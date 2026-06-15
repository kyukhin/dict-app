import XCTest

final class SearchFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!
    var searchPage: SearchPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
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

        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
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
        // Skip on Intel x86_64 + iOS 18.x simulator. Empirically (diagnostic
        // dump, 2026-06-08), the SwiftUI results `List` on that runtime drops
        // long-definition `EntryRow` cells from the rendered/accessible cell
        // tree entirely — definition-length-triggered (the two "procedure"-
        // bearing rows for query "test" have def_len 425 / 1520 and vanish;
        // every surfaced row is ≤122 chars), occupying zero layout space. The
        // probe walks results positionally, so those rows are unreachable and
        // the match is never found. NOT a #56 regression: this test only ever
        // passed on arch/OS combos that materialize the long-def cells (arm64 /
        // iOS 26 stays green). Production-thread investigation tracked in #60;
        // `ALLOW_LONG_DEF_FLAKE` re-enables the test there without editing it.
        // Apple fixed the drop in the iOS 18.6 SDK runtime (re-verified on the
        // 18.6 sim, both current master and pre-#6), so the skip is now narrowed
        // to iOS 18.0–18.5; 18.6+ renders the long cells and runs the test.
        #if arch(x86_64)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if ProcessInfo.processInfo.environment["ALLOW_LONG_DEF_FLAKE"] == nil,
           os.majorVersion == 18, os.minorVersion < 6 {
            throw XCTSkip("Intel x86_64 + iOS 18.0–18.5 sim drops long-definition cells (fixed by Apple in iOS 18.6); see #60.")
        }
        #endif

        // End-to-end: search → tap a matching result → definition view loads
        // with the expected content.
        //
        // We don't pin a specific result index. Bundling additional sources
        // (e.g. the FreeDict eng-spa pair in Issue #24) changes FTS5's BM25
        // ranking and shuffles the top-N for common headwords, so the old
        // "result #0 is the WordNet entry" assumption was brittle. Instead,
        // walk the visible results until one whose definition contains the
        // expected substring is found, navigating back between attempts.
        let searchTerm = TestData.searchTerms[1] // "test"
        guard let expectedContent = TestData.expectedResults[searchTerm] else {
            XCTFail("TestData.expectedResults is missing an entry for '\(searchTerm)'")
            return
        }

        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        // Cap the probe so a real regression (the term has no matching
        // definition at all) fails the test in bounded time. 10 results is
        // far more than any single source contributes to the top of a query
        // for a common word — if the expected content isn't in the first 10,
        // something is genuinely wrong with the seed.
        let resultCount = searchPage.getResultsCount()
        XCTAssertGreaterThan(resultCount, 0, "Search for '\(searchTerm)' returned no results")
        let probeLimit = min(10, resultCount)

        var matchedIndex: Int?
        for index in 0..<probeLimit {
            let definitionPage = searchPage.tapSearchResult(at: index)
            XCTAssertTrue(
                definitionPage.waitForDefinitionToLoad(),
                "Definition view should load for result #\(index)"
            )
            if definitionPage.verifyDefinitionContainsText(expectedContent) {
                matchedIndex = index
                break
            }
            // Not the match we want — navigate back and try the next one.
            // The search query stays in the field, so results are intact.
            definitionPage.navigateBack()
            XCTAssertTrue(
                searchPage.waitForResults(),
                "Results list should re-appear after navigating back from result #\(index)"
            )
        }

        XCTAssertNotNil(
            matchedIndex,
            "No result among the first \(probeLimit) for '\(searchTerm)' had a definition containing '\(expectedContent)'"
        )
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
