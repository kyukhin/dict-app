import XCTest

class TabBarPage: BasePage {

    /// The four tabs, in `ContentView` order. The raw value is the tab's index
    /// in a `UITabBar`.
    enum Tab: Int, CaseIterable {
        case search, history, bookmarks, settings

        /// The tab item's SF Symbol: the tab-button identifier on the iPadOS 26
        /// floating strip. Must match `ContentView`'s `.tabItem` `systemImage`.
        var symbol: String {
            switch self {
            case .search: return AccessibilityIdentifiers.TabBar.searchSymbol
            case .history: return AccessibilityIdentifiers.TabBar.historySymbol
            case .bookmarks: return AccessibilityIdentifiers.TabBar.bookmarksSymbol
            case .settings: return AccessibilityIdentifiers.TabBar.settingsSymbol
            }
        }
    }

    /// Budget for a launch to the Search screen, fresh install included
    /// (Issue #138: nothing is unpacked); see `XCUIApplication.waitForDictionariesReady`.
    static let coldSeedTimeout: TimeInterval = TestData.Timeouts.launch

    /// Every suite builds this page right after `app.launch()`, so wait here,
    /// once, until the Search screen is up rather than in each `setUp`.
    /// Returns at once on a warm launch.
    override init(app: XCUIApplication) {
        super.init(app: app)
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after launch")
    }

    // MARK: - Navigation Methods

    /// Switches to `tab` and checks that the switch landed, so a missed tap
    /// fails here and not later as "History should load" (Issue #102).
    ///
    /// The tap itself:
    ///   - iPad with a `UITabBar` (17.x), button hittable: element `.tap()`.
    ///     A raw coordinate tap is swallowed there while `.searchable` is
    ///     active (Issue #76).
    ///   - Everything else: a coordinate tap. On iOS 26 `.tap()` first runs an
    ///     AX `scrollToVisible` that can fail on tab buttons after a push; a
    ///     coordinate tap skips it. It also works on the iPadOS 26 strip.
    func tap(_ tab: Tab) {
        clearTabObstructions()
        let button = app.tabButton(tab)
        guard button.waitForExistence(timeout: TestData.Timeouts.medium) else {
            XCTFail("\(tab) tab button should exist")
            return
        }
        if UIDevice.current.userInterfaceIdiom == .pad && !app.usesFloatingTabStrip && button.isHittable {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        var selected = waitUntilSelected(tab)
        if !selected {
            let retry = app.tabButton(tab)
            if retry.exists && retry.isHittable {
                retry.tap()
                selected = waitUntilSelected(tab)
            }
        }
        XCTAssertTrue(selected, "Tab \(tab) should be selected after the tap")
        popDetailToRootIfNeeded()
    }

    /// Clears what keeps the tab button from taking the tap: the keyboard.
    /// On iPhone it covers the tab bar after a search, so a tap lands on a key
    /// (Issue #102); on iPad it does too (Issue #76). The tab button itself is
    /// always there, also on iPadOS 26 while the field holds a query (#120).
    private func clearTabObstructions() {
        if app.keyboards.count > 0 {
            app.dismissKeyboardIfPresent()
        }
    }

    /// Polls whether `tab` is selected, re-resolving the button each time.
    private func waitUntilSelected(_ tab: Tab, timeout: TimeInterval = TestData.Timeouts.short) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isSelected(tab) { return true }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return isSelected(tab)
    }

    /// The button's `Selected` trait (both layouts).
    private func isSelected(_ tab: Tab) -> Bool {
        let button = app.tabButton(tab)
        return button.exists && button.isSelected
    }

    /// Selecting the already-active tab does not pop its NavigationStack on
    /// iPhone iOS 17.5, iPad 17.x or iPadOS 26 (only iPhone iOS 26 pops), so a
    /// caller that taps Search to start a fresh search would find a pushed
    /// `DefinitionView` and no search field (Issues #76, #102). Pop it the way
    /// `DefinitionPage.navigateBack` does: tap the leading nav-bar button (the
    /// back button). Safe on every device: tab roots have no back button, and
    /// the loop only runs while a definition is showing.
    private func popDetailToRootIfNeeded() {
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
        tap(.search)
        return SearchPage(app: app)
    }

    @discardableResult
    func tapHistoryTab() -> HistoryPage {
        tap(.history)
        return HistoryPage(app: app)
    }

    @discardableResult
    func tapBookmarksTab() -> BookmarksPage {
        tap(.bookmarks)
        return BookmarksPage(app: app)
    }

    @discardableResult
    func tapSettingsTab() -> SettingsPage {
        tap(.settings)
        return SettingsPage(app: app)
    }

    // MARK: - Verification Methods

    func verifyTabBarExists() -> Bool {
        return app.tabButton(.search).waitForExistence(timeout: TestData.Timeouts.medium)
    }

    func verifyAllTabsExist() -> Bool {
        return Tab.allCases.allSatisfy { app.tabButton($0).exists }
    }

    func verifySearchTabSelected() -> Bool {
        return isSelected(.search)
    }

    func verifyHistoryTabSelected() -> Bool {
        return isSelected(.history)
    }

    func verifyBookmarksTabSelected() -> Bool {
        return isSelected(.bookmarks)
    }

    func verifySettingsTabSelected() -> Bool {
        return isSelected(.settings)
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
