import XCTest

final class HistoryFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
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

    /// #114: the row caption is a localized local time, never the raw UTC `looked_at` text.
    ///
    /// Avoids the #102 flake (History failing to load right after a search):
    /// the lookup is made in this launch, then the app is relaunched without
    /// `-resetData`, so History is the first tab opened by a fresh process with
    /// no search, keyboard or pushed definition around. Tabs are reached by
    /// index (Search 0, History 1), so the label language does not matter.
    func testHistoryRowShowsLocalizedTimeNotRawUTC() throws {
        let word = TestData.historyTestWords[0] // "example"
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(word)
        XCTAssertTrue(searchPage.waitForResults(), "Search results should appear for '\(word)'")
        let definitionPage = searchPage.tapSearchResult(at: 0)
        XCTAssertTrue(definitionPage.waitForDefinitionToLoad(), "Definition should load for '\(word)'")
        definitionPage.navigateBack()

        // Device language: language-agnostic checks only (the suite does not pin it).
        relaunchKeepingData()
        let caption = try historyCaption(for: word)
        XCTAssertNotNil(caption.range(of: #"\d"#, options: .regularExpression),
                        "caption must carry the time of the lookup; got '\(caption)'")

        // Greek in-app language: the same row reads as a Greek relative day.
        // "Χθες" only if the lookup straddled midnight.
        relaunchKeepingData(extraArguments: ["-AppleLanguages", "(el)"])
        let greekCaption = try historyCaption(for: word)
        XCTAssertTrue(greekCaption.contains("Σήμερα") || greekCaption.contains("Χθες"),
                      "Greek caption must be a Greek relative day; got '\(greekCaption)'")
    }

    // MARK: - #114 helpers

    /// Raw `looked_at` text, matched anywhere so a label that merges the word
    /// and the caption cannot hide it.
    private static let rawUTCPattern = #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#

    /// Terminates and relaunches on the same data (history kept).
    private func relaunchKeepingData(extraArguments: [String] = []) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetData" }
        app.launchArguments += extraArguments
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    /// Opens History by tab index on a fresh launch and returns the caption of
    /// `word`'s row: the one label that is not the word. Fails if the caption
    /// is missing or still shows the raw UTC timestamp.
    private func historyCaption(for word: String, file: StaticString = #filePath,
                                line: UInt = #line) throws -> String {
        let historyTab = app.tabBars.firstMatch.buttons.element(boundBy: 1)
        XCTAssertTrue(historyTab.waitForExistence(timeout: TestData.Timeouts.long),
                      "History tab (index 1)", file: file, line: line)
        historyTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let id = AccessibilityIdentifiers.History.historyItem(word: word)
        XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: TestData.Timeouts.long),
                      "History must list '\(word)' after a relaunch", file: file, line: line)
        // The id lands on the cell itself or on its NavigationLink button.
        let cell = app.cells[id].exists ? app.cells[id] : app.cells.containing(.any, identifier: id).firstMatch
        let labels = cell.staticTexts.allElementsBoundByIndex.map(\.label)

        for label in labels {
            XCTAssertNil(label.range(of: Self.rawUTCPattern, options: .regularExpression),
                         "History must not show the raw UTC timestamp; got '\(label)'", file: file, line: line)
        }
        XCTAssertTrue(labels.contains(word), "row must show the word; labels \(labels)", file: file, line: line)
        let captions = labels.filter { $0 != word && !$0.isEmpty }
        XCTAssertEqual(captions.count, 1, "row must show exactly one caption under the word; labels \(labels)",
                       file: file, line: line)
        return try XCTUnwrap(captions.first, file: file, line: line)
    }
}
