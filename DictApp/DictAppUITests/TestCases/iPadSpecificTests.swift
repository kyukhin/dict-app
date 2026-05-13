import XCTest

final class iPadSpecificTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    func testAppLaunchesOnIPad() throws {
        // Regression test for Issue #4 - Verify app launches correctly on iPad

        // Skip test if not running on iPad simulator
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Verify basic app functionality on iPad
        XCTAssertTrue(tabBarPage.verifyTabBarExists(), "Tab bar should exist on iPad")
        XCTAssertTrue(tabBarPage.verifyAllTabsExist(), "All tabs should be present on iPad")

        // Verify search functionality works
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search field should exist on iPad")
    }

    func testIPadAdaptiveLayout() throws {
        // Test that the app adapts properly to iPad screen sizes

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Test search view layout
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search field should be properly laid out on iPad")
        XCTAssertTrue(searchPage.verifyResultsListExists(), "Results list should be properly laid out on iPad")

        // Test history view layout
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History list should be properly laid out on iPad")

        // Test bookmarks view layout
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks list should be properly laid out on iPad")
    }

    func testIPadSearchFlow() throws {
        // Test complete search flow on iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        let searchTerm = TestData.searchTerms[0] // "apple"

        // Perform search on iPad
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)

        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear on iPad")
        XCTAssertTrue(searchPage.verifyResultsCount(greaterThan: 0), "Should have search results on iPad")

        // Navigate to definition
        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load on iPad")
        XCTAssertTrue(definitionPage.verifyDefinitionViewExists(), "Definition view should exist on iPad")
    }

    func testIPadNavigationFlow() throws {
        // Test tab navigation on iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Test cycling through all tabs on iPad
        let searchPage = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search tab should work on iPad")

        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History tab should work on iPad")

        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks tab should work on iPad")

        tabBarPage.tapManageTab()
        XCTAssertTrue(tabBarPage.verifyManageTabSelected(), "Manage tab should work on iPad")

        // Return to search
        let searchPageFinal = tabBarPage.tapSearchTab()
        XCTAssertTrue(searchPageFinal.verifySearchFieldExists(), "Should return to search successfully on iPad")
    }

    func testIPadBookmarkFlow() throws {
        // Test bookmark functionality on iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        let searchTerm = TestData.bookmarkTestWords[0] // "apple"

        // Search and bookmark on iPad
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear on iPad")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load on iPad")
        XCTAssertTrue(definitionPage.verifyBookmarkButtonExists(), "Bookmark button should exist on iPad")

        definitionPage.tapBookmarkButton()

        // Verify bookmark appears in bookmarks tab
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load on iPad")
        XCTAssertTrue(
            bookmarksPage.waitForBookmarkToAppear(searchTerm),
            "Bookmarked word should appear in bookmarks list on iPad"
        )
    }

    func testIPadHistoryFlow() throws {
        // Test history functionality on iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        let searchTerms = TestData.historyTestWords.prefix(2) // ["example", "word"]

        // Search for multiple words on iPad
        let searchPage = tabBarPage.tapSearchTab()

        for searchTerm in searchTerms {
            searchPage.searchFor(searchTerm)
            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)' on iPad")

            let definitionPage = searchPage.tapSearchResult(at: 0)
            XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(searchTerm)' on iPad")
            definitionPage.navigateBack()
        }

        // Check history on iPad
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load on iPad")

        for searchTerm in searchTerms {
            XCTAssertTrue(
                historyPage.verifyHistoryContainsWord(searchTerm),
                "History should contain '\(searchTerm)' on iPad"
            )
        }
    }

    func testIPadOrientationStability() throws {
        // Test app stability during orientation changes (if applicable)

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Note: Orientation testing in UI tests can be complex and may require
        // specific simulator setup. This is a basic stability test.

        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(TestData.searchTerms[0])
        XCTAssertTrue(searchPage.waitForResults(), "Search should work before orientation test")

        // Simulate some user interactions that might be affected by orientation
        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Navigate back and test other tabs
        definitionPage.navigateBack()

        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.verifyHistoryListExists(), "History should remain functional")

        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.verifyBookmarksListExists(), "Bookmarks should remain functional")
    }

    func testIPadMultitaskingCompatibility() throws {
        // Test basic multitasking compatibility (app doesn't crash when backgrounded)

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Perform some actions
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(TestData.searchTerms[0])
        XCTAssertTrue(searchPage.waitForResults(), "Search should work")

        // Simulate app backgrounding and foregrounding
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)

        app.activate()
        Thread.sleep(forTimeInterval: 1.0)

        // Verify app is still functional
        XCTAssertTrue(tabBarPage.verifyTabBarExists(), "Tab bar should exist after backgrounding")
        XCTAssertTrue(searchPage.verifySearchFieldExists(), "Search field should exist after backgrounding")
    }

    func testIPadAccessibilityFeatures() throws {
        // Test accessibility features work properly on iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Verify accessibility identifiers are working
        let searchPage = tabBarPage.tapSearchTab()

        // Test that accessibility identifiers are properly set
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.exists, "Search field should be accessible on iPad")

        // Test tab accessibility
        let historyTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.historyTab]
        XCTAssertTrue(historyTab.exists, "History tab should have proper accessibility identifier on iPad")

        let bookmarksTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.bookmarksTab]
        XCTAssertTrue(bookmarksTab.exists, "Bookmarks tab should have proper accessibility identifier on iPad")
    }

    func testIPadPerformance() throws {
        // Basic performance test for iPad

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        let startTime = Date()

        // Perform a series of operations and measure time
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(TestData.searchTerms[0])
        XCTAssertTrue(searchPage.waitForResults(timeout: TestData.Timeouts.medium), "Search should complete within timeout")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(timeout: TestData.Timeouts.medium), "Definition should load within timeout")

        definitionPage.navigateBack()

        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(timeout: TestData.Timeouts.medium), "History should load within timeout")

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Verify operations complete in reasonable time (adjust threshold as needed)
        XCTAssertLessThan(duration, 15.0, "Basic operations should complete within 15 seconds on iPad")
    }
}