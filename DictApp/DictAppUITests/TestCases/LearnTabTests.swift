import XCTest

/// 0131, #158: the Learn tab. Four tabs; with no learned language the
/// picker "Which language do you want to learn?", a row per pair; the Learn
/// home's Today section and its language switch. English UI unless a test
/// says otherwise, `-resetData` first.
///
/// From the test plan, `testChooseGreekOffersItsLists` waits for 0237's
/// install of the Greek lists and E3's "Choose lists" (#154): here Greek only
/// shows its empty state. The download sizes under the rows wait for #241's
/// packs, the Recognition trainers of `testPickerOffersPairs`,
/// `testLimitedPairShowsItsWarning` and `testLanguageSwitch` for #159.
final class LearnTabTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testLanguageSwitch") { return ["-learningFixture", "bilingual"] }
        if name.contains("testNoSwitchWithOneLanguage") { return ["-learningFixture", "myWords5"] }
        if name.contains("testLimitedPairShowsItsWarning") { return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"] }
        if name.contains("testSpanishUILearnsEnglishViaSpanish") {
            return ["-AppleLanguages", "(es)", "-AppleLocale", "es"]
        }
        return []
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek, Spanish and other
        // packs installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + learningArguments
            + UITestHelpers.packArguments()
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Tests

    /// Search, Learn, History, Settings, in that order: the iPhone tab bar
    /// by index, the iPadOS 26 strip by SF Symbol.
    func testFourTabsInOrder() throws {
        let labels: [TabBarPage.Tab: String] = [.search: "Search", .learn: "Learn", .history: "History",
                                                .settings: "Settings"]
        for tab in TabBarPage.Tab.allCases {
            let button = app.tabButton(tab)
            XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.medium), "\(tab) tab")
            XCTAssertEqual(button.label, labels[tab], "tab \(tab.rawValue)")
        }
        XCTAssertFalse(app.tabButton(labeled: "Bookmarks").exists, "Bookmarks is gone")
        if app.usesFloatingTabStrip {
            let frames = TabBarPage.Tab.allCases.map { app.tabButton($0).frame.midX }
            XCTAssertEqual(frames, frames.sorted(), "the strip's tabs read left to right in order")
        }
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(tabBarPage.verifyLearnTabSelected())
        XCTAssertTrue(learnPage.waitForLearnToLoad(), "the Learn tab shows the picker or the home")
    }

    /// No learned language, English UI: a row per pair, the languages with
    /// lists first (English, Greek), then the others by name; within a
    /// language its default via first, then the others by name. Greek via
    /// Russian carries its warning. Every dictionary is bundled until #241,
    /// so no row has a size to download.
    func testPickerOffersPairs() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker(), "no learned language: the picker")
        XCTAssertTrue(app.staticTexts["Which language do you want to learn?"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "With word lists")).firstMatch.exists,
                      "the languages with lists are captioned")
        let order = [("eng", "eng"), ("eng", "ell"), ("eng", "spa"), ("ell", "eng"), ("ell", "rus"),
                     ("arb", "eng"), ("rus", "eng"), ("spa", "eng")]
        for (lang, via) in order {
            XCTAssertTrue(learnPage.pickerRow(lang, via: via).waitForExistence(timeout: TestData.Timeouts.short),
                          "row \(lang)-\(via)")
        }
        let tops = order.map { learnPage.pickerRow($0.0, via: $0.1).frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "rows in the order \(order)")
        XCTAssertEqual(learnPage.pickerRow("ell", via: "eng").label, "Greek via English")
        XCTAssertEqual(learnPage.pickerRow("eng", via: "spa").label, "English via Spanish")
        XCTAssertFalse(learnPage.pickerRow("eng", via: "rus").exists, "no English via Russian in 2.0")
        XCTAssertFalse(learnPage.pickerRow("eng", via: "arb").exists, "no English via Arabic in 2.0")

        let warning = learnPage.pickerLimited("ell", via: "rus")
        XCTAssertTrue(warning.exists, "Greek via Russian is limited")
        XCTAssertEqual(warning.label, "Words are practised in English.")
        XCTAssertGreaterThan(warning.frame.minY, learnPage.pickerRow("ell", via: "rus").frame.minY, "under its row")
        XCTAssertFalse(learnPage.pickerLimited("ell", via: "eng").exists, "a full pair has no warning")
        let sizes = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                                                         "language_picker_size_"))
        XCTAssertEqual(sizes.count, 0, "until #241 every pack is bundled: nothing to download")
    }

    /// Spanish UI: English's default via is Spanish, so English via Spanish
    /// is its first row; Greek has no pair via Spanish and keeps English.
    func testSpanishUILearnsEnglishViaSpanish() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        let english = [("eng", "spa"), ("eng", "ell"), ("eng", "eng")]
        for (lang, via) in english {
            XCTAssertTrue(learnPage.pickerRow(lang, via: via).waitForExistence(timeout: TestData.Timeouts.short),
                          "row \(lang)-\(via)")
        }
        let tops = english.map { learnPage.pickerRow($0.0, via: $0.1).frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "the default via first, then Griego, Inglés")
        XCTAssertEqual(learnPage.pickerRow("eng", via: "spa").label, "Inglés desde el español")
        XCTAssertFalse(learnPage.pickerRow("ell", via: "spa").exists, "no Greek via Spanish")
        XCTAssertTrue(learnPage.pickerRow("ell", via: "eng").exists)
    }

    /// Russian UI: Greek via Russian, the limited pair, is Greek's first
    /// row, with its warning; Greek via English has none. Choosing it shows
    /// the Greek home.
    func testLimitedPairShowsItsWarning() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        let limited = learnPage.pickerRow("ell", via: "rus")
        XCTAssertTrue(limited.waitForExistence(timeout: TestData.Timeouts.medium), "Greek via Russian is offered")
        XCTAssertEqual(limited.label, "Греческий через русский")
        let full = learnPage.pickerRow("ell", via: "eng")
        XCTAssertTrue(full.exists)
        XCTAssertLessThan(limited.frame.minY, full.frame.minY, "the Russian UI's default via comes first")
        let warning = learnPage.pickerLimited("ell", via: "rus")
        XCTAssertTrue(warning.exists, "its row warns")
        XCTAssertEqual(warning.label, "Слова тренируются с переводом на английский.")
        XCTAssertFalse(learnPage.pickerLimited("ell", via: "eng").exists)

        XCTAssertTrue(learnPage.choosePair("ell", via: "rus"), "choosing it shows the home")
        XCTAssertTrue(app.staticTexts["Выберите списки или нажмите «Учить» на слове"]
            .waitForExistence(timeout: TestData.Timeouts.medium), "Greek's empty state")
    }

    /// Choosing Greek via English, Greek having lists: the home, "Choose
    /// lists or tap Learn on a word", no switch.
    func testChooseGreekShowsItsHome() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        XCTAssertTrue(learnPage.choosePair("ell", via: "eng"), "choosing Greek shows the home")
        XCTAssertTrue(app.staticTexts["Choose lists or tap Learn on a word"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.importList.exists, "Greek has lists: no Import a list")
        XCTAssertFalse(learnPage.languageSwitch.exists, "one language: no switch")
        XCTAssertTrue(learnPage.myWordsRow.exists)
    }

    /// Spanish via English, Spanish having no lists: "Import a list" and
    /// "Add words with Learn on a word's screen.", no "Choose lists".
    func testLanguageWithoutListsOffersImportAndLearn() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        XCTAssertTrue(learnPage.choosePair("spa", via: "eng"))
        XCTAssertTrue(learnPage.importList.waitForExistence(timeout: TestData.Timeouts.medium), "Import a list")
        XCTAssertTrue(learnPage.addWordsHint.exists)
        XCTAssertEqual(learnPage.addWordsHint.label, "Add words with Learn on a word's screen.")
        XCTAssertFalse(app.staticTexts["Choose lists or tap Learn on a word"].exists)
    }

    /// `-learningFixture bilingual`: the switch shows Greek | English;
    /// English has 2 words due; the choice survives a relaunch.
    func testLanguageSwitch() throws {
        var learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "two languages: the switch")
        XCTAssertTrue(learnPage.languageSwitch.buttons["Greek"].isSelected, "the first learned language first")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"))

        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"), "house and water")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "0 new words left today"))

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"] + UITestHelpers.packArguments()
        app.launch()
        tabBarPage = TabBarPage(app: app)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(learnPage.languageSwitch.buttons["English"].isSelected, "the choice is remembered")
    }

    /// `-learningFixture myWords5`: one language, no switch; five new words.
    func testNoSwitchWithOneLanguage() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "5 new words left today"))
        XCTAssertEqual(learnPage.dueCount.label, "0 words due")
        XCTAssertFalse(learnPage.languageSwitch.exists, "one language: no switch")
        let myWords = learnPage.tapMyWords()
        for word in ["γράφω", "σπίτι", "νερό", "καλός", "είμαι"] {
            XCTAssertTrue(myWords.waitForWord(word), "My words lists \(word)")
        }
    }
}
