import XCTest

class SettingsPage: BasePage {

    // MARK: - UI Elements

    private func toggle(for source: String) -> XCUIElement {
        app.switches[AccessibilityIdentifiers.Settings.dictionaryToggle(source: source)]
    }

    // MARK: - Dictionary Order navigation (Issue #6)
    //
    // The enable/disable toggles moved from the Settings root onto the pushed
    // `DictionaryOrderView` (§1b). `tapToggle` / `waitForToggle` auto-navigate
    // there so existing callers keep working with no change.

    private var dictionaryOrderLink: XCUIElement {
        let id = AccessibilityIdentifiers.Settings.dictionaryOrderLink
        if app.buttons[id].firstMatch.exists { return app.buttons[id].firstMatch }
        if app.cells[id].firstMatch.exists { return app.cells[id].firstMatch }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // A SwiftUI row's `.accessibilityIdentifier` surfaces on both the row cell
    // and inner views, so an unqualified `[id]` lookup matches multiple elements
    // and raises on `.frame`/`.tap`. `.firstMatch` (the outermost / row
    // container) disambiguates and is stable for frame-ordering and dragging.
    private func orderRow(_ source: String) -> XCUIElement {
        let id = AccessibilityIdentifiers.Settings.dictionaryOrderRow(source: source)
        // The row id lives on the leading label (kept off the HStack so it can't
        // shadow the row's switch — that breaks `dictionary_toggle_*`). The
        // enclosing CELL is the reliable frame anchor and drag target; a bare
        // staticText is a poor press-drag handle for reorder.
        let cell = app.cells.containing(.staticText, identifier: id).firstMatch
        if cell.exists { return cell }
        if app.cells[id].firstMatch.exists { return app.cells[id].firstMatch }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Pushes the DictionaryOrderView from the Dictionaries section. Idempotent:
    /// no-op if a dictionary-order row is already on screen.
    @discardableResult
    func openDictionaryOrder() -> Bool {
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: TestData.Timeouts.medium)
        // Already on the order screen? `dictionary_order_view` is the screen-level
        // AX id added in #6 review — wait-then-return makes subsequent interactions
        // race-free on the slow Intel sim.
        let orderView = app.descendants(matching: .any)["dictionary_order_view"]
        if orderView.exists { return true }
        guard app.scrollToElement(dictionaryOrderLink) else { return false }
        dictionaryOrderLink.tap()
        return orderView.waitForExistence(timeout: TestData.Timeouts.medium)
    }

    /// Ensures we're on the DictionaryOrderView (where the toggles + order rows
    /// live). If no toggle is materialized, push the order screen.
    private func ensureOnOrderScreen(for source: String) {
        if !toggle(for: source).exists && !orderRow(source).exists {
            _ = openDictionaryOrder()
        }
    }

    /// Moves the first dictionary to the end via drag-to-reorder, returning the
    /// resulting on-screen order. Cycles through several press points/durations
    /// because XCUITest reorder is gesture-flaky and the reliable grip offset
    /// differs across arches (the trailing grip works on arm64/iOS 26; a longer
    /// centre press works on the Intel/iOS-18 sim) — we drag, poll for the order
    /// to change, and try the next strategy if it didn't. Returns the (possibly
    /// unchanged) order so the caller can assert.
    @discardableResult
    func reorderFirstToLast(sources: [String]) -> [String] {
        let before = currentOrder(of: sources)
        guard before.count >= 2 else { return before }
        // (dx, press-duration) pairs, ordered most-likely-first per arch.
        let strategies: [(CGFloat, TimeInterval)] = [
            (0.97, 1.0), (0.5, 1.2), (0.85, 1.0), (0.5, 1.6), (0.92, 1.3)
        ]
        let changed = NSPredicate { [weak self] _, _ in
            self.map { $0.currentOrder(of: sources) != before } ?? false
        }
        for (dx, duration) in strategies {
            let src = orderRow(before[0])
            let dst = orderRow(before[before.count - 1])
            guard src.waitForExistence(timeout: TestData.Timeouts.medium),
                  dst.waitForExistence(timeout: TestData.Timeouts.medium) else { continue }
            src.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
                .press(forDuration: duration,
                       thenDragTo: dst.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)))
            let exp = XCTNSPredicateExpectation(predicate: changed, object: nil)
            if XCTWaiter.wait(for: [exp], timeout: 8) == .completed { break }
        }
        return currentOrder(of: sources)
    }

    /// The on-screen order of the given sources, top-to-bottom by row frame.
    func currentOrder(of sources: [String]) -> [String] {
        sources
            .map { ($0, orderRow($0)) }
            .filter { $0.1.exists }
            .sorted { $0.1.frame.minY < $1.1.frame.minY }
            .map { $0.0 }
    }

    // MARK: - Actions

    /// Taps the toggle for the given source and verifies its state flipped.
    /// Each test launches with `-resetData`, which resets all toggles to ON.
    /// If the first tap doesn't change the accessibility value (some SwiftUI
    /// Toggle hit-targets in iOS 26 don't toggle on label-area taps), we
    /// retry on the right-edge coordinate where the switch handle lives.
    func tapToggle(source: String) {
        ensureOnOrderScreen(for: source)
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
        ensureOnOrderScreen(for: source)
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
