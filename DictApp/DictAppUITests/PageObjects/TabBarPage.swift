import XCTest

class TabBarPage: BasePage {

    private var tabBar: XCUIElement {
        let element = app.tabBars.firstMatch
        _ = element.waitForExistence(timeout: 10)
        return element
    }

    // Tab buttons - scope strictly to tab bar to avoid conflicts
    private var searchTab: XCUIElement {
        // First try by accessibility identifier within tab bar
        if tabBar.buttons["search_tab"].exists {
            return tabBar.buttons["search_tab"]
        }
        // Second try by label within tab bar
        if tabBar.buttons["Search"].exists {
            return tabBar.buttons["Search"]
        }
        // Fallback to first match in tab bars
        return app.tabBars.firstMatch.buttons["Search"]
    }

    private var historyTab: XCUIElement {
        // First try by accessibility identifier within tab bar
        if tabBar.buttons["history_tab"].exists {
            return tabBar.buttons["history_tab"]
        }
        // Second try by label within tab bar
        if tabBar.buttons["History"].exists {
            return tabBar.buttons["History"]
        }
        // Fallback to first match in tab bars
        return app.tabBars.firstMatch.buttons["History"]
    }

    private var bookmarksTab: XCUIElement {
        // First try by accessibility identifier within tab bar
        if tabBar.buttons["bookmarks_tab"].exists {
            return tabBar.buttons["bookmarks_tab"]
        }
        // Second try by label within tab bar
        if tabBar.buttons["Bookmarks"].exists {
            return tabBar.buttons["Bookmarks"]
        }
        // Fallback to first match in tab bars
        return app.tabBars.firstMatch.buttons["Bookmarks"]
    }

    private var settingsTab: XCUIElement {
        if tabBar.buttons["settings_tab"].exists {
            return tabBar.buttons["settings_tab"]
        }
        if tabBar.buttons["Settings"].exists {
            return tabBar.buttons["Settings"]
        }
        return app.tabBars.firstMatch.buttons["Settings"]
    }

    // MARK: - Navigation Methods

    /// Taps a tab-bar element via a normalized center coordinate. XCUITest's
    /// `.tap()` first invokes an AX `scrollToVisible` action; on iOS 26 with
    /// certain SwiftUI layouts (notably after a NavigationLink push inside
    /// the tab) that action fails with `kAXErrorCannotComplete`, breaking
    /// tab navigation entirely. A coordinate tap skips `scrollToVisible`
    /// and works as long as the element's frame is correct (which it is for
    /// tab-bar buttons — they live in a fixed bottom strip).
    private func coordinateTap(_ element: XCUIElement) {
        // Make sure the element exists before computing a coordinate from it.
        _ = element.waitForExistence(timeout: TestData.Timeouts.medium)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    func tapSearchTab() -> SearchPage {
        coordinateTap(searchTab)
        return SearchPage(app: app)
    }

    @discardableResult
    func tapHistoryTab() -> HistoryPage {
        coordinateTap(historyTab)
        return HistoryPage(app: app)
    }

    @discardableResult
    func tapBookmarksTab() -> BookmarksPage {
        coordinateTap(bookmarksTab)
        return BookmarksPage(app: app)
    }

    @discardableResult
    func tapSettingsTab() -> SettingsPage {
        coordinateTap(settingsTab)
        return SettingsPage(app: app)
    }

    // MARK: - Verification Methods

    func verifyTabBarExists() -> Bool {
        return tabBar.exists
    }

    func verifyAllTabsExist() -> Bool {
        return searchTab.exists &&
               historyTab.exists &&
               bookmarksTab.exists &&
               settingsTab.exists
    }

    func verifySearchTabSelected() -> Bool {
        return searchTab.isSelected
    }

    func verifyHistoryTabSelected() -> Bool {
        return historyTab.isSelected
    }

    func verifyBookmarksTabSelected() -> Bool {
        return bookmarksTab.isSelected
    }

    func verifySettingsTabSelected() -> Bool {
        return settingsTab.isSelected
    }

    @available(*, deprecated, renamed: "verifySettingsTabSelected")
    func verifyManageTabSelected() -> Bool {
        return verifySettingsTabSelected()
    }

    @discardableResult
    func tapManageTab() -> SettingsPage {
        return tapSettingsTab()
    }
}
