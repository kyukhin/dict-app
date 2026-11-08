import XCTest

/// 0131, #158: the Learn tab. Four tabs; with no learned language the
/// picker "Which language do you want to learn?", a row per pair; the Learn
/// home's Today section and its language switch. English UI unless a test
/// says otherwise, `-resetData` first.
///
/// The Greek lists come from the Greek pack, installed from the committed
/// assets as 0237's tests do, except where a test downloads its pair's
/// packs (`-resetPacks`, `-packDownloads`, never the network). The
/// Recognition trainers of `testPickerOffersPairs`,
/// `testLimitedPairShowsItsWarning` and `testLanguageSwitch` (#159) are in
/// `ExerciseFlowTests`: a pair chosen in the picker has no word in learning
/// yet, so its trainers are disabled; the fixtures give them words.
final class LearnTabTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testLanguageSwitch") { return ["-learningFixture", "bilingual"] }
        if name.contains("testNoSwitchWithOneLanguage") { return ["-learningFixture", "myWords5"] }
        if name.contains("testChooseListsWhenNothingToLearn") { return ["-learningLanguages", "ell"] }
        if name.contains("testTrainersOnKeepTheConjugationRow") {
            return ["-learningLanguages", "ell", "-learningLists", "ky-ell-a1"]
        }
        if name.contains("testTrainersOffConjugationRowRightToLeft") {
            return ["-learningLanguages", "ell", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        }
        if name.contains("testLimitedPairShowsItsWarning") { return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"] }
        if name.contains("testSpanishUILearnsEnglishViaSpanish") {
            return ["-AppleLanguages", "(es)", "-AppleLocale", "es"]
        }
        return []
    }

    /// 0237: the packs a test starts from. A pair chosen downloads what is
    /// missing through the fixture protocol: once failing, or offline.
    private var packArguments: [String] {
        if name.contains("testChoosingAPairDownloadsItsPacks") {
            return ["-resetPacks", UITestHelpers.skipWelcome] + UITestHelpers.downloadArguments("failOnce")
        }
        if name.contains("testChoosingAPairOffline") {
            return ["-resetPacks", UITestHelpers.skipWelcome] + UITestHelpers.downloadArguments("offline")
        }
        return UITestHelpers.packArguments()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek, Spanish and other
        // packs installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + learningArguments + packArguments
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
    /// Russian carries its warning. Every pack is installed, so no row has a
    /// size to download.
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
        XCTAssertEqual(sizes.count, 0, "every pack installed: nothing to download")
    }

    /// 0237 with 0131: no pack installed. Greek via English shows the Greek
    /// pack's size; choosing it downloads it (the fixture protocol: the
    /// first request stops halfway): the home shows the failure with Try
    /// again; Try again installs it, the row goes, and Choose lists offers
    /// Greek's lists.
    func testChoosingAPairDownloadsItsPacks() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        let size = learnPage.pickerSize("ell", via: "eng")
        XCTAssertTrue(size.waitForExistence(timeout: TestData.Timeouts.medium), "Greek's pack is to download")
        XCTAssertTrue(size.label.hasSuffix("MB to download"), size.label)
        XCTAssertTrue(learnPage.pickerSize("eng", via: "eng").exists, "English's lists are to download too")

        XCTAssertTrue(learnPage.choosePair("ell", via: "eng"))
        XCTAssertTrue(learnPage.installRetry.waitForExistence(timeout: TestData.Timeouts.long),
                      "the stopped download offers Try again")
        XCTAssertEqual(learnPage.installRow.label, "Greek")
        XCTAssertTrue(learnPage.installError.exists)
        learnPage.installRetry.tap()
        XCTAssertTrue(learnPage.installRow.waitForNonExistence(timeout: TestData.Timeouts.long),
                      "installed: the row goes")
        let newWordsFrom = learnPage.tapChooseLists()
        XCTAssertTrue(newWordsFrom.newWordsFromRow("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.long),
                      "Greek's lists came with its pack")
    }

    /// 0237: no network. Choosing Spanish via English keeps it learned: its
    /// home, and the failure with Try again.
    func testChoosingAPairOffline() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        XCTAssertTrue(learnPage.pickerSize("spa", via: "eng").waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(learnPage.choosePair("spa", via: "eng"))
        XCTAssertTrue(learnPage.installError.waitForExistence(timeout: TestData.Timeouts.medium), "the failure shows")
        XCTAssertEqual(learnPage.installRow.label, "Spanish")
        XCTAssertTrue(learnPage.installRetry.exists)
        XCTAssertTrue(learnPage.importList.exists, "Spanish is learned: its home")
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
    /// lists or tap Learn on a word", no switch, the trainers off with their
    /// footer above the Conjugation row; "Choose lists" opens New words from
    /// with Greek A1, A2 and B1 only.
    func testChooseGreekOffersItsLists() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForPicker())
        XCTAssertTrue(learnPage.choosePair("ell", via: "eng"), "choosing Greek shows the home")
        XCTAssertTrue(app.staticTexts["Choose lists or tap Learn on a word"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.importList.exists, "Greek has lists: no Import a list")
        XCTAssertFalse(learnPage.languageSwitch.exists, "one language: no switch")
        // #159: nothing in learning, so the trainers are off, with the reason.
        XCTAssertTrue(learnPage.trainerRecognition.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.trainerRecognition.isEnabled, "Recognition is off")
        XCTAssertFalse(learnPage.trainerProduction.isEnabled, "Production is off")
        let footer = app.staticTexts["Learn a few words first"]
        XCTAssertTrue(footer.exists)
        // 0132: the footer is the other trainers'; the enabled Conjugation row follows it.
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "the Conjugation row")
        XCTAssertTrue(learnPage.trainerConjugation.isEnabled)
        XCTAssertTrue(footer.exists)
        XCTAssertLessThan(footer.frame.maxY, learnPage.trainerConjugation.frame.minY, "the footer is above the row")
        // Below the Lists and Grammar sections (0133, #172): the lazy List
        // builds it once scrolled to.
        XCTAssertTrue(app.scrollToElement(learnPage.myWordsRow), "My words")
        // Back to Today: `scrollToElement` counts Choose lists as reached while
        // it is still under the navigation bar, where a tap misses it.
        let chooseLists = learnPage.chooseLists
        for _ in 0..<6 where !(chooseLists.exists && chooseLists.frame.minY >= app.navigationBars.firstMatch.frame.maxY) {
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(chooseLists.exists, "back to Today")
        XCTAssertGreaterThanOrEqual(chooseLists.frame.minY, app.navigationBars.firstMatch.frame.maxY,
                                    "Choose lists clear of the navigation bar")

        let newWordsFrom = learnPage.tapChooseLists()
        for id in ["ky-ell-a1", "ky-ell-a2", "ky-ell-b1"] {
            XCTAssertTrue(newWordsFrom.newWordsFromRow(id).waitForExistence(timeout: TestData.Timeouts.medium), id)
        }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "new_words_from_row_"))
        XCTAssertEqual(rows.count, 3, "Greek's lists only")
        XCTAssertTrue(newWordsFrom.noneChecked.exists, "nothing checked")
    }

    /// `-learningLanguages ell`, the Greek lists installed, nothing in
    /// learning: Today reads "Choose lists or tap Learn on a word"; "Choose
    /// lists" opens New words from; after checking Greek A1, the Lists
    /// section shows it and "New words from", and Today its new words.
    func testChooseListsWhenNothingToLearn() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long))
        XCTAssertTrue(app.staticTexts["Choose lists or tap Learn on a word"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.newWordsFromRow.exists, "no New words from row while Today offers Choose lists")
        let newWordsFrom = learnPage.tapChooseLists()
        let greekA1 = newWordsFrom.newWordsFromRow("ky-ell-a1")
        XCTAssertTrue(greekA1.waitForExistence(timeout: TestData.Timeouts.medium))
        greekA1.tap()
        XCTAssertTrue(newWordsFrom.wait(for: greekA1, selected: true), "checked")
        newWordsFrom.goBack()

        XCTAssertTrue(learnPage.listRow("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium),
                      "the Lists section shows Greek A1")
        XCTAssertTrue(learnPage.newWordsFromRow.exists, "and New words from")
        XCTAssertFalse(learnPage.chooseLists.exists, "Choose lists has done its job")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "10 new words left today"))
        learnPage.newWordsFromRow.tap()
        XCTAssertTrue(newWordsFrom.waitForNewWordsFrom(), "the row opens New words from")
        XCTAssertTrue(newWordsFrom.newWordsFromRow("ky-ell-a1").isSelected)
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

    /// QA, PR #281 (0132): with words to learn the trainers are on, there
    /// is no "Learn a few words first", and the Conjugation row is the last
    /// row of the Trainers section, right below Match the pairs.
    func testTrainersOnKeepTheConjugationRow() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(learnPage.trainerRecognition.waitForExistence(timeout: TestData.Timeouts.medium))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"),
                                                object: learnPage.trainerRecognition)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: TestData.Timeouts.medium), .completed, "Recognition is on")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "the Conjugation row")
        XCTAssertTrue(learnPage.trainerConjugation.isEnabled)
        XCTAssertTrue(learnPage.trainerMatch.exists, "Match the pairs")
        XCTAssertEqual(learnPage.trainerConjugation.frame.minY, learnPage.trainerMatch.frame.maxY, accuracy: 2,
                       "the next row of the same section")
        XCTAssertFalse(app.staticTexts["Learn a few words first"].exists, "no footer while the trainers are on")
    }

    /// QA, PR #281 (0132): the trainers off in Arabic: their footer, read
    /// from the right, sits between Match the pairs and the Conjugation
    /// row, which is enabled and reads "تصريف الأفعال".
    func testTrainersOffConjugationRowRightToLeft() throws {
        let learnTab = app.tabButton(labeled: "تعلّم")
        XCTAssertTrue(learnTab.waitForExistence(timeout: TestData.Timeouts.long), "the Learn tab in Arabic")
        learnTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let learnPage = LearnPage(app: app)
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(learnPage.trainerRecognition.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.trainerRecognition.isEnabled, "Recognition is off")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "the Conjugation row")
        let row = learnPage.trainerConjugation
        XCTAssertTrue(row.isEnabled, "Conjugation works without learned words")
        XCTAssertEqual(row.label, "تصريف الأفعال")
        let footer = app.staticTexts["ابدأ بتعلّم بضع كلمات أولًا"]
        XCTAssertTrue(footer.exists, "the trainers' footer")
        // The footer's frame starts where the section's last row ends.
        XCTAssertLessThanOrEqual(learnPage.trainerMatch.frame.maxY, footer.frame.minY, "below Match the pairs")
        XCTAssertLessThan(footer.frame.maxY, row.frame.minY, "above the Conjugation row")
        // RTL, read from the row's pixels (its frame is full width): the
        // title, the primary ink, on the right; the level and chevron left.
        let rowInk = try XCTUnwrap(ConjugationPage(app: app).inkColumns(of: row), "the row's text")
        XCTAssertGreaterThan(rowInk.strong.lowerBound, row.frame.width / 2, "RTL: the title on the right: \(rowInk)")
        XCTAssertLessThan(rowInk.ink.lowerBound, row.frame.width / 4, "the level and chevron on the left: \(rowInk)")
    }
}
