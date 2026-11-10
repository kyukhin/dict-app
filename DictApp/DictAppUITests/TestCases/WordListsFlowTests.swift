import XCTest

/// 0130, #154: the Lists screen, a list's screen and New words from,
/// reached from the Learn home. English UI, `-resetData`, the built-in lists
/// from the Greek pack and the English lists pack (with the Spanish pack for
/// English via Spanish), installed from the committed assets
/// (`UITestHelpers.packArguments`). Greek and English learned unless a test
/// says otherwise. `-wordListFixture lists` adds two imported lists until
/// #155's import: "Greek fixture" (σπίτι το, γράφω, έχει αέρα at A1, αγάπη η
/// at A2, βιβλίο without a level or translation) and the newer "English
/// fixture" (house, water).
final class WordListsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private let greekFixture = "user-fixture-greek"
    private let englishFixture = "user-fixture-english"

    /// Launch arguments after `-resetData`, per test.
    private var testArguments: [String] {
        if name.contains("testListsFollowLearnedLanguages") || name.contains("testChooseListsOpensNewWordsFrom") {
            return ["-learningLanguages", "ell", "-wordListFixture", "lists"]
        }
        if name.contains("testEnglishListMeaningsFollowTheVia") { return ["-learningLanguages", "eng:spa"] }
        if name.contains("testListRowsShowProgress") { return ["-learningFixture", "due"] }
        if name.contains("testNewWordsFromCheckedLists") {
            // #161's Start, every question a choice answered by its hint.
            return ["-learningLanguages", "ell:eng,eng:eng", "-learningAnswerHints", "-learningSeed", "154",
                    "-learning_answer_mode", "choice"]
        }
        return ["-learningLanguages", "ell,eng", "-wordListFixture", "lists"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + testArguments + UITestHelpers.packArguments()
        // Lists of thousands of rows: silence the app's os_log so XCTest's
        // log volume cannot crash it while it scrolls (iOS 17.5, #125).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Helpers

    /// Learn tab → home → All lists.
    private func openLists() -> WordListsPage {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        return learnPage.tapAllLists()
    }

    /// The Lists screen → list `id`.
    private func openList(_ id: String) -> WordListsPage {
        let page = openLists()
        page.openList(id)
        return page
    }

    // MARK: - Built-in lists

    /// Greek and English learned, English UI: the Greek section, then the
    /// English one, then My lists, each built-in list with its word count.
    func testBuiltInListsShowTheirCounts() throws {
        let page = openLists()
        let counts = [("ky-ell-a1", "1,457 words"), ("ky-ell-a2", "756 words"), ("ky-ell-b1", "2,435 words"),
                      ("cefr-eng-a1", "1,063 words"), ("cefr-eng-a2", "1,241 words"), ("cefr-eng-b1", "2,138 words"),
                      ("cefr-eng-b2", "2,417 words"), ("cefr-eng-c1", "913 words"), ("cefr-eng-c2", "875 words")]
        XCTAssertTrue(page.row("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1")
        XCTAssertTrue(app.staticTexts["Greek A1"].exists, "titled by language and level")
        for (id, count) in counts {
            let row = page.row(id)
            XCTAssertTrue(app.scrollToElement(row), id)
            XCTAssertEqual(page.count(id).label, count, id)
        }
        XCTAssertTrue(app.staticTexts["English C2"].exists)
        XCTAssertTrue(app.scrollToElement(page.row("my-words")), "My lists follow")
        // iPad: the imports may sit below the window once My words shows.
        XCTAssertTrue(app.scrollToElement(page.row(englishFixture)), "the newer import")
        XCTAssertTrue(app.scrollToElement(page.row(greekFixture)), "the older import")
    }

    /// Greek B1 is one section of its own 2,435 words, alphabetical from
    /// αγγίζω to ωφελώ; σπίτι, an A1 word, is not in it.
    func testGreekB1ShowsAllItsWords() throws {
        let page = openList("ky-ell-b1")
        XCTAssertTrue(app.navigationBars["Greek B1"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(app.staticTexts["2,435 words"].exists, "the count at the top")
        XCTAssertTrue(page.word("αγγίζω").waitForExistence(timeout: TestData.Timeouts.medium), "the first word")
        XCTAssertFalse(app.staticTexts["B1"].exists, "one level: no section header")
        XCTAssertTrue(page.scrollTo(page.word("ωφελώ"), maxSwipes: 80, velocity: WordListsPage.bottomVelocity),
                      "the last word")
        XCTAssertFalse(page.word("σπίτι").exists, "an A1 word is not in B1")
    }

    /// `-learningLanguages ell`: the Greek section and My lists with My
    /// words and the Greek import, no English list; the "+" is there.
    func testListsFollowLearnedLanguages() throws {
        let page = openLists()
        XCTAssertTrue(page.row("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1")
        XCTAssertFalse(page.row("cefr-eng-a1").exists, "English is not learned: no English list")
        XCTAssertFalse(app.staticTexts["English"].exists, "no English section")
        XCTAssertTrue(app.scrollToElement(page.row("my-words")), "My words")
        XCTAssertTrue(page.row(greekFixture).exists, "the Greek import")
        XCTAssertFalse(page.row(englishFixture).exists, "English is not learned: its import hides")
        XCTAssertEqual(page.count(greekFixture).label, "5 words")
        XCTAssertEqual(page.count("my-words").label, "0 words")
        XCTAssertLessThan(page.row("my-words").frame.minY, page.row(greekFixture).frame.minY, "My words first")
        XCTAssertTrue(page.importButton.exists, "the + of Import (#155)")
        XCTAssertTrue(app.navigationBars["Lists"].exists, "titled Lists")
    }

    /// σπίτι in Greek A1 opens its Definition, in the pair's first dictionary.
    func testTapOpensDefinition() throws {
        let page = openList("ky-ell-a1")
        let spiti = page.word("σπίτι")
        XCTAssertTrue(page.scrollFromBottom(to: "σπίτι", last: "ωστόσο"), "σπίτι, 284 words before the end of Greek A1")
        XCTAssertTrue(page.wait(for: spiti, "value", toBe: "house, residence; (family) home"), "Kirill's translation")
        spiti.tap()
        let definition = DefinitionPage(app: app)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "σπίτι opens its Definition")
        XCTAssertTrue(app.navigationBars["σπίτι"].waitForExistence(timeout: TestData.Timeouts.medium))
    }

    /// έχει αέρα (Greek A2) has no entry: it shows "it is windy", is not a
    /// button and pushes nothing.
    func testStandaloneWordShowsItsTranslation() throws {
        let page = openList("ky-ell-a2")
        let windy = page.word("έχει αέρα")
        XCTAssertTrue(page.scrollTo(windy, maxSwipes: 20), "έχει αέρα in Greek A2")
        XCTAssertTrue(page.wait(for: windy, "value", toBe: "it is windy"))
        XCTAssertFalse(app.buttons.matching(identifier: AccessibilityIdentifiers.WordLists.item)
                        .matching(NSPredicate(format: "label == %@", "έχει αέρα")).firstMatch.exists,
                       "no chevron: not a button")
        windy.tap()
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView]
                        .waitForExistence(timeout: TestData.Timeouts.short), "tapping it pushes nothing")
        XCTAssertTrue(page.listScreen.exists)
    }

    /// `-learningLanguages eng:spa`: English A1's house reads En–Es · FD's
    /// "casalicio, casa". After changing the via to English in Settings
    /// (#162), WordNet's first sense.
    func testEnglishListMeaningsFollowTheVia() throws {
        var page = openList("cefr-eng-a1")
        let house = page.word("house")
        XCTAssertTrue(page.scrollTo(house, maxSwipes: 80), "house in English A1")
        XCTAssertTrue(page.wait(for: house, "value", toBe: "casalicio, casa"), "via Spanish; got \(house.value ?? "")")

        tabBarPage.tapSettingsTab()
        let settings = LearningSettingsPage(app: app)
        XCTAssertTrue(settings.openLanguages(), "Settings → Learning → Languages")
        settings.chooseVia("via English", for: "eng")

        let learnPage = tabBarPage.tapLearnTab()
        learnPage.popToRoot()
        XCTAssertTrue(learnPage.waitForHome(), "the Learn home")
        page = learnPage.tapAllLists()
        page.openList("cefr-eng-a1")
        let viaEnglish = page.word("house")
        XCTAssertTrue(page.scrollTo(viaEnglish, maxSwipes: 80), "house via English")
        XCTAssertTrue(page.wait(for: viaEnglish, "value",
                                toBe: "a dwelling that serves as living quarters for one or more families"),
                      "via English; got \(viaEnglish.value ?? "")")
    }

    // MARK: - Learn this list, New words from

    /// Learn this list on Greek A1, then English B1: both rows carry the
    /// badge and the button reads "Learning this list"; a second tap on
    /// English B1 removes its badge; Greek A1's survives a relaunch.
    func testLearnThisListAddsTheBadge() throws {
        let page = openList("ky-ell-a1")
        XCTAssertEqual(page.learnButton.label, "Learn this list")
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.goBack()
        XCTAssertTrue(page.badge("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1's badge")
        XCTAssertEqual(page.badge("ky-ell-a1").label, "Learning")

        page.openList("cefr-eng-b1")
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.goBack()
        XCTAssertTrue(page.badge("cefr-eng-b1").waitForExistence(timeout: TestData.Timeouts.medium), "English B1's badge")
        XCTAssertTrue(app.scrollToElement(page.row("ky-ell-a1")))
        XCTAssertTrue(page.badge("ky-ell-a1").exists)

        page.openList("cefr-eng-b1")
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learn this list"), "a second tap unchecks")
        page.goBack()
        XCTAssertTrue(page.badge("cefr-eng-b1").waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "English B1's badge goes")

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"] + UITestHelpers.packArguments()
        app.launch()
        tabBarPage = TabBarPage(app: app)
        let relaunched = openLists()
        XCTAssertTrue(relaunched.badge("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium),
                      "kept after a relaunch")
        XCTAssertFalse(relaunched.badge("cefr-eng-b1").exists)
    }

    /// Greek only: "Choose lists" opens New words from with Greek A1, A2,
    /// B1 and the Greek import, unchecked, and the footer; checking Greek A1
    /// hides the footer; back home, the Lists section shows it with "New
    /// words from", and Today counts its new words.
    func testChooseListsOpensNewWordsFrom() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long))
        XCTAssertFalse(learnPage.newWordsFromRow.exists, "Today offers Choose lists instead")
        let page = learnPage.tapChooseLists()
        XCTAssertTrue(app.staticTexts["Lower levels come first: A1, then A2 and up. Lists without levels come last."].exists)
        for id in ["ky-ell-a1", "ky-ell-a2", "ky-ell-b1", greekFixture] {
            XCTAssertTrue(page.newWordsFromRow(id).waitForExistence(timeout: TestData.Timeouts.medium), id)
            XCTAssertFalse(page.newWordsFromRow(id).isSelected, id)
        }
        XCTAssertFalse(page.newWordsFromRow("cefr-eng-a1").exists, "English is not learned")
        XCTAssertFalse(page.newWordsFromRow(englishFixture).exists, "English is not learned")
        XCTAssertFalse(page.newWordsFromRow("my-words").exists, "My words is not on it")
        XCTAssertTrue(page.noneChecked.exists, "No list checked.")

        let row = page.newWordsFromRow("ky-ell-a1")
        row.tap()
        XCTAssertTrue(page.wait(for: row, selected: true), "checked")
        XCTAssertTrue(page.noneChecked.waitForNonExistence(timeout: TestData.Timeouts.medium))
        page.goBack()

        XCTAssertTrue(learnPage.listRow("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium),
                      "the Lists section shows the checked list")
        XCTAssertTrue(learnPage.newWordsFromRow.exists, "and New words from")
        XCTAssertFalse(learnPage.chooseLists.exists)
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "10 new words left today"))
    }

    /// Greek and English learned: "Choose lists" checks Greek A1 and English
    /// C2; the language switch shows. With English chosen, Start's new
    /// words, with the "New word" badge, are English; closed, then with
    /// Greek chosen, Start's are Greek: new words come from the checked
    /// lists of the chosen language only (0130, #161's Start).
    func testNewWordsFromCheckedLists() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long))
        let page = learnPage.tapChooseLists()
        let greekA1 = page.newWordsFromRow("ky-ell-a1")
        XCTAssertTrue(greekA1.waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1")
        greekA1.tap()
        XCTAssertTrue(page.wait(for: greekA1, selected: true))
        let englishC2 = page.newWordsFromRow("cefr-eng-c2")
        XCTAssertTrue(app.scrollToElement(englishC2), "English C2")
        englishC2.tap()
        XCTAssertTrue(page.wait(for: englishC2, selected: true))
        page.goBack()

        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "Greek | English")
        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "10 new words left today"), "English C2")
        assertNewWords(greek: false, learnPage: learnPage)

        learnPage.selectLanguage(named: "Greek")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "10 new words left today"), "Greek A1")
        assertNewWords(greek: true, learnPage: learnPage)
    }

    /// Start, then the first three questions: each carries the "New word"
    /// badge and asks a word of the chosen language, Greek or English. A
    /// recognition question shows the word; a production question offers
    /// words, so the word is in the prompt or in the right option. Then
    /// the run closes.
    private func assertNewWords(greek: Bool, learnPage: LearnPage, file: StaticString = #filePath, line: UInt = #line) {
        let run = learnPage.startSession()
        var previous: String?
        for question in 1...3 {
            let deadline = Date().addingTimeInterval(TestData.Timeouts.long)
            while !(run.prompt.exists && !run.feedback.exists && run.progress.label != previous), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.15)
            }
            previous = run.progress.label
            XCTAssertTrue(run.newBadge.exists, "question \(question): a new word", file: file, line: line)
            let texts = [run.prompt.label] + run.options.map(\.label)
            let shown = greek ? [run.prompt.label, run.rightOption?.label ?? ""] : texts
            XCTAssertEqual(shown.contains(where: Self.hasGreek), greek,
                           "question \(question) asks a \(greek ? "Greek" : "English") word: \(texts)", file: file, line: line)
            XCTAssertNotNil(run.choose(right: true), "question \(question): the answer hint", file: file, line: line)
            XCTAssertEqual(run.waitForFeedback(), "right", file: file, line: line)
            run.tapContinue()
        }
        XCTAssertTrue(run.closeButton.waitForExistence(timeout: TestData.Timeouts.medium), file: file, line: line)
        run.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "closed", file: file, line: line)
    }

    /// A letter of the Greek or Greek Extended blocks.
    private static func hasGreek(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }

    /// New words from lists both languages' lists; a second tap unchecks;
    /// the Lists screen's badges follow.
    func testNewWordsFromChecksAndUnchecks() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long))
        let page = learnPage.tapChooseLists()
        let greekRow = page.newWordsFromRow("ky-ell-a2")
        let englishRow = page.newWordsFromRow("cefr-eng-c2")
        XCTAssertTrue(greekRow.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(app.scrollToElement(englishRow))
        englishRow.tap()
        XCTAssertTrue(page.wait(for: englishRow, selected: true))
        XCTAssertTrue(app.scrollToElement(greekRow))
        greekRow.tap()
        XCTAssertTrue(page.wait(for: greekRow, selected: true))
        XCTAssertTrue(app.scrollToElement(englishRow))
        englishRow.tap()
        XCTAssertTrue(page.wait(for: englishRow, selected: false), "a second tap unchecks")
        page.goBack()
        let lists = learnPage.tapAllLists()
        XCTAssertTrue(lists.badge("ky-ell-a2").waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(lists.badge("cefr-eng-c2").exists)
    }

    // MARK: - Progress (0166)

    /// `-learningFixture due` (Greek): five Greek A1 words in learning and
    /// βιβλίο learned. Greek A1's bar reads its learned / learning / new;
    /// Greek A2, with no word started, reads all new; the Learn home's
    /// Lists section shows the same bar for the checked Greek A1.
    func testListRowsShowProgress() throws {
        let page = openLists()
        let a1 = page.progress("ky-ell-a1")
        XCTAssertTrue(a1.waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1's bar")
        XCTAssertEqual(a1.label, "1 learned · 5 learning · 1,451 new")
        XCTAssertEqual(page.progress("ky-ell-a2").label, "0 learned · 0 learning · 756 new")
        XCTAssertTrue(app.scrollToElement(page.row("my-words")))
        XCTAssertEqual(page.progress("my-words").label, "1 learned · 5 learning · 0 new", "My words' Greek words")

        page.openList("ky-ell-a1")
        page.learnButton.tap()
        XCTAssertTrue(page.wait(for: page.learnButton, toBe: "Learning this list"))
        let learnPage = LearnPage(app: app)
        learnPage.popToRoot()
        let homeBar = learnPage.listProgress("ky-ell-a1")
        XCTAssertTrue(app.scrollToElement(homeBar), "the Learn home shows the checked list's bar")
        XCTAssertEqual(homeBar.label, "1 learned · 5 learning · 1,451 new")
    }

    // MARK: - Imported lists and My words

    /// Greek and English learned: both imports, newest first, with counts.
    func testImportedListsShowTheirCounts() throws {
        let page = openLists()
        XCTAssertTrue(app.scrollToElement(page.row(englishFixture), maxSwipes: 12))
        XCTAssertTrue(app.scrollToElement(page.row(greekFixture)))
        XCTAssertEqual(page.count(englishFixture).label, "2 words")
        XCTAssertEqual(page.count(greekFixture).label, "5 words")
        XCTAssertLessThan(page.row(englishFixture).frame.minY, page.row(greekFixture).frame.minY, "the newer import first")
    }

    /// An imported list's screen: the words alphabetical in a section per
    /// level (A1, A2, then none), each with its meaning: the import's
    /// translation, else the pair's dictionary.
    func testImportedListShowsItsWordsByLevel() throws {
        let page = openLists()
        XCTAssertTrue(app.scrollToElement(page.row(greekFixture), maxSwipes: 12))
        page.openList(greekFixture)
        XCTAssertTrue(app.navigationBars["Greek fixture"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(app.staticTexts["5 words"].exists, "the count at the top")
        let terms = ["γράφω", "έχει αέρα", "σπίτι", "αγάπη", "βιβλίο"]
        for term in terms {
            XCTAssertTrue(page.word(term).waitForExistence(timeout: TestData.Timeouts.medium), term)
        }
        let tops = terms.map { page.word($0).frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "A1 alphabetical, then A2, then the word without a level")
        XCTAssertTrue(page.wait(for: page.word("σπίτι"), "value", toBe: "house"), "the import's translation")
        XCTAssertTrue(page.wait(for: page.word("βιβλίο"), "value", toBe: "book"),
                      "no translation: El–En · FD's first sense, the pair's first dictionary")
        XCTAssertTrue(app.staticTexts["A1"].exists && app.staticTexts["A2"].exists, "a header per level")
    }

    /// Swipe to delete an imported list, after an alert; Cancel keeps it.
    func testDeleteImportedList() throws {
        let page = openLists()
        XCTAssertTrue(app.scrollToElement(page.row(greekFixture), maxSwipes: 12))
        page.swipeToDelete(greekFixture)
        let alert = app.alerts["Delete “Greek fixture”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert asks first")
        XCTAssertTrue(alert.staticTexts["Progress on its words is kept."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(page.row(greekFixture).waitForExistence(timeout: TestData.Timeouts.medium), "Cancel keeps it")

        page.swipeToDelete(greekFixture)
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(page.row(greekFixture).waitForNonExistence(timeout: TestData.Timeouts.medium), "Delete removes it")
        XCTAssertTrue(page.row(englishFixture).exists)
    }

    /// My words opens its list screen: no Learn this list, its words with
    /// a snippet of their entry.
    func testMyWordsIsAList() throws {
        let search = tabBarPage.tapSearchTab()
        search.searchFor("γράφω")
        XCTAssertTrue(search.waitForResults())
        let definition = search.tapResult(word: "γράφω", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(definition.waitForDefinitionToLoad())
        definition.learn()

        let myWords = tabBarPage.tapLearnTab().tapMyWords()
        XCTAssertTrue(myWords.waitForWord("γράφω"))
        let page = WordListsPage(app: app)
        XCTAssertTrue(page.listScreen.exists, "E3's list screen")
        XCTAssertFalse(page.learnButton.exists, "My words has no Learn this list")
        let snippet = page.word("γράφω").value as? String ?? ""
        XCTAssertTrue(snippet.contains("write"), "a snippet of its entry; got '\(snippet)'")
    }
}
