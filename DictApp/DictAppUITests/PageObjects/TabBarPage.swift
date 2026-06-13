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

    /// Dismisses the software keyboard if it is showing. On iPad the keyboard
    /// overlays the bottom tab strip after a `.searchable` search, leaving each
    /// tab button present-but-unhittable — a tap then lands on a keyboard key
    /// instead of the tab, so the switch silently no-ops (Issue #76). A no-op
    /// when no keyboard is up, so it is harmless on the iPhone path.
    private func dismissKeyboardIfPresent() {
        guard app.keyboards.count > 0 else { return }
        let hideKey = app.keyboards.buttons["Hide keyboard"]
        if hideKey.exists {
            hideKey.tap()
        } else {
            app.keyboards.firstMatch.swipeDown()
        }
        // Wait for the keyboard to retract so the tab strip becomes hittable.
        let deadline = Date().addingTimeInterval(2.0)
        while app.keyboards.count > 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Taps a tab-bar element. XCUITest's `.tap()` first invokes an AX
    /// `scrollToVisible` action; on iOS 26 with certain SwiftUI layouts
    /// (notably after a NavigationLink push inside the tab) that action fails
    /// with `kAXErrorCannotComplete`, breaking tab navigation entirely. A
    /// coordinate tap skips `scrollToVisible` and works as long as the
    /// element's frame is correct (which it is for tab-bar buttons — they live
    /// in a fixed bottom strip). That is the iPhone path, unchanged.
    ///
    /// iPad needs two extra steps (Issue #76, verified by hierarchy dumps):
    ///   1. The keyboard occludes the tab strip after a `.searchable` search,
    ///      so dismiss it first (above) to make the button hittable.
    ///   2. Even when hittable, a *raw coordinate* tap is swallowed while
    ///      `.searchable` is still active (a "Cancel" button present) — only a
    ///      direct element `.tap()` registers the switch (and clears the search).
    /// So on iPad, once the button is hittable, prefer `.tap()`; otherwise fall
    /// back to the coordinate tap.
    private func coordinateTap(_ element: XCUIElement) {
        // Make sure the element exists before computing a coordinate from it.
        _ = element.waitForExistence(timeout: TestData.Timeouts.medium)
        dismissKeyboardIfPresent()
        if UIDevice.current.userInterfaceIdiom == .pad && element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        popDetailToRootIfNeeded()
    }

    /// Re-selecting an already-active tab pops its NavigationStack to root on
    /// iPhone, but **not** on iPad (Issue #76): a pushed `DefinitionView` stays
    /// on top, so a caller that taps e.g. the Search tab to start a fresh search
    /// finds no search field (`SearchPage` "Search field should exist"). When a
    /// detail view is still showing after the tab tap, pop it the same way
    /// `DefinitionPage.navigateBack` does — tap the leading nav-bar button (the
    /// back chevron). This is safe because the tab root views carry no leading
    /// nav-bar button, so it only ever dismisses a pushed detail. iPhone is
    /// unaffected (it has already popped, so the loop never runs).
    private func popDetailToRootIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let detail = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView]
        var guardCount = 0
        while detail.exists && guardCount < 4 {
            let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
            guard backButton.exists && backButton.isHittable else { break }
            backButton.tap()
            guardCount += 1
            // Wait on the detail view's disappearance — not the nav bar's existence
            // (which is typically already present pre-tap and doesn't synchronize
            // with the pop animation, so the loop could fire mid-transition).
            _ = detail.waitForNonExistence(timeout: TestData.Timeouts.short)
        }
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
