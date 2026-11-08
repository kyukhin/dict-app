import XCTest

/// 0131, #161: the daily session (Start), its summary, and mistakes
/// practice. English UI, `-resetData`, `-learningAnswerHints` (the right
/// option's value is `answer`), a fixed `-learningSeed`, and Multiple choice
/// through the `learning_answer_mode` default (until #162's Settings), so
/// every question is a choice answered by its hint.
final class SessionFlowTests: XCTestCase {

    var app: XCUIApplication!
    var learnPage: LearnPage!

    private typealias IDs = AccessibilityIdentifiers.Exercise

    /// One question as asked: its progress label and whether it carried the
    /// "New word" badge.
    private struct Asked {
        let progress: String
        let isNew: Bool
    }

    /// Launch arguments after `-resetData`, per test. The built-in Greek A1
    /// list ships in the Greek pack (0237), not in this bundle: the session
    /// takes its new words from the `session` fixture's user list.
    private var learningArguments: [String] {
        if name.contains("testSessionDueThenNew") {
            return ["-learningFixture", "session", "-learningLists", "user-fixture-ell"]
        }
        if name.contains("testPractiseMistakes") {
            return ["-learningFixture", "mistakes"]
        }
        // 0134, #178: five new words, each with 5 examples in the Greek pack.
        if name.contains("testExampleSheetAtTheLargestTextSize") {
            return ["-learningFixture", "myWords5",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if name.contains("testNewWordShowsTheExampleSheet") {
            return ["-learningFixture", "myWords5"]
        }
        return ["-learningFixture", "due"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek pack, which holds the
        // meanings, and the others installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "161",
                               "-learning_answer_mode", "choice"] + learningArguments + UITestHelpers.packArguments()
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

    /// Waits for the next question (a progress label other than `previous`,
    /// no feedback bar) or the summary; nil at the summary.
    private func nextQuestion(_ run: ExercisePage, after previous: String?) -> String? {
        let deadline = Date().addingTimeInterval(TestData.Timeouts.long)
        repeat {
            if run.summary.exists { return nil }
            if run.prompt.exists, !run.feedback.exists, run.progress.label != previous { return run.progress.label }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        XCTFail("no next question after \(previous ?? "the start")")
        return nil
    }

    /// Answers every question until the summary, right except the
    /// questions numbered in `wrong` (from 1).
    @discardableResult
    private func answerAll(_ run: ExercisePage, wrong: Set<Int> = [], limit: Int = 30) -> [Asked] {
        var asked: [Asked] = []
        var previous: String?
        while asked.count < limit, let progress = nextQuestion(run, after: previous) {
            let isWrong = wrong.contains(asked.count + 1)
            asked.append(Asked(progress: progress, isNew: run.newBadge.exists))
            XCTAssertNotNil(run.choose(right: !isWrong), "\(progress): an option to tap")
            XCTAssertEqual(run.waitForFeedback(), isWrong ? "wrong" : "right", progress)
            previous = progress
            run.tapContinue()
        }
        return asked
    }

    // MARK: - Tests

    /// `session` with its list checked: Today reads 5 due and 4 new; Start
    /// asks the due cards first, then the list's words with the "New word"
    /// badge, each twice: 18 questions. Then all is done for today.
    func testSessionDueThenNew() throws {
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "5 words due"))
        XCTAssertEqual(learnPage.newCount.label, "4 new words left today")
        let run = learnPage.startSession()
        let asked = answerAll(run)
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(asked.count, 18, "10 due cards, then 4 new words twice")
        XCTAssertEqual(asked.first?.progress, "Question 1 of 18")
        XCTAssertTrue(asked.prefix(9).allSatisfy { !$0.isNew }, "the due cards first, without the badge")
        XCTAssertEqual(asked.filter(\.isNew).count, 8, "each new word's two cards carry the badge")
        XCTAssertEqual(asked.last?.isNew, true)
        XCTAssertEqual(run.summaryValue(IDs.summaryNewWords), "4")
        XCTAssertEqual(run.summaryValue(IDs.summaryReviewed), "5")

        run.tapDone()
        XCTAssertTrue(learnPage.waitForHome(), "Done closes the run")
        XCTAssertTrue(learnPage.allDone.waitForExistence(timeout: TestData.Timeouts.medium), "All done for today")
        XCTAssertFalse(learnPage.startButton.exists, "Start hides when all is done")
    }

    /// `due`: the summary's numbers are the answers given: 10 cards, the
    /// second answered wrong and asked again, so 11 exercises and 91% right,
    /// 5 reviewed words, no new word, and 11 of the daily goal of 20.
    func testSummaryAfterSession() throws {
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "5 words due"))
        let run = learnPage.startSession()
        let asked = answerAll(run, wrong: [2])
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(asked.count, 11, "the wrong card comes back once, at the end")
        XCTAssertEqual(asked.last?.progress, "Question 11 of 11")
        XCTAssertEqual(run.summaryValue(IDs.summaryExercises), "11")
        XCTAssertEqual(run.summaryValue(IDs.summaryAccuracy), "91%")
        XCTAssertEqual(run.summaryValue(IDs.summaryNewWords), "0")
        XCTAssertEqual(run.summaryValue(IDs.summaryReviewed), "5")
        XCTAssertEqual(run.summaryValue(IDs.summaryGoal), "11 of 20")
        run.tapDone()
        XCTAssertTrue(learnPage.waitForHome(), "Done closes the run")
    }

    /// `mistakes`: "Practise mistakes · 2 words" asks γράφω's recognition
    /// (wrong today), then σπίτι's production (wrong 6 days ago), not νερό
    /// (7 days ago) nor καλός (right since). Answered right, they leave and
    /// the row hides.
    func testPractiseMistakes() throws {
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.mistakesRow, toBe: "Practise mistakes · 2 words"))
        let run = learnPage.openMistakes()
        XCTAssertNotNil(nextQuestion(run, after: nil))
        XCTAssertEqual(run.prompt.label, "γράφω", "the latest mistake first")
        let asked = answerAll(run)
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(asked.map(\.progress), ["Question 1 of 2", "Question 2 of 2"])
        XCTAssertEqual(run.summaryValue(IDs.summaryExercises), "2")
        XCTAssertEqual(run.summaryValue(IDs.summaryGoal), "3 of 20", "today's mistake counts too")
        run.tapDone()
        XCTAssertTrue(learnPage.waitForHome(), "Done closes the run")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: learnPage.mistakesRow)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: TestData.Timeouts.medium), .completed, "the row hides at 0")
    }

    // MARK: - 0134, #178: the example sheet

    /// `myWords5`: the first question carries the "New word" badge; after
    /// the answer a sheet shows the word and 1–3 examples with English
    /// translations; its Continue shows the next question.
    func testNewWordShowsTheExampleSheet() throws {
        let run = learnPage.startSession()
        XCTAssertNotNil(nextQuestion(run, after: nil), "the first question")
        XCTAssertTrue(run.newBadge.exists, "a new word")
        let progress = run.progress.label
        let word = run.prompt.label
        XCTAssertNotNil(run.choose(right: true))
        XCTAssertEqual(run.waitForFeedback(), "right")
        XCTAssertTrue(run.waitForExampleSheet(), "the sheet after a new word's first answer")
        XCTAssertTrue(run.exampleSheetWord.waitForExistence(timeout: TestData.Timeouts.medium), "the word")
        XCTAssertTrue(run.exampleSheetWord.label.hasPrefix(word), "the word as the question shows it: \(run.exampleSheetWord.label)")
        let examples = (1...3).map(run.example).filter(\.exists)
        XCTAssertFalse(examples.isEmpty, "1–3 examples")
        XCTAssertFalse(run.example(4).exists, "at most 3")
        for example in examples {
            XCTAssertNotNil(example.label.range(of: "[A-Za-z]{2,}.* From Tatoeba: ", options: .regularExpression),
                            "an English translation and the authors: \(example.label)")
        }
        attachScreenshot("example sheet")

        XCTAssertTrue(run.exampleSheetContinue.exists, "Continue")
        run.exampleSheetContinue.tap()
        XCTAssertTrue(run.exampleSheet.waitForNonExistence(timeout: TestData.Timeouts.medium), "the sheet closes")
        XCTAssertNotNil(nextQuestion(run, after: progress), "Continue shows the next question")
        XCTAssertEqual(run.progress.label, "Question 2 of 10")
    }

    /// At the largest accessibility text size the sheet opens at full
    /// height, its examples scroll, and Continue stays on screen.
    func testExampleSheetAtTheLargestTextSize() throws {
        let run = learnPage.startSession()
        XCTAssertNotNil(nextQuestion(run, after: nil), "the first question")
        XCTAssertNotNil(run.choose(right: true))
        XCTAssertEqual(run.waitForFeedback(), "right")
        XCTAssertTrue(run.waitForExampleSheet(), "the sheet")
        let window = app.windows.firstMatch.frame
        let sheet = run.exampleSheet
        // Let the presentation settle at its detent.
        let settled = NSPredicate { _, _ in sheet.exists && sheet.frame.height > window.height * 0.8 }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: TestData.Timeouts.medium)
        XCTAssertGreaterThan(sheet.frame.height, window.height * 0.8, "full height: \(sheet.frame) in \(window)")
        let continueButton = run.exampleSheetContinue
        XCTAssertTrue(continueButton.exists)
        XCTAssertTrue(window.contains(CGPoint(x: continueButton.frame.midX, y: continueButton.frame.midY)),
                      "Continue on screen: \(continueButton.frame)")
        XCTAssertTrue(continueButton.isHittable, "Continue pinned at the bottom")
        attachScreenshot("example sheet, largest text size")
        continueButton.tap()
        XCTAssertTrue(run.exampleSheet.waitForNonExistence(timeout: TestData.Timeouts.medium), "the sheet closes")
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
