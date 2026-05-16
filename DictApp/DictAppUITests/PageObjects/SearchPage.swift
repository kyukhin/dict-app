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

    /// Dismisses the on-screen keyboard so the tab bar becomes hittable.
    /// On iPhone the keyboard overlays the tab bar after a `.searchable()`
    /// search, so any subsequent `tabBar.buttons[...]` tap would silently
    /// hit the keyboard area instead.
    ///
    /// The commit-key label varies by keyboard type — `.searchable()` uses
    /// "Search" / "search"; standard text fields use "return". We try the
    /// known labels, then fall back to a swipe-down gesture that dismisses
    /// the keyboard in iOS without scrolling the content area.
    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        for label in ["return", "Return", "Search", "search", "Go", "Done"] {
            let key = app.keyboards.buttons[label]
            if key.exists {
                key.tap()
                // Wait briefly for the keyboard to animate out.
                _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2.0)
                return
            }
        }
        // Fallback: scroll the results list down — iOS dismisses the
        // keyboard on a scroll-drag in a scrollable container.
        app.swipeDown()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2.0)
    }

    /// On first use of `.searchable()` iOS 26 surfaces a full-screen
    /// "Siri, Dictation & Privacy" notice that overlays the entire app and
    /// silently intercepts subsequent taps on the tab bar. This method
    /// detects and closes that sheet so tests can carry on.
    func dismissSiriPrivacyNoticeIfPresent() {
        let nav = app.navigationBars["Siri, Dictation & Privacy"]
        guard nav.waitForExistence(timeout: 1.0) else { return }
        // The sheet has a Close button (system "close" symbol) in its
        // navigation bar — tap it via the first button on that bar.
        let close = nav.buttons.firstMatch
        if close.exists {
            close.tap()
        }
    }

    /// Convenience: clears anything that could be blocking the tab bar after
    /// a `.searchable()` interaction (keyboard + Siri privacy sheet).
    func clearOverlaysBeforeTabSwitch() {
        dismissSiriPrivacyNoticeIfPresent()
        dismissKeyboard()
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

    /// Waits for the `ContentUnavailableView` that SearchView renders inside
    /// its List when `results` is empty and `query` is non-empty.
    ///
    /// We can't use `cells.count == 0` because the ContentUnavailableView is
    /// rendered as one cell inside the SwiftUI List — a "no results" state
    /// looks like one cell, not zero. Instead we look for the explicit
    /// accessibility identifier added in `SearchView.swift`.
    func waitForNoResults(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let marker = app.descendants(matching: .any)["search_no_results"]
        return marker.waitForExistence(timeout: timeout)
    }

    func verifyContentUnavailableShown() -> Bool {
        return app.descendants(matching: .any)["search_no_results"].exists
    }
}

