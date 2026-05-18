import XCTest

class SettingsPage: BasePage {

    // MARK: - UI Elements

    /// The Settings form is a SwiftUI `Form`. XCUI exposes it as a
    /// `collectionView`, `scrollView`, or `table` depending on the OS
    /// version. We pick the first one that exists; if none do, callers
    /// fall back to swiping the whole app element.
    private var form: XCUIElement? {
        let candidates: [XCUIElement] = [
            app.collectionViews.firstMatch,
            app.scrollViews.firstMatch,
            app.tables.firstMatch
        ]
        return candidates.first(where: { $0.exists })
    }

    private func swipeContainerUp() {
        if let f = form { f.swipeUp() } else { app.swipeUp() }
    }

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
        XCTAssertTrue(
            waitForToggle(source: source, timeout: TestData.Timeouts.long),
            "Toggle for '\(source)' should appear in Settings"
        )
        let sw = toggle(for: source)
        scrollToElement(sw)
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

    /// Waits for the toggle for the given source to appear. Scrolls once if
    /// the toggle isn't immediately visible (the Dictionaries section may
    /// be below the fold on smaller screens).
    func waitForToggle(source: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let sw = toggle(for: source)
        if sw.waitForExistence(timeout: timeout) { return true }
        swipeContainerUp()
        return sw.waitForExistence(timeout: timeout)
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

    // MARK: - Helpers

    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            swipeContainerUp()
            swipes += 1
        }
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

    /// Waits for the "Manage Dictionaries" navigation row.
    ///
    /// The link itself is *unconditionally* rendered inside the
    /// Dictionaries section in `SettingsView` — it's outside the
    /// `if dictionaries.isEmpty` branch — so the only failure mode is
    /// cell-virtualization: SwiftUI's `Form` is backed by a
    /// `UICollectionView` that only materializes cells in/near the visible
    /// region. After many launches the simulator's scene-state restoration
    /// can resume Settings at any scroll offset (often the bottom on warm
    /// runs), keeping the link off the rendered-cell window. `exists`
    /// then returns false even though the link is in the SwiftUI view
    /// hierarchy.
    ///
    /// Strategy:
    ///   1) Wait for *some* sign Settings rendered — the navigation title
    ///      "Settings". Without this we'd be swiping a tab bar or a wrong
    ///      form when the tab transition is still in flight.
    ///   2) Probe for the link. If visible, done.
    ///   3) Otherwise sweep the form in both directions a few times. We
    ///      don't know whether scene restoration parked it above or below
    ///      the fold, so we try down then up.
    func waitForManageDictionariesLink(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        // 1) Wait for the Settings screen itself to mount — the navigation
        //    title is the most reliable per-tab indicator and is present
        //    regardless of `SettingsViewModel.dictionaries` load state.
        _ = app.navigationBars["Settings"].waitForExistence(timeout: timeout)

        let link = manageDictionariesLink
        if link.waitForExistence(timeout: 1.0) { return true }

        // 2) Sweep up (reveal content below the fold) — most common case
        //    on first entry where the form starts at the top.
        for _ in 0..<6 {
            swipeContainerUp()
            if link.waitForExistence(timeout: 0.5) { return true }
        }

        // 3) Sweep back down — covers the scene-restoration case where the
        //    form resumed scrolled past the link.
        for _ in 0..<8 {
            swipeContainerDown()
            if link.waitForExistence(timeout: 0.5) { return true }
        }
        return false
    }

    private func swipeContainerDown() {
        if let f = form { f.swipeDown() } else { app.swipeDown() }
    }

    /// Taps "Manage Dictionaries" and returns the destination page object.
    @discardableResult
    func tapManageDictionariesLink() -> ManageDictionariesPage {
        XCTAssertTrue(
            waitForManageDictionariesLink(timeout: TestData.Timeouts.long),
            "Manage Dictionaries link should appear in Settings"
        )
        let link = manageDictionariesLink
        scrollToElement(link)
        link.tap()
        return ManageDictionariesPage(app: app)
    }
}
