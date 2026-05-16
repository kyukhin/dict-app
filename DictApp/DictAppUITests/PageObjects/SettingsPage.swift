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
}

