import XCTest

final class NavigationTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    func testTabBarExists() throws {
        // Verify tab bar is present and functional
        XCTAssertTrue(tabBarPage.verifyTabBarExists(), "Tab bar should exist")
        XCTAssertTrue(tabBarPage.verifyAllTabsExist(), "All tabs should be present")
    }

    func testSearchTabNavigation() throws {
        // Test navigation to Search tab
        let searchPage = tabBarPage.tapSearchTab()

        XCTAssertTrue(tabBarPage.verifySearchTabSelected(), "Search tab should be selected")
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search field should be visible")
    }

    func testHistoryTabNavigation() throws {
        // Test navigation to History tab
        let historyPage = tabBarPage.tapHistoryTab()

        XCTAssertTrue(tabBarPage.verifyHistoryTabSelected(), "History tab should be selected")
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History list should be visible")
    }

    func testBookmarksTabNavigation() throws {
        // Test navigation to Bookmarks tab
        let bookmarksPage = tabBarPage.tapBookmarksTab()

        XCTAssertTrue(tabBarPage.verifyBookmarksTabSelected(), "Bookmarks tab should be selected")
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks list should be visible")
    }

    func testManageTabNavigation() throws {
        // Test navigation to Manage tab
        tabBarPage.tapManageTab()

        XCTAssertTrue(tabBarPage.verifySettingsTabSelected(), "Settings tab should be selected")
        // Note: Manage tab functionality would need specific verification based on implementation
    }

    func testTabSwitchingPreservesState() throws {
        // SearchView holds its query in a @StateObject, so tab switching
        // must not reset the underlying search state — coming back to the
        // Search tab should still show the results that were on screen.
        //
        // On iOS 26 the visible `.searchable()` field collapses when its
        // host tab loses focus and the rendered field text shows as empty
        // until the user re-activates the field. That's iOS chrome, not
        // app state — `vm.query` itself is preserved, which is what the
        // user actually cares about. We therefore assert the *results
        // list* still contains entries (proving `vm.query` survived), and
        // do not assert on the field's displayed text.
        let searchPage = tabBarPage.tapSearchTab()
        let searchTerm = TestData.searchTerms[0]
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        let baselineCount = searchPage.getResultsCount()
        XCTAssertGreaterThan(baselineCount, 0, "Pre-condition: search returned at least one result")

        // Switch to History tab and back.
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History should load")

        let searchPageAgain = tabBarPage.tapSearchTab()

        // The results list — driven by `vm.query`/`vm.results` — must still
        // be populated. This is the real "state preserved" signal: if
        // tab-switching had blown away the query, the view would fall back
        // to the Recent list or be empty.
        XCTAssertTrue(
            searchPageAgain.verifyResultsCount(greaterThan: 0),
            "Search results must still be visible after returning from another tab"
        )
        XCTAssertEqual(
            searchPageAgain.getResultsCount(), baselineCount,
            "Result count must match the pre-tab-switch baseline; differing means vm.query changed"
        )
    }

    func testCompleteTabCycle() throws {
        // Test cycling through all tabs

        // Start at Search
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search tab should be functional")

        // Move to History
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History tab should be functional")

        // Move to Bookmarks
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks tab should be functional")

        // Move to Manage
        tabBarPage.tapManageTab()
        XCTAssertTrue(tabBarPage.verifySettingsTabSelected(), "Settings tab should be selected")

        // Return to Search
        let searchPageFinal = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPageFinal.verifySearchFieldExists(), "Should return to Search successfully")
    }

    func testNavigationStackBehavior() throws {
        // Test proper navigation stack behavior

        // Start with search and navigate to definition
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(TestData.searchTerms[0])
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Navigate back to search
        let searchPageAgain = definitionPage.navigateBack()
        XCTAssertTrue(searchPageAgain.verifySearchFieldExists(), "Should return to search view")

        // Verify we're still on the search tab
        XCTAssertTrue(tabBarPage.verifySearchTabSelected(), "Should still be on search tab")
    }

    func testTabNavigationFromDefinitionView() throws {
        // Test tab navigation while viewing a definition

        // Navigate to definition
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(TestData.searchTerms[1])
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Switch to History tab from definition view
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History should load")
        XCTAssertTrue(tabBarPage.verifyHistoryTabSelected(), "History tab should be selected")

        // Switch to Bookmarks tab
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks should load")
        XCTAssertTrue(tabBarPage.verifyBookmarksTabSelected(), "Bookmarks tab should be selected")
    }

    func testRapidTabSwitching() throws {
        // Test rapid tab switching for stability

        for _ in 0..<3 {
            tabBarPage.tapSearchTab()
            tabBarPage.tapHistoryTab()
            tabBarPage.tapBookmarksTab()
            tabBarPage.tapManageTab()
        }

        // Verify final state
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "App should remain stable after rapid switching")
        XCTAssertTrue(tabBarPage.verifySearchTabSelected(), "Search tab should be properly selected")
    }
}
