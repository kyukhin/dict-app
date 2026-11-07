import XCTest

/// 0131, #160: match the pairs. English UI, `-resetData`,
/// `-learningAnswerHints` (while a word is selected its meaning's value is
/// `answer`) and a fixed `-learningSeed`. `-learningFixture due`: the five
/// due Greek words (and the learned βιβλίο, not needed) with their English
/// meanings from the Greek pack.
final class MatchPairsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!
    var learnPage: LearnPage!

    /// The `due` fixture's round: each word and its meaning from El–En · FD.
    static let meanings = ["γράφω": "write", "σπίτι": "house, home, habitation", "νερό": "water",
                           "καλός": "good", "είμαι": "be, exist"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `bilingual`: two Greek words, too few for a round.
        let fixture = name.contains("testDisabledWithFewerThanFiveWords") ? "bilingual" : "due"
        // Issue #237: no first-launch sheet; the Greek pack, which holds the
        // meanings, installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "160",
                               "-learningFixture", fixture] + UITestHelpers.packArguments("ell")
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
        learnPage = nil
    }

    /// A screenshot kept in the result bundle, for review on each device.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Five words and their five meanings, a timer that counts up, a wrong
    /// pair that stays on the board, then every right pair gone; the
    /// result shows the time and 1 mistake, and Done returns to the home.
    /// The board is centred and at most 600 pt wide, on iPhone and iPad.
    func testRoundOfFive() throws {
        let match = learnPage.openMatch()
        XCTAssertTrue(match.waitForBoard(), "the board")
        XCTAssertEqual(Set(match.words.map(\.label)), Set(Self.meanings.keys), "the five due words")
        XCTAssertEqual(Set(match.meanings.map(\.label)), Set(Self.meanings.values), "their English meanings")

        let window = app.windows.firstMatch.frame
        let board = match.word(0).frame.union(match.meaning(0).frame)
        XCTAssertLessThanOrEqual(board.width, 600, "at most 600 pt wide")
        XCTAssertEqual(board.midX, window.midX, accuracy: 2, "centred")
        XCTAssertLessThan(match.word(0).frame.maxX, match.meaning(0).frame.minX, "the words on the left")

        let started = try XCTUnwrap(match.timerSeconds, "the timer reads m:ss: \(String(describing: match.timer.value))")
        Thread.sleep(forTimeInterval: 2.5)
        let later = try XCTUnwrap(match.timerSeconds)
        XCTAssertGreaterThan(later, started, "the timer counts up")

        let first = match.word(0)
        let firstWord = first.label
        XCTAssertNotNil(match.pair(first, right: false), "a wrong pair")
        attachScreenshot("a wrong pair")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(match.words.count, 5, "a wrong pair stays on the board")
        XCTAssertEqual(match.meanings.count, 5)
        XCTAssertTrue(first.exists, "\(firstWord) stays")

        for position in 0..<5 {
            let word = match.word(position)
            let label = word.label
            if position == 2 {
                word.tap()
                attachScreenshot("a word selected, two pairs matched")
                word.tap()
            }
            let meaning = try XCTUnwrap(match.pair(word, right: true), "\(label): its meaning marked")
            XCTAssertEqual(meaning.label, Self.meanings[label], "\(label)'s meaning")
            XCTAssertTrue(match.waitForGone(word), "\(label) disappears")
            XCTAssertTrue(match.waitForGone(app.buttons[meaning.id]), "\(label)'s meaning disappears")
        }

        XCTAssertTrue(match.result.waitForExistence(timeout: TestData.Timeouts.medium), "the result")
        XCTAssertEqual(match.resultMistakes.label, "1", "one wrong pair")
        XCTAssertTrue(match.resultTime.label.contains(":"), "the time as m:ss: \(match.resultTime.label)")
        XCTAssertTrue(match.nextRoundButton.exists, "Next round")
        attachScreenshot("the result")
        match.doneButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "Done closes match the pairs")
    }

    /// Next round: five tiles again, the timer from 0, the word answered
    /// wrong among them; the close button ends it at any time.
    func testNextRound() throws {
        let match = learnPage.openMatch()
        XCTAssertTrue(match.waitForBoard(), "the board")
        let first = match.word(0)
        let firstWord = first.label
        XCTAssertNotNil(match.pair(first, right: false), "a wrong pair")
        for position in 0..<5 {
            let word = match.word(position)
            XCTAssertNotNil(match.pair(word, right: true))
            XCTAssertTrue(match.waitForGone(word))
        }
        XCTAssertTrue(match.nextRoundButton.waitForExistence(timeout: TestData.Timeouts.medium), "Next round")
        match.nextRoundButton.tap()
        XCTAssertTrue(match.waitForBoard(), "a new board")
        XCTAssertEqual(match.words.count, 5)
        XCTAssertTrue(match.words.map(\.label).contains(firstWord), "\(firstWord), back to learning, comes first")
        XCTAssertLessThanOrEqual(try XCTUnwrap(match.timerSeconds), 2, "the timer starts again")
        XCTAssertTrue(match.closeButton.exists, "the close button")
        match.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "closing returns to the Learn home")
    }

    /// Two Greek words (`bilingual`): the trainer is disabled with "Learn 5
    /// words first".
    func testDisabledWithFewerThanFiveWords() throws {
        let row = learnPage.trainerMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Match the pairs row")
        XCTAssertFalse(row.isEnabled, "disabled")
        XCTAssertTrue(row.label.contains("Learn 5 words first"), row.label)
    }
}
