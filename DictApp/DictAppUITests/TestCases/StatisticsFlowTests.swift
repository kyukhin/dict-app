import XCTest

/// 0166, #164: the statistics screen, the daily goal ring and the streak on
/// the Learn home. English UI, `-resetData`, `-learningAnswerHints` (the
/// right option's value is `answer`), and per test a learning fixture:
/// `stats` (30 days of Greek answers: the streak 9, the best 12, two frozen
/// days and a reset; 434 exercises on 21 days, 30 yesterday; γράφω, σπίτι
/// and νερό with 5, 3 and 2 mistakes; 40 drill rows over present, aorist
/// and future; two English words on the last 3 days; Greek and English
/// learned), `due` (no answers yet) or `mistakes` (answers, no drill).
final class StatisticsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var learnPage: LearnPage!

    private typealias IDs = AccessibilityIdentifiers.Statistics

    /// The `stats` fixture's 30-day summary, without its best day's date.
    private static let summaryStart = "Last 30 days: 434 exercises on 21 days. Goal met on 21 days. Best day: "
    private static let summaryEnd = ", 30 exercises."

    private var fixture: String {
        if name.contains("testTodayAfterAnswers") || name.contains("testEmptyBeforeTheFirstAnswer") { return "due" }
        if name.contains("testNoDrillAnswersNoBlock") { return "mistakes" }
        return "stats"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek pack, which holds the
        // meanings and the Definitions, and the others installed from the
        // committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "164",
                               "-learningFixture", fixture] + UITestHelpers.packArguments()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        learnPage = TabBarPage(app: app).tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
    }

    override func tearDownWithError() throws {
        app = nil
        learnPage = nil
    }

    // MARK: - Helpers

    /// Today's learning day as the app counts it: before 4 AM, yesterday.
    private static var today: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var date = Date()
        if calendar.component(.hour, from: date) < 4 {
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// Waits until `element`'s value is `value`.
    private func waitForValue(of element: XCUIElement, toBe value: String,
                              timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Tests

    /// `due`: 3 Recognition answers, then the run closed. The ring reads
    /// 3/20; a tap on it opens Statistics, whose Today shows 3 of 20, 3
    /// words reviewed, all right.
    func testTodayAfterAnswers() throws {
        XCTAssertTrue(learnPage.goalRing.waitForExistence(timeout: TestData.Timeouts.medium), "the ring")
        XCTAssertEqual(learnPage.goalRing.value as? String, "0/20")
        XCTAssertEqual(learnPage.goalRing.label, "Daily goal: 0 of 20 exercises")
        let run = learnPage.openTrainer()
        for question in 1...3 {
            XCTAssertTrue(run.waitForQuestionOrSummary(), "question \(question)")
            XCTAssertNotNil(run.choose(right: true), "question \(question): the answer hint")
            XCTAssertEqual(run.waitForFeedback(), "right")
            if question < 3 { run.tapContinue() }
        }
        run.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "the close button ends the run")
        XCTAssertTrue(waitForValue(of: learnPage.goalRing, toBe: "3/20"), "the ring after 3 answers")
        XCTAssertEqual(learnPage.streak.value as? String, "0", "the goal is not met yet")

        let stats = learnPage.openStatistics(from: learnPage.goalRing)
        XCTAssertTrue(stats.waitForLabel(IDs.todayExercises, toBe: "3 of 20"))
        XCTAssertEqual(stats.label(IDs.todayNew), "0")
        XCTAssertEqual(stats.label(IDs.todayReviewed), "3")
        XCTAssertEqual(stats.label(IDs.todayAccuracy), "100%")
        XCTAssertEqual(stats.label(IDs.streakCurrent), "0 days")
        XCTAssertFalse(stats.languageSwitch.exists, "one learned language: no switch")
    }

    /// `stats`: the 30-day chart with its summary; the hardest words, the
    /// word with 5 mistakes first, whose tap opens its Definition.
    func testChartAndHardestWords() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.reveal(IDs.chart30d), "the chart")
        XCTAssertTrue(stats.chart.label.hasPrefix(Self.summaryStart), stats.chart.label)
        XCTAssertTrue(stats.chart.label.hasSuffix(Self.summaryEnd), stats.chart.label)
        XCTAssertEqual(stats.element(IDs.chartEnd).label, "Today")
        let tallest = try XCTUnwrap(stats.tallestBarPosition(), "the chart's bars")
        XCTAssertGreaterThan(tallest, 0.7, "yesterday's bar, the tallest, at the right edge next to today's")

        let first = stats.element(IDs.hardest(1))
        XCTAssertTrue(stats.reveal(IDs.hardest(1)), "the hardest words")
        XCTAssertTrue(first.label.contains("γράφω"), first.label)
        XCTAssertTrue(first.label.contains("write"), "its meaning: \(first.label)")
        XCTAssertTrue(first.label.contains("5 mistakes"), first.label)
        XCTAssertTrue(stats.label(IDs.hardest(2)).contains("3 mistakes"))
        XCTAssertTrue(stats.label(IDs.hardest(3)).contains("2 mistakes"))
        XCTAssertFalse(stats.element(IDs.hardest(4)).exists, "three words with mistakes")
        first.tap()
        let definition = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionContent].firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: TestData.Timeouts.long), "γράφω's Definition")
        XCTAssertTrue(app.staticTexts["γράφω"].firstMatch.waitForExistence(timeout: TestData.Timeouts.medium))
    }

    /// `stats`: the Conjugation block lists the fixture's 3 tenses in the
    /// tables' order, both voices of the present together, and the hardest
    /// verbs.
    func testConjugationBlock() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.reveal(IDs.tense("present")), "the Conjugation block")
        XCTAssertEqual(stats.label(IDs.tense("present")), "75%")
        XCTAssertEqual(stats.label(IDs.tense("aorist")), "67%")
        XCTAssertEqual(stats.label(IDs.tense("future")), "58%")
        XCTAssertFalse(stats.element(IDs.tense("imperfect")).exists)
        XCTAssertLessThan(stats.element(IDs.tense("present")).frame.minY, stats.element(IDs.tense("aorist")).frame.minY)
        XCTAssertLessThan(stats.element(IDs.tense("aorist")).frame.minY, stats.element(IDs.tense("future")).frame.minY)
        let verb = stats.label(IDs.hardestVerb(1))
        XCTAssertTrue(verb.contains("γράφω") && verb.contains("10 mistakes"), verb)
        XCTAssertTrue(stats.label(IDs.hardestVerb(2)).contains("είμαι"))
    }

    /// `mistakes`: answers but no drill: no Conjugation block.
    func testNoDrillAnswersNoBlock() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.reveal(IDs.hardest(1)), "the hardest words")
        for _ in 0..<6 { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertFalse(stats.tenseChart.exists, "no tense chart")
        XCTAssertFalse(stats.element(IDs.tense("present")).exists)
        XCTAssertFalse(stats.element(IDs.hardestVerb(1)).exists)
    }

    /// `stats`: Greek and English learned: the switch shows. English
    /// changes the chosen language's numbers; the goal and the streak stay.
    func testLanguageSwitch() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "the switch")
        XCTAssertEqual(stats.label(IDs.todayNew), "1", "ψωμί, started today")
        XCTAssertEqual(stats.label(IDs.todayExercises), "22 of 20")
        XCTAssertEqual(stats.label(IDs.streakCurrent), "9 days")
        stats.selectLanguage(named: "English")
        XCTAssertTrue(stats.waitForLabel(IDs.todayNew, toBe: "0"), "English: no word started today")
        XCTAssertEqual(stats.label(IDs.todayReviewed), "2")
        XCTAssertEqual(stats.label(IDs.todayExercises), "22 of 20", "every language")
        XCTAssertEqual(stats.label(IDs.streakCurrent), "9 days", "the streak is shared")
        // English's lists: My words with house and water, both learning;
        // the Greek list is gone.
        XCTAssertEqual(stats.label(IDs.listForecast("my-words")), "All learned in ~25 days")
        XCTAssertFalse(stats.element(IDs.list(Self.greekList)).exists, "a Greek list")
    }

    /// The `stats` fixture's Greek list: θάλασσα and ψωμί learning, ήλιος new.
    private static let greekList = "user-fixture-stats"

    /// `stats`, Greek: the Lists block shows My words and the list with
    /// started words, each with its forecast: one new word at the pace of
    /// the words started since the first one, 23 to 29 days ago (by the
    /// weekday), plus the 25 days a new word needs to be learned.
    func testListsShowTheForecast() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.reveal(IDs.listForecast(Self.greekList)), "the Greek list's forecast")
        XCTAssertTrue(stats.element(IDs.list(Self.greekList)).exists)
        try assertForecast(stats.label(IDs.listForecast(Self.greekList)), in: 37...40)
        XCTAssertTrue(stats.reveal(IDs.listForecast("my-words")), "My words' forecast")
        try assertForecast(stats.label(IDs.listForecast("my-words")), in: 28...29)
    }

    /// `text` reads "All learned in ~N days" with N in `range`.
    private func assertForecast(_ text: String, in range: ClosedRange<Int>,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let prefix = "All learned in ~", suffix = " days"
        XCTAssertTrue(text.hasPrefix(prefix) && text.hasSuffix(suffix), text, file: file, line: line)
        let days = try XCTUnwrap(Int(text.dropFirst(prefix.count).dropLast(suffix.count)), text, file: file, line: line)
        XCTAssertTrue(range.contains(days), "\(days) days, not in \(range)", file: file, line: line)
    }

    /// `due`: words to learn and no answer yet: Statistics shows only "Your
    /// statistics appear after your first exercise."
    func testEmptyBeforeTheFirstAnswer() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.empty.waitForExistence(timeout: TestData.Timeouts.medium), "the empty state")
        XCTAssertEqual(stats.empty.label, "Your statistics appear after your first exercise.")
        XCTAssertFalse(stats.element(IDs.todayExercises).exists, "no Today block")
        XCTAssertFalse(stats.element(IDs.streakCurrent).exists, "no Streak block")
        XCTAssertFalse(stats.chart.exists, "no chart")
    }

    /// `stats`: VoiceOver reads each chart as one summary.
    func testChartsHaveSummaries() throws {
        let stats = learnPage.openStatistics()
        XCTAssertTrue(stats.reveal(IDs.chart30d))
        XCTAssertTrue(stats.chart.label.hasPrefix(Self.summaryStart), stats.chart.label)
        XCTAssertTrue(stats.reveal(IDs.tenseChart), "the tense chart")
        XCTAssertEqual(stats.tenseChart.label, "Conjugation, last 30 days: present 75%, aorist 67%, future 58%.")
    }

    /// `stats`: the home's ring and flame, then the Streak block: 9, best
    /// 12, the freezes, and the calendar's marks, today met.
    func testStreakBlock() throws {
        XCTAssertTrue(learnPage.goalRing.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(learnPage.goalRing.value as? String, "22/20")
        XCTAssertEqual(learnPage.streak.value as? String, "9")
        let streakLabel = learnPage.streak.label
        XCTAssertTrue(streakLabel.hasPrefix("9-day streak, "), streakLabel)
        // "9-day streak, 2 freezes": the freezes in stock, 0 to 3, by the weekday.
        let freezes = try XCTUnwrap(streakLabel.split(separator: " ").dropLast().last.flatMap { Int($0) }, streakLabel)
        XCTAssertTrue((0...3).contains(freezes), streakLabel)
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "learn home: ring and streak"
        home.lifetime = .keepAlways
        add(home)

        let stats = learnPage.openStatistics(from: learnPage.streak)
        XCTAssertEqual(stats.label(IDs.streakCurrent), "9 days")
        XCTAssertEqual(stats.label(IDs.streakBest), "12 days")
        XCTAssertEqual(stats.label(IDs.streakFreeze), "\(freezes) of 3", "the freezes in stock, as on the home")
        let today = stats.element(IDs.streakDay(Self.today))
        XCTAssertTrue(stats.reveal(IDs.streakDay(Self.today)), "today in the calendar")
        XCTAssertEqual(today.value as? String, "met")
        XCTAssertTrue(today.label.hasSuffix(", goal met"), today.label)
        XCTAssertEqual(stats.days(marked: "frozen").count, 2, "two missed days frozen")
        XCTAssertGreaterThanOrEqual(stats.days(marked: "missed").count, 1, "then a reset")
    }
}
