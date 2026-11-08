import XCTest

class DefinitionPage: BasePage {

    // UI Elements
    private var definitionView: XCUIElement {
        // Try multiple approaches to find the definition view
        if app.otherElements[AccessibilityIdentifiers.Definition.definitionView].exists {
            return app.otherElements[AccessibilityIdentifiers.Definition.definitionView]
        }
        if app.scrollViews[AccessibilityIdentifiers.Definition.definitionView].exists {
            return app.scrollViews[AccessibilityIdentifiers.Definition.definitionView]
        }
        // Fallback to any element with the identifier
        return app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView]
    }

    /// 0131, #158: "Learn", "Stop learning" or "Remove from My words".
    var learnButton: XCUIElement {
        waitForButton(AccessibilityIdentifiers.Definition.learnButton)
    }

    /// 0166, #165: the learning status under the part of speech.
    var learningStatus: XCUIElement {
        app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.learningStatus].firstMatch
    }

    private var definitionContent: XCUIElement {
        // Try multiple approaches to find the definition content
        if app.staticTexts[AccessibilityIdentifiers.Definition.definitionContent].exists {
            return app.staticTexts[AccessibilityIdentifiers.Definition.definitionContent]
        }
        if app.textViews[AccessibilityIdentifiers.Definition.definitionContent].exists {
            return app.textViews[AccessibilityIdentifiers.Definition.definitionContent]
        }
        if app.scrollViews[AccessibilityIdentifiers.Definition.definitionContent].exists {
            return app.scrollViews[AccessibilityIdentifiers.Definition.definitionContent]
        }
        // Fallback to any element with the identifier
        return app.otherElements[AccessibilityIdentifiers.Definition.definitionContent]
    }

    // MARK: - Examples (0134, #178)

    private typealias ExampleIDs = AccessibilityIdentifiers.Examples

    var examplesSection: XCUIElement { app.descendants(matching: .any)[ExampleIDs.section].firstMatch }
    var examplesTitle: XCUIElement { app.descendants(matching: .any)[ExampleIDs.title].firstMatch }
    var examplesMoreButton: XCUIElement { app.buttons[ExampleIDs.moreButton].firstMatch }

    /// Example `n` (from 1): one element whose label is what VoiceOver reads.
    func example(_ n: Int) -> XCUIElement {
        app.descendants(matching: .any)[ExampleIDs.example(n)].firstMatch
    }

    /// The examples shown, 1…5, in display order.
    var shownExamples: [XCUIElement] {
        (1...5).map(example).filter(\.exists)
    }

    /// Waits for the section, or with `expected` false makes sure it does not
    /// come: the examples load after the definition.
    func waitForExamples(_ expected: Bool = true, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        if expected { return examplesSection.waitForExistence(timeout: timeout) }
        return !examplesSection.waitForExistence(timeout: timeout)
    }

    // MARK: - Actions

    func tapLearnButton() {
        learnButton.tap()
    }

    /// Learn, in an English UI: taps the button and, when it asks "Learn
    /// %@?", answers Yes (`yes`) or No. Waits for the button to read "Stop
    /// learning" (Yes, or a learned language) or "Remove from My words" (No).
    func learn(answeringLanguageAlertWith yes: Bool = true) {
        learnButton.tap()
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: TestData.Timeouts.short) {
            answerLearnLanguageAlert(yes ? "Yes" : "No")
        }
        let expected = yes ? "Stop learning" : "Remove from My words"
        XCTAssertTrue(waitForLearnButtonLabel(expected), "after Learn the button reads '\(expected)'; got '\(learnButton.label)'")
    }

    /// Taps `button` ("Yes", "Ναι") on the "Learn %@?" alert.
    func answerLearnLanguageAlert(_ button: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the 'Learn %@?' alert")
        alert.buttons[button].tap()
        _ = alert.waitForNonExistence(timeout: TestData.Timeouts.medium)
    }

    func waitForLearnButtonLabel(_ label: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                    object: app.buttons[AccessibilityIdentifiers.Definition.learnButton])
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the learning status to show with every one of `texts` in
    /// its label (its lines, as VoiceOver reads them).
    func waitForLearningStatus(containing texts: [String], timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let predicates = [NSPredicate(format: "exists == true")]
            + texts.map { NSPredicate(format: "label CONTAINS %@", $0) }
        let expectation = XCTNSPredicateExpectation(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
                                                    object: learningStatus)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the screen to show no learning status.
    func waitForNoLearningStatus(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                    object: learningStatus)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    func navigateBack() -> SearchPage {
        // The SwiftUI NavigationStack back button is labeled with the PREVIOUS
        // screen's title ("Dictionary"), not "Back", so a `buttons["Back"]`
        // lookup misses and the old `swipeRight()` fallback — unreliable on the
        // slow x86_64 sim and able to leave the definition pushed on top — was
        // taken every time. Tap the leading nav-bar button (the back chevron,
        // index 0) for a deterministic pop, then confirm the pop completed by
        // waiting for the search field to re-resolve on SearchView.
        let nav = app.navigationBars.firstMatch
        let backButton = nav.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: TestData.Timeouts.medium) {
            backButton.tap()
        } else {
            definitionView.swipeRight()
        }
        _ = app.searchFields.firstMatch.waitForExistence(timeout: TestData.Timeouts.medium)
        return SearchPage(app: app)
    }

    // MARK: - Verification Methods

    func verifyDefinitionViewExists() -> Bool {
        return definitionView.exists
    }

    func verifyLearnButtonExists() -> Bool {
        return learnButton.exists
    }

    func verifyDefinitionContentExists() -> Bool {
        return definitionContent.exists
    }

    func verifyDefinitionContainsText(_ text: String) -> Bool {
        let element = definitionContent
        if element.label.range(of: text, options: .caseInsensitive) != nil { return true }
        return element.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    func getDefinitionText() -> String {
        return definitionContent.label
    }

    func waitForDefinitionToLoad(timeout: TimeInterval = 10.0) -> Bool {
        return definitionContent.waitForExistence(timeout: timeout)
    }
}
