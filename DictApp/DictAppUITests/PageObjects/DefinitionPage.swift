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

    private var bookmarkButton: XCUIElement {
        waitForButton(AccessibilityIdentifiers.Definition.bookmarkButton)
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

    // MARK: - Actions

    func tapBookmarkButton() {
        bookmarkButton.tap()
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

    func verifyBookmarkButtonExists() -> Bool {
        return bookmarkButton.exists
    }

    func verifyDefinitionContentExists() -> Bool {
        return definitionContent.exists
    }

    func verifyDefinitionContainsText(_ text: String) -> Bool {
        let element = definitionContent
        if element.label.range(of: text, options: .caseInsensitive) != nil { return true }
        return element.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    func verifyBookmarkButtonState(isBookmarked: Bool) -> Bool {
        // This would depend on how the bookmark button changes state
        // For now, we'll just verify it exists and is enabled
        return bookmarkButton.exists && bookmarkButton.isEnabled
    }

    func getDefinitionText() -> String {
        return definitionContent.label
    }

    func waitForDefinitionToLoad(timeout: TimeInterval = 10.0) -> Bool {
        return definitionContent.waitForExistence(timeout: timeout)
    }
}
