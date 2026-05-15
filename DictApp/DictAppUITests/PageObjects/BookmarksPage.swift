import XCTest

class BookmarksPage: BasePage {

    // UI Elements
    private var bookmarksList: XCUIElement {
        // Try multiple approaches to find the bookmarks list
        if app.tables[AccessibilityIdentifiers.Bookmarks.bookmarksList].exists {
            return app.tables[AccessibilityIdentifiers.Bookmarks.bookmarksList]
        }
        // Try scrollViews (SwiftUI List often appears as scrollView)
        if app.scrollViews[AccessibilityIdentifiers.Bookmarks.bookmarksList].exists {
            return app.scrollViews[AccessibilityIdentifiers.Bookmarks.bookmarksList]
        }
        // Try any element with the identifier
        if app.descendants(matching: .any)[AccessibilityIdentifiers.Bookmarks.bookmarksList].exists {
            return app.descendants(matching: .any)[AccessibilityIdentifiers.Bookmarks.bookmarksList]
        }
        // Fallback to any table, scrollView, or list
        if app.tables.firstMatch.exists {
            return app.tables.firstMatch
        }
        if app.scrollViews.firstMatch.exists {
            return app.scrollViews.firstMatch
        }
        return app.collectionViews.firstMatch
    }

    // MARK: - Actions

    @discardableResult
    func tapBookmarkItem(at index: Int) -> DefinitionPage {
        let cells = bookmarksList.cells
        XCTAssertTrue(cells.count > index, "Bookmark item at index \(index) does not exist")

        let cell = cells.element(boundBy: index)
        XCTAssertTrue(cell.waitForExistence(timeout: TestData.Timeouts.medium))
        cell.tap()

        return DefinitionPage(app: app)
    }

    @discardableResult
    func tapBookmarkItemWithId(_ id: String) -> DefinitionPage {
        let bookmarkItem = app.cells[AccessibilityIdentifiers.Bookmarks.bookmarkItem(id: id)]
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: TestData.Timeouts.medium))
        bookmarkItem.tap()

        return DefinitionPage(app: app)
    }

    func deleteBookmarkItem(at index: Int) {
        let cells = bookmarksList.cells
        XCTAssertTrue(cells.count > index, "Bookmark item at index \(index) does not exist")

        let cell = cells.element(boundBy: index)
        cell.swipeLeft()

        // Look for delete button
        if app.buttons["Delete"].exists {
            app.buttons["Delete"].tap()
        }
    }

    // MARK: - Verification Methods

    func verifyBookmarksListExists() -> Bool {
        if app.staticTexts["No Bookmarks"].exists {
            return true
        }
        return bookmarksList.exists
    }

    func verifyBookmarksCount(greaterThan count: Int) -> Bool {
        return bookmarksList.cells.count > count
    }

    func verifyBookmarksCount(equalTo count: Int) -> Bool {
        return bookmarksList.cells.count == count
    }

    func verifyBookmarksIsEmpty() -> Bool {
        // Check for "No Bookmarks" text specifically
        if app.staticTexts["No Bookmarks"].exists {
            return true
        }
        // Check for empty state identifier
        if app.otherElements["empty_bookmarks_state"].exists {
            return true
        }
        // Fallback to checking cell count
        return bookmarksList.cells.count == 0
    }

    func verifyBookmarkExists(withId id: String) -> Bool {
        let bookmarkItem = app.cells[AccessibilityIdentifiers.Bookmarks.bookmarkItem(id: id)]
        return bookmarkItem.exists
    }

    func verifyBookmarkItemAtIndex(_ index: Int, containsText text: String) -> Bool {
        let cells = bookmarksList.cells
        guard cells.count > index else { return false }

        let cell = cells.element(boundBy: index)
        return cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    func getBookmarksCount() -> Int {
        return bookmarksList.cells.count
    }

    func getBookmarkItemText(at index: Int) -> String {
        let cells = bookmarksList.cells
        guard cells.count > index else { return "" }

        let cell = cells.element(boundBy: index)
        return cell.label
    }

    func waitForBookmarksToLoad(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        // Check for empty state first - "No Bookmarks" text
        if app.staticTexts["No Bookmarks"].waitForExistence(timeout: timeout) {
            return true
        }

        // Try multiple fallback strategies for finding the bookmarks list
        if app.tables[AccessibilityIdentifiers.Bookmarks.bookmarksList].waitForExistence(timeout: timeout) {
            return true
        }

        // Try scrollViews (SwiftUI List often appears as scrollView)
        if app.scrollViews[AccessibilityIdentifiers.Bookmarks.bookmarksList].waitForExistence(timeout: timeout) {
            return true
        }

        // Try any element with the identifier
        if app.descendants(matching: .any)[AccessibilityIdentifiers.Bookmarks.bookmarksList].waitForExistence(timeout: timeout) {
            return true
        }

        // Check for empty state identifier
        if app.otherElements["empty_bookmarks_state"].waitForExistence(timeout: timeout) {
            return true
        }

        // Fallback to any table or collection view
        return app.tables.firstMatch.waitForExistence(timeout: timeout) ||
               app.collectionViews.firstMatch.waitForExistence(timeout: timeout) ||
               app.scrollViews.firstMatch.waitForExistence(timeout: timeout)
    }

    func verifyBookmarkContainsWord(_ word: String) -> Bool {
        let cells = bookmarksList.cells
        for i in 0..<cells.count {
            let cell = cells.element(boundBy: i)
            if cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", word)).count > 0 {
                return true
            }
        }
        return false
    }

    func waitForBookmarkToAppear(_ word: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.verifyBookmarkContainsWord(word)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
