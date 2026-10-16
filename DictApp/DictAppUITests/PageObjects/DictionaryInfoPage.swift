import XCTest

/// Issue #91 — the pushed dictionary info detail (`DictionaryDetailView`):
/// one section per underlying source, keyed by source ID.
class DictionaryInfoPage: BasePage {

    var view: XCUIElement {
        app.descendants(matching: .any)[AccessibilityIdentifiers.DictionaryInfo.view].firstMatch
    }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    func waitForView(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        view.waitForExistence(timeout: timeout)
    }

    /// Swipe-first scroll on the info list until `id` exists with an on-screen,
    /// non-degenerate frame. License bodies are long and the lazy `List` does
    /// not materialise off-screen sections, so never bound by `cells.count`.
    @discardableResult
    func revealElement(_ id: String) -> Bool {
        app.scrollToElement(element(id), in: view)
    }

    /// Back to the order screen. Taps the leading nav-bar button by index: its
    /// label is the previous screen's localised title, not "Back".
    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }
}
