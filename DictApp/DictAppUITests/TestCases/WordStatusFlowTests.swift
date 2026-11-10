import XCTest

/// 0166, #165: a word's learning status under the part of speech on the
/// Definition screen. English UI, `-resetData` and `-learningFixture due`
/// (Greek learned; γράφω, σπίτι, νερό, καλός and είμαι due today on rungs
/// 1–3; βιβλίο learned, due in 20 days), with `-learningAnswerHints` so a
/// trainer answer can be wrong on purpose. θάλασσα is in no fixture.
final class WordStatusFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        // Issue #237: no first-launch sheet; the Greek pack installed from
        // the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "165",
                               "-learningFixture", "due"] + UITestHelpers.packArguments()
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

    /// Searches `term` and opens its El–En · FD entry.
    private func openDefinition(_ term: String) -> DefinitionPage {
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(term)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(term)'")
        let definitionPage = searchPage.tapResult(word: term, source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(term)'")
        return definitionPage
    }

    /// The learning day `days` from today, as the app shows a date in
    /// English: "Dec 12", with the year when it is not this year's. A day
    /// starts at 4 AM (0131).
    private func shortDate(daysFromToday days: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let today = calendar.component(.hour, from: now) < 4 ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        let date = calendar.date(byAdding: .day, value: days, to: today)!
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en"),
                                     calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: today) { style = style.year() }
        return date.formatted(style)
    }

    // MARK: - Tests

    /// A learning, a learned and a new word show their stage, next review
    /// and each card's stage.
    func testDefinitionShowsStatus() throws {
        let grafo = openDefinition("γράφω")
        XCTAssertTrue(grafo.waitForLearningStatus(containing: ["Learning · next review today",
                                                               "Recognition: every 1 day · Production: every 1 day"]),
                      "γράφω, rung 1 and due today; got '\(grafo.learningStatus.label)'")
        XCTAssertFalse(grafo.learningStatus.label.contains("mistake"), "no mistakes, no line")
        let statusElements = app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Definition.learningStatus)
        XCTAssertEqual(statusElements.count, 1, "VoiceOver reads the status as one element")
        grafo.navigateBack()

        let vivlio = openDefinition("βιβλίο")
        let date = shortDate(daysFromToday: 20)
        XCTAssertTrue(vivlio.waitForLearningStatus(containing: ["Learned · next review \(date)",
                                                                "Recognition: learned · Production: learned"]),
                      "βιβλίο, learned, due in 20 days (\(date)); got '\(vivlio.learningStatus.label)'")
        vivlio.navigateBack()

        let thalassa = openDefinition("θάλασσα")
        XCTAssertTrue(thalassa.waitForLearnButtonLabel("Learn"), "θάλασσα is not in learning")
        thalassa.learn()
        XCTAssertTrue(thalassa.waitForLearningStatus(containing: ["New · not started yet"]),
                      "Learn makes it new; got '\(thalassa.learningStatus.label)'")
        XCTAssertFalse(thalassa.learningStatus.label.contains("Recognition"), "a new word shows one line")
    }

    /// A word never added and a paused word show no status.
    func testDefinitionWithoutLearningShowsNothing() throws {
        let thalassa = openDefinition("θάλασσα")
        XCTAssertTrue(thalassa.waitForLearnButtonLabel("Learn"), "θάλασσα is not in learning")
        XCTAssertTrue(thalassa.waitForNoLearningStatus(), "a word never added shows nothing")
        thalassa.navigateBack()

        let grafo = openDefinition("γράφω")
        XCTAssertTrue(grafo.waitForLearningStatus(containing: ["Learning"]), "γράφω is in learning")
        XCTAssertTrue(grafo.waitForLearnButtonLabel("Stop learning"))
        grafo.tapLearnButton()
        XCTAssertTrue(grafo.waitForLearnButtonLabel("Learn"), "Stop learning pauses it")
        XCTAssertTrue(grafo.waitForNoLearningStatus(), "a paused word shows nothing")
        grafo.navigateBack()

        let reopened = openDefinition("γράφω")
        XCTAssertTrue(reopened.waitForLearnButtonLabel("Learn"))
        XCTAssertTrue(reopened.waitForNoLearningStatus(), "still nothing when opened again")
    }

    /// A wrong answer in the recognition trainer shows on the word's
    /// Definition: its card back to learning, due today, and 1 mistake.
    func testMistakeShowsOnTheDefinition() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        let run = learnPage.openTrainer()
        XCTAssertTrue(run.waitForQuestionOrSummary(), "a question")
        let word = run.prompt.label
        XCTAssertNotNil(run.choose(right: false), "a wrong option to tap for \(word)")
        XCTAssertEqual(run.waitForFeedback(), "wrong", word)
        run.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "closing returns to the Learn home")

        let definition = openDefinition(word)
        XCTAssertTrue(definition.waitForLearningStatus(containing: ["Learning · next review today",
                                                                    "Recognition: learning", "1 mistake"]),
                      "\(word) after a wrong answer; got '\(definition.learningStatus.label)'")
    }
}
