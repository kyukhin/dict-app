import XCTest

/// My words (0131, #158): the former Bookmarks list, behind the Learn home's
/// "My words" row; since #154 E3's list screen for `my-words` (0130).
/// Newest first, one row per word; a tap opens the Definition; the swipe is
/// Stop learning.
class MyWordsPage: BasePage {

    private var list: XCUIElement {
        let collection = app.collectionViews[AccessibilityIdentifiers.MyWords.list]
        if collection.exists { return collection }
        return app.descendants(matching: .any)[AccessibilityIdentifiers.MyWords.list].firstMatch
    }

    /// The word rows, top to bottom.
    private var items: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.MyWords.item)
    }

    /// The empty state's text (English).
    static let emptyText = "Tap Learn on any word to add it here."

    func item(_ word: String) -> XCUIElement {
        items.matching(NSPredicate(format: "label == %@", word)).firstMatch
    }

    // MARK: - Actions

    @discardableResult
    func tapItem(at index: Int) -> DefinitionPage {
        let row = items.element(boundBy: index)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "My words item \(index)")
        row.tap()
        return DefinitionPage(app: app)
    }

    @discardableResult
    func tapWord(_ word: String) -> DefinitionPage {
        let element = item(word)
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), "My words lists '\(word)'")
        element.tap()
        return DefinitionPage(app: app)
    }

    /// The swipe: "Stop learning" (English UI).
    func stopLearning(_ word: String) {
        let element = item(word)
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), "My words lists '\(word)'")
        element.swipeLeft()
        let button = app.buttons["Stop learning"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.medium), "the swipe shows Stop learning")
        button.tap()
    }

    // MARK: - Verification

    /// The list or its empty state.
    func waitForMyWordsToLoad(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if list.exists || isEmpty() { return true }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return list.exists || isEmpty()
    }

    func isEmpty() -> Bool {
        app.staticTexts[Self.emptyText].exists
    }

    func waitForEmpty(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        app.staticTexts[Self.emptyText].waitForExistence(timeout: timeout)
    }

    func containsWord(_ word: String) -> Bool {
        item(word).exists
    }

    func waitForWord(_ word: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        item(word).waitForExistence(timeout: timeout)
    }

    func waitForWordToDisappear(_ word: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        item(word).waitForNonExistence(timeout: timeout)
    }

    /// The word rows shown (SwiftUI materialises only the visible ones).
    var count: Int {
        list.exists ? items.count : 0
    }
}
