import XCTest

final class HistoryFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-resetData")

        // iOS 26 surfaces an "Enable Dictation?" springboard alert the first
        // time `.searchable()` is activated. XCUI's default handler taps the
        // wrong button (the "About Siri & Dictation…" info link) which then
        // covers the tab bar and breaks the test. Install our own handler
        // that picks a dismissal label.
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
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    func testBasicHistoryFlow() throws {
        // Test: Search multiple words → check History tab shows recent searches
        let searchTerms = TestData.historyTestWords // ["example", "word", "book"]

        // Search for multiple words to populate history
        let searchPage = tabBarPage.tapSearchTab()

        for searchTerm in searchTerms {
            searchPage.searchFor(searchTerm)
            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)'")

            // View definition to ensure it's added to history
            let definitionPage = searchPage.tapSearchResult(at: 0)
            XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(searchTerm)'")

            // Navigate back to search for next term
            definitionPage.navigateBack()
        }

        // Check history tab
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Verify history contains searched words
        XCTAssertTrue(
            historyPage.verifyHistoryCount(greaterThan: 0),
            "History should contain searched words"
        )

        // Verify at least some of the searched terms appear in history
        for searchTerm in searchTerms {
            XCTAssertTrue(
                historyPage.verifyHistoryContainsWord(searchTerm),
                "History should contain '\(searchTerm)'"
            )
        }
    }

    func testHistoryOrdering() throws {
        // Test that history shows most recent searches first
        let searchTerms = TestData.historyTestWords.prefix(3) // ["example", "word", "book"]

        let searchPage = tabBarPage.tapSearchTab()

        // Search for words in order
        for searchTerm in searchTerms {
            searchPage.searchFor(searchTerm)
            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)'")

            let definitionPage = searchPage.tapSearchResult(at: 0)
            XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(searchTerm)'")
            definitionPage.navigateBack()
        }

        // Check history ordering
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Verify most recent search appears first (reverse order)
        let expectedOrder = Array(searchTerms.reversed())
        XCTAssertTrue(
            historyPage.verifyHistoryOrder(expectedWords: expectedOrder),
            "History should show most recent searches first"
        )
    }

    func testHistoryNavigation() throws {
        // Test navigating from history item to definition
        let searchTerm = TestData.historyTestWords[0] // "example"

        // First add item to history
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.navigateBack()

        // Navigate to history and tap item
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")
        XCTAssertTrue(historyPage.verifyHistoryContainsWord(searchTerm), "History should contain the word")

        let definitionFromHistory = historyPage.tapHistoryItem(at: 0)

        // Verify definition loads from history
        XCTAssertTrue(
            definitionFromHistory.waitForDefinitionToLoad(),
            "Definition should load from history"
        )
        XCTAssertTrue(
            definitionFromHistory.verifyDefinitionViewExists(),
            "Definition view should exist"
        )
        XCTAssertTrue(
            definitionFromHistory.verifyDefinitionContentExists(),
            "Definition content should exist"
        )
    }

    func testHistoryPersistence() throws {
        // Test that history persists across app launches
        let searchTerm = TestData.historyTestWords[1] // "word"

        // Add item to history
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.navigateBack()

        // Verify item is in history
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")
        XCTAssertTrue(historyPage.verifyHistoryContainsWord(searchTerm), "History should contain the word")

        // Simulate app restart. CRUCIAL: drop `-resetData` from the launch
        // args before the relaunch — otherwise the freshly-added history
        // would be wiped and the assertion below would be vacuous.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetData" }
        app.launch()

        // Reinitialize page objects
        tabBarPage = TabBarPage(app: app)
        let historyPageAfterRestart = tabBarPage.tapHistoryTab()

        // Verify history persists
        XCTAssertTrue(
            historyPageAfterRestart.waitForHistoryToLoad(),
            "History should load after restart"
        )
        XCTAssertTrue(
            historyPageAfterRestart.verifyHistoryContainsWord(searchTerm),
            "History should persist after app restart"
        )
    }

    func testEmptyHistory() throws {
        // `-resetData` in setUp wipes history, so we can assert empty state
        // unconditionally. The `No History` ContentUnavailableView must be
        // showing, and there must be zero history cells.
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        XCTAssertTrue(
            app.staticTexts["No History"].waitForExistence(timeout: TestData.Timeouts.medium),
            "Empty-state ContentUnavailableView must be visible when history is empty"
        )
        XCTAssertTrue(
            historyPage.verifyHistoryIsEmpty(),
            "History list must report zero entries on first launch with -resetData"
        )
    }

    func testHistoryItemContent() throws {
        // Test that history items display correct content
        let searchTerm = TestData.historyTestWords[2] // "book"

        // Add item to history
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.navigateBack()

        // Check history item content
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Verify history item contains the search term
        XCTAssertTrue(
            historyPage.verifyHistoryItemAtIndex(0, containsText: searchTerm),
            "History item should contain the search term"
        )

        let historyItemText = historyPage.getHistoryItemText(at: 0)
        XCTAssertTrue(
            historyItemText.lowercased().contains(searchTerm.lowercased()),
            "History item text should contain the search term"
        )
    }

    func testMultipleHistoryEntries() throws {
        // Test multiple history entries and their management
        let searchTerms = TestData.historyTestWords // ["example", "word", "book"]

        let searchPage = tabBarPage.tapSearchTab()

        // Add multiple items to history
        for searchTerm in searchTerms {
            searchPage.searchFor(searchTerm)
            XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(searchTerm)'")

            let definitionPage = searchPage.tapSearchResult(at: 0)
            XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(searchTerm)'")
            definitionPage.navigateBack()
        }

        // Verify all items in history
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        let historyCount = historyPage.getHistoryCount()
        XCTAssertTrue(
            historyCount >= searchTerms.count,
            "History should contain at least \(searchTerms.count) items"
        )

        // Verify each search term appears in history
        for searchTerm in searchTerms {
            XCTAssertTrue(
                historyPage.verifyHistoryContainsWord(searchTerm),
                "History should contain '\(searchTerm)'"
            )
        }
    }

    func testHistoryFromBookmarkNavigation() throws {
        // Test that accessing bookmarks also updates history
        let searchTerm = TestData.historyTestWords[0] // "example"

        // First bookmark a word
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")

        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load")
        definitionPage.tapBookmarkButton()
        definitionPage.navigateBack()

        // Access word from bookmarks
        let bookmarksPage = tabBarPage.tapBookmarksTab()
        XCTAssertTrue(bookmarksPage.waitForBookmarksToLoad(), "Bookmarks should load")

        let definitionFromBookmark = bookmarksPage.tapBookmarkItem(at: 0)
        XCTAssertTrue(definitionFromBookmark.waitForDefinitionToLoad(), "Definition should load from bookmark")
        definitionFromBookmark.navigateBack()

        // Check if this appears in history
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        // Verify the word appears in history (may appear multiple times)
        XCTAssertTrue(
            historyPage.verifyHistoryContainsWord(searchTerm),
            "Word accessed from bookmark should appear in history"
        )
    }

    func testHistoryUpdateOnRepeatedSearch() throws {
        // Test that searching for the same word updates its position in history
        let searchTerm = TestData.historyTestWords[0] // "example"
        let otherTerm = TestData.historyTestWords[1] // "word"

        let searchPage = tabBarPage.tapSearchTab()

        // Search for first term
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        let definitionPage1 = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage1.waitForDefinitionToLoad(), "Definition should load")
        definitionPage1.navigateBack()

        // Search for second term
        searchPage.searchFor(otherTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        let definitionPage2 = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage2.waitForDefinitionToLoad(), "Definition should load")
        definitionPage2.navigateBack()

        // Search for first term again
        searchPage.searchFor(searchTerm)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear")
        let definitionPage3 = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage3.waitForDefinitionToLoad(), "Definition should load")
        definitionPage3.navigateBack()

        // Check history - first term should be at the top again
        let historyPage = tabBarPage.tapHistoryTab()
        XCTAssertTrue(historyPage.waitForHistoryToLoad(), "History should load")

        XCTAssertTrue(
            historyPage.verifyHistoryItemAtIndex(0, containsText: searchTerm),
            "Most recently searched term should be at the top of history"
        )
    }
}
