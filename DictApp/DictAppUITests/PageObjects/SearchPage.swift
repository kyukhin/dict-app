import XCTest

class SearchPage: BasePage {

    // UI Elements
    private var searchField: XCUIElement {
        // SwiftUI search fields are accessible via searchFields collection
        app.searchFields.firstMatch
    }

    private var resultsList: XCUIElement {
        // Try multiple approaches to find the results list
        if app.tables[AccessibilityIdentifiers.Search.resultsList].exists {
            return app.tables[AccessibilityIdentifiers.Search.resultsList]
        }
        // Fallback to any table or list
        if app.tables.firstMatch.exists {
            return app.tables.firstMatch
        }
        return app.collectionViews.firstMatch
    }

    // MARK: - Search Actions

func searchFor(_ term: String) {
        searchField.tap()
        searchField.clearAndTypeText(term)
    }

    func clearSearch() {
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.waitForExistence(timeout: 1.0) {
            clearButton.tap()
        } else {
            searchField.tap()
            searchField.clearAndTypeText("")
        }
    }

    // MARK: - Results Interaction

    @discardableResult
    func tapSearchResult(at index: Int) -> DefinitionPage {
        let cells = resultsList.cells
        XCTAssertTrue(cells.count > index, "Search result at index \(index) does not exist")

        let cell = cells.element(boundBy: index)
        XCTAssertTrue(cell.waitForExistence(timeout: TestData.Timeouts.medium))
        cell.tap()

        return DefinitionPage(app: app)
    }

    @discardableResult
    func tapSearchResultWithId(_ id: String) -> DefinitionPage {
        let resultElement = app.cells[AccessibilityIdentifiers.Search.searchResult(id: id)]
        XCTAssertTrue(resultElement.waitForExistence(timeout: TestData.Timeouts.medium))
        resultElement.tap()

        return DefinitionPage(app: app)
    }

    // MARK: - Verification Methods

    func verifySearchFieldExists() -> Bool {
        return searchField.exists
    }

    func verifySearchFieldContains(_ text: String) -> Bool {
        let value = searchField.value as? String ?? ""
        if text.isEmpty {
            // Empty field may show placeholder text instead of ""
            return value.isEmpty || value == searchField.placeholderValue
        }
        return value == text
    }

    func verifyResultsListExists() -> Bool {
        return resultsList.exists
    }

    func verifyResultsCount(greaterThan count: Int) -> Bool {
        return resultsList.cells.count > count
    }

    func verifyResultsCount(equalTo count: Int) -> Bool {
        return resultsList.cells.count == count
    }

    func verifyNoResults() -> Bool {
        return resultsList.cells.count == 0
    }

    func verifyResultContainsText(_ text: String, at index: Int) -> Bool {
        let cells = resultsList.cells
        guard cells.count > index else { return false }

        let cell = cells.element(boundBy: index)
        return cell.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0
    }

    func getResultsCount() -> Int {
        return resultsList.cells.count
    }

    func waitForResults(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let predicate = NSPredicate(format: "count > 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: resultsList.cells)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
