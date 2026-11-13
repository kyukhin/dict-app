import XCTest

/// 0131, #158: the Learn button on the Definition screen and My words, the
/// former Bookmarks flow. English UI. Every test but the persistence one
/// starts from `-resetData` with English and Greek learned
/// (`-learningLanguages eng,ell`), so Learn adds a word at once; the "Learn
/// %@ via %@?" tests learn Greek only, or nothing in a Russian UI.
final class MyWordsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// The arguments each test launches with after `-resetData`: the
    /// learned languages, or a Russian UI with none.
    private var testArguments: [String] {
        if name.contains("testLearnGreekInRussianUIWarns") { return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"] }
        return ["-learningLanguages", name.contains("testLearnOnANewLanguageAsks") ? "ell" : "eng,ell"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        // Issue #237: no first-launch sheet; the Greek pack and the others
        // installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + testArguments + UITestHelpers.packArguments()
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Helpers

    /// Searches `term` and opens its first result (or `source`'s row).
    private func openDefinition(_ term: String, source: String? = nil) -> DefinitionPage {
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(term)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(term)'")
        let definitionPage = source.map { searchPage.tapResult(word: term, source: $0) }
            ?? searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(term)'")
        return definitionPage
    }

    /// Learn tab → home → `lang`'s tab, when given → My words. Each tab's
    /// My words lists its language's words only (#295); the first learned
    /// language's tab shows first.
    private func openMyWords(on lang: String? = nil) -> MyWordsPage {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(), "the Learn home should show with a learned language")
        if let lang {
            learnPage.selectTab(lang)
        }
        let myWords = learnPage.tapMyWords()
        XCTAssertTrue(myWords.waitForMyWordsToLoad(), "My words should load")
        return myWords
    }

    // MARK: - Tests

    /// Learn on a word adds it to My words.
    func testBasicLearnFlow() throws {
        let term = TestData.learnTestWords[0] // "apple"
        let definitionPage = openDefinition(term)
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Learn"), "an outlined cap reads 'Learn'")
        definitionPage.learn()

        let myWords = openMyWords()
        XCTAssertTrue(myWords.waitForWord(term), "My words should list '\(term)'")
    }

    func testMultipleWords() throws {
        for term in TestData.learnTestWords {
            openDefinition(term).learn()
        }
        let myWords = openMyWords()
        for term in TestData.learnTestWords {
            XCTAssertTrue(myWords.waitForWord(term), "My words should list '\(term)'")
        }
        XCTAssertGreaterThanOrEqual(myWords.count, TestData.learnTestWords.count)
    }

    func testMyWordsOpensTheDefinition() throws {
        let term = TestData.learnTestWords[0]
        openDefinition(term).learn()

        let myWords = openMyWords()
        let definitionPage = myWords.tapWord(term)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load from My words")
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Stop learning"), "a filled cap reads 'Stop learning'")
    }

    /// Search γράφω, Learn: the Greek tab's My words lists it; Stop
    /// learning: gone.
    func testLearnButtonAddsAndRemoves() throws {
        let term = "γράφω"
        openDefinition(term, source: TestData.Sources.freedictEllEng).learn()
        var myWords = openMyWords(on: "ell")
        XCTAssertTrue(myWords.waitForWord(term), "My words should list '\(term)'")

        let definitionPage = openDefinition(term, source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Stop learning"))
        definitionPage.tapLearnButton()
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Learn"), "Stop learning gives back an outlined cap")

        myWords = openMyWords(on: "ell")
        XCTAssertTrue(myWords.waitForEmpty(), "My words should be empty after Stop learning")
    }

    /// The swipe is Stop learning: the word leaves My words and learning,
    /// so its Definition reads "Learn" again.
    func testStopLearningFromMyWordsSwipe() throws {
        let term = TestData.learnTestWords[0]
        openDefinition(term).learn()

        let myWords = openMyWords()
        XCTAssertTrue(myWords.waitForWord(term))
        myWords.stopLearning(term)
        XCTAssertTrue(myWords.waitForWordToDisappear(term), "the swipe removes '\(term)'")

        let definitionPage = openDefinition(term)
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Learn"), "the word left learning too")
    }

    /// The button's state and My words survive a relaunch.
    func testLearnButtonStatePersists() throws {
        let term = TestData.learnTestWords[1] // "test"
        openDefinition(term).learn()

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"] + UITestHelpers.packArguments()
        app.launch()
        tabBarPage = TabBarPage(app: app)

        let myWords = openMyWords()
        XCTAssertTrue(myWords.waitForWord(term), "'\(term)' should stay in My words after a relaunch")
        let definitionPage = openDefinition(term)
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Stop learning"), "and the button stays filled")
    }

    /// γράφω from El–En · WN shows the filled cap after Learn on El–En · FD:
    /// it is the same word.
    func testWordFromAnotherDictionaryIsTheSameWord() throws {
        let term = "γράφω"
        openDefinition(term, source: TestData.Sources.freedictEllEng).learn()
        let other = openDefinition(term, source: TestData.Sources.wordnetEllEng)
        XCTAssertTrue(other.waitForLearnButtonLabel("Stop learning"),
                      "El–En · WN's γράφω is in learning; got '\(other.learnButton.label)'")
    }

    /// `-learningLanguages ell`, English UI: Learn on "house" asks "Learn
    /// English via English?", the default pair; No adds it to My words and
    /// learns no language, so it shows on no tab (#295); Learn on "water",
    /// Yes: an English tab next to Greek, whose My words lists both.
    func testLearnOnANewLanguageAsks() throws {
        let house = openDefinition("house")
        house.tapLearnButton()
        XCTAssertTrue(app.alerts["Learn English via English?"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "Learn on an English word asks 'Learn English via English?'")
        XCTAssertFalse(app.alerts.firstMatch.staticTexts["Words are practised in English."].exists, "a full pair: no warning")
        house.answerLearnLanguageAlert("No")
        XCTAssertTrue(house.waitForLearnButtonLabel("Remove from My words"))

        var learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertFalse(learnPage.pairTab("eng").exists, "No learns no language: no English tab")
        let greek = learnPage.tapMyWords()
        XCTAssertTrue(greek.waitForEmpty(), "English house is on no tab while English is not learned")

        let water = openDefinition("water")
        water.tapLearnButton()
        XCTAssertTrue(app.alerts["Learn English via English?"].waitForExistence(timeout: TestData.Timeouts.medium))
        water.answerLearnLanguageAlert("Yes")
        XCTAssertTrue(water.waitForLearnButtonLabel("Stop learning"))

        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        learnPage.revealPairTabs()
        XCTAssertTrue(learnPage.pairTab("eng").waitForExistence(timeout: TestData.Timeouts.medium),
                      "Yes adds English: its tab shows")
        XCTAssertTrue(learnPage.pairTab("ell").exists)
        let english = openMyWords(on: "eng")
        XCTAssertTrue(english.waitForWord("house"), "No still added house to My words: it shows once English is learned")
        XCTAssertTrue(english.waitForWord("water"), "the English tab's My words lists water")
    }

    /// Russian UI, nothing learned: Learn on γράφω asks for Greek via
    /// Russian, the limited pair, with its warning as the message; Yes
    /// learns the word.
    func testLearnGreekInRussianUIWarns() throws {
        let definitionPage = openDefinition("γράφω", source: TestData.Sources.freedictEllEng)
        definitionPage.tapLearnButton()
        let alert = app.alerts["Учить греческий через русский?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Learn asks for Greek via Russian; got \(app.alerts.firstMatch.label)")
        XCTAssertTrue(alert.staticTexts["Слова тренируются с переводом на английский."].exists, "the warning")
        definitionPage.answerLearnLanguageAlert("Да")
        XCTAssertTrue(definitionPage.waitForLearnButtonLabel("Перестать учить"), "Yes learns the word")
    }

    func testEmptyMyWords() throws {
        let myWords = openMyWords()
        XCTAssertTrue(myWords.waitForEmpty(), "a fresh My words shows its empty state")
        XCTAssertEqual(myWords.count, 0)
    }

    /// Learn on a word opened from History.
    func testLearnFromHistory() throws {
        let term = TestData.learnTestWords[1] // "test"
        openDefinition(term).navigateBack()

        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")
        let definitionFromHistory = historyPage.tapHistoryItem(at: 0)
        XCTAssertTrue(definitionFromHistory.waitForDefinitionToLoad(), "Definition should load from History")
        definitionFromHistory.learn()

        let myWords = openMyWords()
        XCTAssertTrue(myWords.waitForWord(term), "a word opened from History is added to My words")
    }
}
