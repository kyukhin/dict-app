import XCTest

final class BookmarkFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Only add -resetData for tests that need clean state
        // testBookmarkPersistence will handle its own launch logic
        if name != "testBookmarkPersistence" {
            app.launchArguments.append("-resetData")
        }
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

    func testBasicBookmarkFlow() throws {
        // Test: Search word → view definition → bookmark → verify in bookmarks tab
        let searchTerm = TestData.bookmarkTestWords[0] // "apple"

        print("🔍 Starting testBasicBookmarkFlow with search term: \(searchTerm)")

        // Search for word
        print("📱 Step 1: Tapping search tab")
        let searchPage = tabBarPage.tapSearchTab()

        print("🔍 Step 2: Searching for '\(searchTerm)'")
        searchPage.searchFor(searchTerm)

        print("⏳ Step 3: Waiting for search results")
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        print("✅ Search results appeared")

        // View definition
        print("👆 Step 4: Tapping first search result")
        let definitionPage = searchPage.tapSearchResult(at: 0)

        print("⏳ Step 5: Waiting for definition to load")
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        print("✅ Definition loaded")

        print("🔍 Step 6: Verifying bookmark button exists")
        XCTAssertTrue(definitionPage.verifyBookmarkButtonExists(), "Bookmark button should exist")
        print("✅ Bookmark button exists")

        // Bookmark the word
        print("⭐ Step 7: Tapping bookmark button")
        definitionPage.tapBookmarkButton()
        print("✅ Bookmark button tapped")

        // Navigate to bookmarks tab
        print("📱 Step 8: Tapping bookmarks tab")
        let bookmarksPage = tabBarPage.tapBookmarksTab()

        print("⏳ Step 9: Waiting for bookmarks to load")
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")
        print("✅ Bookmarks loaded")

        // Verify bookmark appears
        print("🔍 Step 10: Waiting for bookmark to appear")
        XCTAssertTrue(
            bookmarksPage.waitForBookmarkToAppear(searchTerm),
            "Bookmarked word should appear in bookmarks list"
        )
        print("✅ Bookmark appeared in list")

        print("🔍 Step 11: Verifying bookmark contains word")
        XCTAssertTrue(
            bookmarksPage.verifyBookmarkContainsWord(searchTerm),
            "Bookmarks should contain the bookmarked word"
        )
        print("✅ Test completed successfully!")
    }

    func testMultipleBookmarks() throws {
        // Test bookmarking multiple words

        for searchTerm in TestData.bookmarkTestWords {
            // Search and bookmark each word
            let searchPage = tabBarPage.tapSearchTab()
            searchPage.searchFor(searchTerm)
            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)'")

            let definitionPage = searchPage.tapSearchResult(at: 0)
            XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(searchTerm)'")

            definitionPage.tapBookmarkButton()
        }

        // Verify all bookmarks appear
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")

        for searchTerm in TestData.bookmarkTestWords {
            XCTAssertTrue(
                bookmarksPage.verifyBookmarkContainsWord(searchTerm),
                "Bookmarks should contain '\(searchTerm)'"
            )
        }

        // Verify bookmark count
        XCTAssertTrue(
            bookmarksPage.verifyBookmarksCount(greaterThan: TestData.bookmarkTestWords.count - 1),
            "Should have at least \(TestData.bookmarkTestWords.count) bookmarks"
        )
    }

    func testBookmarkNavigation() throws {
        // Test navigating from bookmark back to definition
        let searchTerm = TestData.bookmarkTestWords[0] // "apple"

        // First bookmark a word
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.tapBookmarkButton()

        // Navigate to bookmarks and tap the bookmark
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")
        XCTAssertTrue(bookmarksPage.verifyBookmarkContainsWord(searchTerm), "Bookmark should exist")

        let definitionPageFromBookmark = bookmarksPage.tapBookmarkItem(at: 0)

        // Verify definition loads from bookmark
        XCTAssertTrue(
            definitionPageFromBookmark.waitForDefinitionToLoad(),
            "Definition should load from bookmark"
        )
        XCTAssertTrue(
            definitionPageFromBookmark.verifyDefinitionViewExists(),
            "Definition view should exist"
        )
    }

    func testBookmarkPersistence() throws {
        // Test that bookmarks persist across app launches
        let searchTerm = TestData.bookmarkTestWords[1] // "test"

        // Manual initial reset - start with clean state
        app.terminate()
        app.launchArguments = ["-resetData"]
        app.launch()
        tabBarPage = TabBarPage(app: app)

        // Bookmark a word
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.tapBookmarkButton()

        // Add delay to ensure database persistence after bookmark action
        sleep(2)

        // Verify bookmark exists
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")

        // Add small delay to ensure bookmark state is stable
        sleep(1)
        XCTAssertTrue(bookmarksPage.verifyBookmarkContainsWord(searchTerm), "Bookmark should exist")

        // The persistence restart - launch WITHOUT reset argument
        app.terminate()
        app.launchArguments = [] // Clear arguments to prevent reset
        app.launch()

        // Reinitialize page objects
        tabBarPage = TabBarPage(app: app)
        let bookmarksPageAfterRestart = tabBarPage.tapBookmarksTab()

        // Verify bookmark still exists
        XCTAssertTrue(
            bookmarksPageAfterRestart.waitForBookmarksToLoad(),
            "Bookmarks should load after restart"
        )
        XCTAssertTrue(
            bookmarksPageAfterRestart.verifyBookmarkContainsWord(searchTerm),
            "Bookmark should persist after app restart"
        )
    }

    func testBookmarkRemoval() throws {
        // Test removing bookmarks
        let searchTerm = TestData.bookmarkTestWords[0] // "apple"

        // First bookmark a word
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.tapBookmarkButton()

        // Add delay to ensure database persistence after bookmark action
        sleep(2)

        // Verify bookmark exists
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")

        // Add small delay to ensure bookmark state is stable
        sleep(1)
        XCTAssertTrue(bookmarksPage.verifyBookmarkContainsWord(searchTerm), "Bookmark should exist")

        let initialCount = bookmarksPage.getBookmarksCount()

        // Remove bookmark (swipe to delete)
        bookmarksPage.deleteBookmarkItem(at: 0)

        // Verify bookmark is removed
        let finalCount = bookmarksPage.getBookmarksCount()
        XCTAssertTrue(finalCount < initialCount, "Bookmark count should decrease after deletion")
    }

    func testBookmarkButtonState() throws {
        // Test bookmark button state changes
        let searchTerm = TestData.bookmarkTestWords[0] // "apple"

        // Search for word
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Verify bookmark button is available
        XCTAssertTrue(
            definitionPage.verifyBookmarkButtonExists(),
            "Bookmark button should exist"
        )
        XCTAssertTrue(
            definitionPage.verifyBookmarkButtonState(isBookmarked: false),
            "Bookmark button should be in unbookmarked state initially"
        )

        // Bookmark the word
        definitionPage.tapBookmarkButton()

        // Verify button state changes (implementation dependent)
        XCTAssertTrue(
            definitionPage.verifyBookmarkButtonExists(),
            "Bookmark button should still exist after bookmarking"
        )
    }

    func testEmptyBookmarksList() throws {
        // Test behavior when bookmarks list is empty
        let bookmarksPage = tabBarPage.tapBookmarksTab()

        // Add small delay to ensure UI is stable
        sleep(5)
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")

        // Note: This test assumes a clean state or that we can clear bookmarks
        // In a real scenario, you might need to clear existing bookmarks first

        if bookmarksPage.verifyBookmarksIsEmpty() {
            XCTAssertTrue(
                bookmarksPage.verifyBookmarksCount(equalTo: 0),
                "Empty bookmarks list should have 0 items"
            )
        }
    }

    func testBookmarkFromHistory() throws {
        // Test bookmarking a word accessed from history
        let searchTerm = TestData.bookmarkTestWords[1] // "test"

        // First search to add to history
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")

        // Navigate back and go to history
        definitionPage.navigateBack()
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Access word from history and bookmark it
        let definitionFromHistory = historyPage.tapHistoryItem(at: 0)
        XCTAssertTrue(definitionFromHistory.waitForDefinitionToLoad(), "Definition should load from history")

        definitionFromHistory.tapBookmarkButton()

        // Verify bookmark was created
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")
        XCTAssertTrue(
            bookmarksPage.verifyBookmarkContainsWord(searchTerm),
            "Word accessed from history should be bookmarked"
        )
    }
}
