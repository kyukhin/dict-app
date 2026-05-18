import XCTest

final class SearchFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!
    var searchPage: SearchPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-resetData")

        // iOS 26 surfaces an "Enable Dictation?" springboard alert the first
        // time `.searchable()` is activated. XCUI's default handler taps the
        // wrong button ("About Siri & Dictation…") which then covers the tab
        // bar and breaks the test. Install our own handler that picks a
        // dismissal label.
        addUIInterruptionMonitor(withDescription: "Enable Dictation alert") { alert in
            for label in ["Not Now", "Cancel", "Don't Enable", "Don't Allow", "Enable Dictation"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        tabBarPage = TabBarPage(app: app)
        searchPage = tabBarPage.tapSearchTab()
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
        searchPage = nil
    }

    func testBasicSearchFlow() throws {
        // Test: Enter search term → verify results → tap result → verify definition view
        let searchTerm = TestData.searchTerms[0] // "apple"

        // Perform search
        searchPage.searchFor(searchTerm)

        // Verify search results appear
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        XCTAssertTrue(searchPage.verifyResultsCount(greaterThan: 0), "Should have search results")

        // Tap first result
        let definitionPage = searchPage.tapSearchResult(at: 0)

        // Verify definition view loads
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        XCTAssertTrue(definitionPage.verifyDefinitionViewExists(), "Definition view should exist")
        XCTAssertTrue(definitionPage.verifyDefinitionContentExists(), "Definition content should exist")
    }

    func testSearchWithMultipleTerms() throws {
        // Test multiple search terms to verify search functionality
        for searchTerm in TestData.searchTerms.prefix(3) {
            searchPage.searchFor(searchTerm)

            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)'")
            XCTAssertTrue(searchPage.verifyResultsCount(greaterThan: 0), "Should have results for '\(searchTerm)'")

            // Clear search for next iteration
            searchPage.clearSearch()
        }
    }

    func testSearchResultContent() throws {
        // Test that search results contain expected content
        let searchTerm = TestData.searchTerms[0] // "apple"

        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        // Verify first result contains the search term
        XCTAssertTrue(
            searchPage.verifyResultContainsText(searchTerm, at: 0),
            "First result should contain the search term"
        )
    }

    func testSearchToDefinitionNavigation() throws {
        // Test complete flow from search to definition
        let searchTerm = TestData.searchTerms[1] // "test"

        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)

        // Verify definition contains expected content
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        if let expectedContent = TestData.expectedResults[searchTerm] {
            XCTAssertTrue(
                definitionPage.verifyDefinitionContainsText(expectedContent),
                "Definition should contain expected content"
            )
        }
    }

    func testSearchFieldFunctionality() throws {
        // Test search field behavior
        let searchTerm = "example"

        // Verify search field exists
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search field should exist")

        // Type in search field
        searchPage.searchFor(searchTerm)

        // Verify search field contains the text
        XCTAssertTrue(
            searchPage.verifySearchFieldContains(searchTerm),
            "Search field should contain the typed text"
        )

        // Clear search
        searchPage.clearSearch()

        // Verify search field is cleared
        XCTAssertTrue(
            searchPage.verifySearchFieldContains(""),
            "Search field should be empty after clearing"
        )
    }

    func testEmptySearchResults() throws {
        // A search term that cannot exist in either bundled dictionary.
        let nonExistentTerm = "xyzzyx123nonexistent"

        searchPage.searchFor(nonExistentTerm)

        // The empty-state ContentUnavailableView SwiftUI renders inside the
        // results List is *one* cell — so `cells.count == 0` is the wrong
        // signal. Wait on the explicit `search_no_results` identifier
        // instead, which is the unambiguous "zero matches" marker.
        XCTAssertTrue(
            searchPage.waitForNoResults(timeout: TestData.Timeouts.medium),
            "Search for a non-existent term must show the no-results view"
        )
    }

    func testSearchHistoryUpdated() throws {
        // Test that search updates history
        let searchTerm = TestData.searchTerms[2] // "example"

        // Perform search and view definition
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Navigate back to search
        definitionPage.navigateBack()

        // Go to history tab
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Verify search term appears in history
        XCTAssertTrue(
            historyPage.verifyHistoryContainsWord(searchTerm),
            "History should contain the searched word"
        )
    }
}
