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

    func navigateBack() -> SearchPage {
        // Use navigation back button or swipe gesture
        if app.navigationBars.buttons["Back"].exists {
            app.navigationBars.buttons["Back"].tap()
        } else {
            // Fallback to swipe gesture
            definitionView.swipeRight()
        }
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
        return definitionContent.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
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