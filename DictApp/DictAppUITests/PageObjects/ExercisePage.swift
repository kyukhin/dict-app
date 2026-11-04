import XCTest

/// A run (0131, #159): the full-screen cover with its close button,
/// progress bar, question, feedback bar and summary. With
/// `-learningAnswerHints` the right option's accessibility value is
/// `answer`, so a test can answer right or wrong on purpose.
class ExercisePage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Exercise

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var view: XCUIElement { element(IDs.view) }
    var prompt: XCUIElement { element(IDs.prompt) }
    var progress: XCUIElement { element(IDs.progress) }
    var closeButton: XCUIElement { app.buttons[IDs.close].firstMatch }
    var newBadge: XCUIElement { element(IDs.newBadge) }
    var answerField: XCUIElement { app.textFields[IDs.answerField].firstMatch }
    var checkButton: XCUIElement { app.buttons[IDs.check].firstMatch }
    var dontKnowButton: XCUIElement { app.buttons[IDs.dontKnow].firstMatch }
    var feedback: XCUIElement { element(IDs.feedback) }
    var continueButton: XCUIElement { app.buttons[IDs.continueButton].firstMatch }
    var summary: XCUIElement { element(IDs.summary) }
    var summaryDone: XCUIElement { app.buttons[IDs.summaryDone].firstMatch }

    func option(_ index: Int) -> XCUIElement {
        app.buttons[IDs.option(index)].firstMatch
    }

    /// The options shown, 0…3.
    var options: [XCUIElement] {
        (0..<4).map(option).filter(\.exists)
    }

    /// The option marked `answer` (`-learningAnswerHints`), nil for a typed question.
    var rightOption: XCUIElement? {
        options.first { ($0.value as? String) == "answer" }
    }

    /// The feedback bar's text: "Right!", "Right answer: write", "Mind the accent: γράφω".
    var feedbackText: String {
        feedback.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
    }

    // MARK: - Waiting

    /// A question or the summary, whichever comes.
    func waitForQuestionOrSummary(timeout: TimeInterval = TestData.Timeouts.long) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if summary.exists || (prompt.exists && !feedback.exists) { return true }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return summary.exists || prompt.exists
    }

    var isTyped: Bool { answerField.exists }

    // MARK: - Actions

    /// Taps the right option (`right`) or another one; returns the tapped
    /// option's label.
    @discardableResult
    func choose(right: Bool) -> String? {
        let all = options
        guard let answer = rightOption else { return nil }
        let target = right ? answer : all.first { $0.identifier != answer.identifier }
        guard let target else { return nil }
        let label = target.label
        target.tap()
        return label
    }

    /// Types `text` and taps Check.
    func type(_ text: String) {
        XCTAssertTrue(answerField.waitForExistence(timeout: TestData.Timeouts.medium), "the answer field")
        if !answerField.hasKeyboardFocus { answerField.tap() }
        answerField.typeText(text)
        XCTAssertTrue(checkButton.waitForExistence(timeout: TestData.Timeouts.short), "Check")
        checkButton.tap()
    }

    /// Waits for the feedback bar and returns its outcome: `right`, `accent` or `wrong`.
    func waitForFeedback(timeout: TimeInterval = TestData.Timeouts.medium) -> String? {
        guard feedback.waitForExistence(timeout: timeout) else { return nil }
        return feedback.value as? String
    }

    func tapContinue() {
        XCTAssertTrue(continueButton.waitForExistence(timeout: TestData.Timeouts.medium), "Continue")
        continueButton.tap()
    }

    func tapDone() {
        XCTAssertTrue(summaryDone.waitForExistence(timeout: TestData.Timeouts.medium), "Done")
        summaryDone.tap()
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
