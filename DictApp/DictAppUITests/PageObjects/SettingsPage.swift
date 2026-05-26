import XCTest

class SettingsPage: BasePage {

    // MARK: - UI Elements

    private func toggle(for source: String) -> XCUIElement {
        app.switches[AccessibilityIdentifiers.Settings.dictionaryToggle(source: source)]
    }

    // MARK: - Actions

    /// Taps the toggle for the given source and verifies its state flipped.
    /// Each test launches with `-resetData`, which resets all toggles to ON.
    /// If the first tap doesn't change the accessibility value (some SwiftUI
    /// Toggle hit-targets in iOS 26 don't toggle on label-area taps), we
    /// retry on the right-edge coordinate where the switch handle lives.
    func tapToggle(source: String) {
        let sw = toggle(for: source)
        XCTAssertTrue(
            app.scrollToElement(sw),
            "Toggle for '\(source)' should be reachable in Settings after scrolling"
        )
        let before = isDictionaryEnabled(source: source)
        sw.tap()
        if !waitForStateChange(source: source, from: before, timeout: 3.0) {
            // Fallback: tap the right edge where the switch handle is rendered.
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(
                waitForStateChange(source: source, from: before, timeout: 3.0),
                "Toggle for '\(source)' did not change state after tap (was \(before ?? false))"
            )
        }
    }

    private func waitForStateChange(source: String, from before: Bool?, timeout: TimeInterval) -> Bool {
        let pred = NSPredicate { _, _ in
            self.isDictionaryEnabled(source: source) != before
        }
        let exp = XCTNSPredicateExpectation(predicate: pred, object: nil)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    // MARK: - Verification

    /// Waits for the toggle for the given source to appear and become
    /// hittable. Delegates the scroll search to `XCUIApplication.
    /// scrollToElement`, which sweeps up then down with a swipe budget
    /// that handles the SwiftUI Form virtualisation case where the
    /// Dictionaries section sits below the fold on smaller screens or
    /// after the section grows (e.g. adding the FreeDict eng-spa row in
    /// Issue #24 pushed the Russian toggle further down).
    ///
    /// The `timeout` parameter is retained for source-compatibility with
    /// existing callers; the underlying scroll loop is bounded by swipe
    /// count rather than wall-clock time, and finishes well within the
    /// previous default budget.
    func waitForToggle(source: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        return app.scrollToElement(toggle(for: source))
    }

    /// Returns the SwiftUI Toggle's "on" state, tried via several XCUI
    /// value representations. Returns nil if the toggle isn't found.
    func isDictionaryEnabled(source: String) -> Bool? {
        let sw = toggle(for: source)
        guard sw.exists else { return nil }
        if let s = sw.value as? String { return s == "1" || s.lowercased() == "true" }
        if let b = sw.value as? Bool   { return b }
        if let i = sw.value as? Int    { return i == 1 }
        return nil
    }

    // MARK: - Manage Dictionaries navigation

    private var manageDictionariesLink: XCUIElement {
        // SwiftUI NavigationLink usually surfaces as a button or cell — accept
        // either, indexed by the accessibility identifier set on the view.
        let id = AccessibilityIdentifiers.Settings.manageDictionariesLink
        if app.buttons[id].exists { return app.buttons[id] }
        if app.cells[id].exists   { return app.cells[id] }
        return app.descendants(matching: .any)[id]
    }

    /// Waits for the "Manage Dictionaries" navigation row to be reachable.
    ///
    /// The link itself is *unconditionally* rendered inside the Dictionaries
    /// section in `SettingsView` — it's outside the `if dictionaries.isEmpty`
    /// branch — so the only failure mode is cell-virtualization: SwiftUI's
    /// `Form` is backed by a `UICollectionView` that only materializes cells
    /// in/near the visible region.
    ///
    /// Strategy: first wait for the Settings screen itself to mount (so we
    /// don't swipe on a half-loaded tab transition), then delegate the
    /// scroll search to the shared `XCUIApplication.scrollToElement` helper.
    func waitForManageDictionariesLink(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        // Wait for the Settings screen itself to mount — any navigation
        // bar is a reliable per-tab indicator and is present regardless
        // of `SettingsViewModel.dictionaries` load state. Match by
        // first-existence rather than the localized title "Settings" so
        // the wait holds under non-English UI languages.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: timeout)
        return app.scrollToElement(manageDictionariesLink)
    }

    /// Taps "Manage Dictionaries" and returns the destination page object.
    @discardableResult
    func tapManageDictionariesLink() -> ManageDictionariesPage {
        XCTAssertTrue(
            waitForManageDictionariesLink(timeout: TestData.Timeouts.long),
            "Manage Dictionaries link should be reachable in Settings"
        )
        manageDictionariesLink.tap()
        return ManageDictionariesPage(app: app)
    }
}
