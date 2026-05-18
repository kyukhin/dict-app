import XCTest

class HistoryPage: BasePage {

    // UI Elements
    private var historyList: XCUIElement {
        if app.tables[AccessibilityIdentifiers.History.historyList].exists {
            return app.tables[AccessibilityIdentifiers.History.historyList]
        }
        if app.collectionViews[AccessibilityIdentifiers.History.historyList].exists {
            return app.collectionViews[AccessibilityIdentifiers.History.historyList]
        }
        if app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyList].exists {
            return app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyList]
        }
        if app.tables.firstMatch.exists {
            return app.tables.firstMatch
        }
        return app.collectionViews.firstMatch
    }

    // MARK: - Actions

    @discardableResult
    func tapHistoryItem(at index: Int) -> DefinitionPage {
        let cells = historyList.cells
        XCTAssertTrue(cells.count > index, "History item at index \(index) does not exist")

        let cell = cells.element(boundBy: index)
        XCTAssertTrue(cell.waitForExistence(timeout: TestData.Timeouts.medium))
        cell.tap()

        return DefinitionPage(app: app)
    }

    @discardableResult
    func tapHistoryItemWithWord(_ word: String) -> DefinitionPage {
        let historyItem = app.cells[AccessibilityIdentifiers.History.historyItem(word: word)]
        XCTAssertTrue(historyItem.waitForExistence(timeout: TestData.Timeouts.medium))
        historyItem.tap()

        return DefinitionPage(app: app)
    }

    // MARK: - Verification Methods

    func verifyHistoryListExists() -> Bool {
        if app.staticTexts["No History"].exists {
            return true
        }
        return historyList.exists
    }

    func verifyHistoryCount(greaterThan count: Int) -> Bool {
        return historyList.cells.count > count
    }

    func verifyHistoryCount(equalTo count: Int) -> Bool {
        return historyList.cells.count == count
    }

    func verifyHistoryIsEmpty() -> Bool {
        return historyList.cells.count == 0
    }

    func verifyHistoryContainsWord(_ word: String) -> Bool {
        let historyItem = app.cells[AccessibilityIdentifiers.History.historyItem(word: word)]
        if historyItem.exists { return true }
        let cells = historyList.cells
        for i in 0..<cells.count {
            let cell = cells.element(boundBy: i)
            if cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", word)).count > 0 {
                return true
            }
        }
        return false
    }

    func verifyHistoryItemAtIndex(_ index: Int, containsText text: String) -> Bool {
        let cells = historyList.cells
        guard cells.count > index else { return false }

        let cell = cells.element(boundBy: index)
        return cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    func getHistoryCount() -> Int {
        return historyList.cells.count
    }

    func getHistoryItemText(at index: Int) -> String {
        let cells = historyList.cells
        guard cells.count > index else { return "" }

        let cell = cells.element(boundBy: index)
        // SwiftUI NavigationLink rows in a List don't reliably surface the
        // child Text content through `cell.label` (it may be empty or only
        // contain the timestamp). The visible word lives in a staticText
        // descendant — concatenate them, matching the lookup behavior of
        // `verifyHistoryItemAtIndex(_:containsText:)`.
        let texts = cell.staticTexts.allElementsBoundByIndex.map(\.label)
        return texts.joined(separator: " ")
    }

    func waitForHistoryToLoad(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        // Wait for the populated list first (fast path when data exists)
        if app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyList]
            .waitForExistence(timeout: timeout) {
            return true
        }
        // List didn't appear — history must be empty
        return app.staticTexts["No History"].exists
    }

    func verifyHistoryOrder(expectedWords: [String]) -> Bool {
        let cells = historyList.cells
        guard cells.count >= expectedWords.count else { return false }

        for (index, expectedWord) in expectedWords.enumerated() {
            let cell = cells.element(boundBy: index)
            if !cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", expectedWord)).firstMatch.exists {
                return false
            }
        }
        return true
    }
}
