import XCTest

/// Match the pairs (0131, #160): the full-screen cover with its close
/// button, its timer, the word and meaning tiles, and the round's result.
/// A matched tile leaves the accessibility tree. With
/// `-learningAnswerHints`, while a tile is selected its pair in the other
/// column has the value `answer`.
class MatchPairsPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Match

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var view: XCUIElement { element(IDs.view) }
    var timer: XCUIElement { element(IDs.timer) }
    var mismatch: XCUIElement { element(IDs.mismatch) }
    var closeButton: XCUIElement { app.buttons[AccessibilityIdentifiers.Exercise.close].firstMatch }
    var result: XCUIElement { element(IDs.result) }
    var resultTime: XCUIElement { element(IDs.resultTime) }
    var resultMistakes: XCUIElement { element(IDs.resultMistakes) }
    var nextRoundButton: XCUIElement { app.buttons[IDs.nextRound].firstMatch }
    var doneButton: XCUIElement { app.buttons[IDs.done].firstMatch }

    func word(_ position: Int) -> XCUIElement {
        app.buttons[IDs.word(position)].firstMatch
    }

    func meaning(_ position: Int) -> XCUIElement {
        app.buttons[IDs.meaning(position)].firstMatch
    }

    /// The tiles still on the board, top to bottom.
    var words: [XCUIElement] { (0..<5).map(word).filter(\.exists) }
    var meanings: [XCUIElement] { (0..<5).map(meaning).filter(\.exists) }

    /// The meaning marked `answer` while a word is selected.
    var rightMeaning: XCUIElement? {
        meanings.first { ($0.value as? String) == "answer" }
    }

    /// The timer's value in seconds: "0:07" is 7.
    var timerSeconds: Int? {
        guard let value = timer.value as? String else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// The board, or the result, whichever comes.
    func waitForBoard(timeout: TimeInterval = TestData.Timeouts.long) -> Bool {
        word(0).waitForExistence(timeout: timeout)
    }

    /// Taps `word`, then its meaning (`right`) or another one still on the
    /// board; returns the meaning tapped, read before the tap.
    @discardableResult
    func pair(_ word: XCUIElement, right: Bool) -> (id: String, label: String)? {
        word.tap()
        let deadline = Date().addingTimeInterval(TestData.Timeouts.medium)
        var answer = rightMeaning
        while answer == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            answer = rightMeaning
        }
        guard let answer else { return nil }
        let answerID = answer.identifier
        let target = right ? answer : meanings.first { $0.identifier != answerID }
        guard let target else { return nil }
        let tapped = (id: target.identifier, label: target.label)
        target.tap()
        return tapped
    }

    /// Waits until `element` has left the board.
    func waitForGone(_ element: XCUIElement, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }
}
