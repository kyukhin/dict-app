import XCTest

/// Issue #243 — Settings → Dictionaries → Languages (0237, "Settings →
/// Dictionaries"). Rows are found by id (`AccessibilityIdentifiers.Languages`);
/// the List is lazy, so every element is scrolled to by geometry before a tap.
final class LanguagesPage: BasePage {

    private typealias IDs = AccessibilityIdentifiers.Languages

    var screen: XCUIElement { element(IDs.screen) }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func button(_ id: String) -> XCUIElement {
        app.buttons[id].firstMatch
    }

    /// The row's cell (its name is a static text with the row id): the
    /// swipe target.
    func cell(_ id: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: IDs.row(id)).firstMatch
    }

    /// From the Settings root: pushes the Languages screen. No-op when it is
    /// already showing.
    @discardableResult
    func open() -> Bool {
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: TestData.Timeouts.medium)
        if screen.exists { return true }
        let link = element(IDs.link)
        guard app.scrollToElement(link) else { return false }
        link.tap()
        return screen.waitForExistence(timeout: TestData.Timeouts.medium)
    }

    /// Taps the row's Download, after scrolling it into view.
    func tapDownload(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(IDs.download(id)), "Download of \(id)", file: file, line: line)
    }

    func tapCancel(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(IDs.cancel(id)), "Cancel of \(id)", file: file, line: line)
    }

    /// The row shows "Installed · …".
    func waitForInstalled(_ id: String, timeout: TimeInterval = 60) -> Bool {
        element(IDs.installed(id)).waitForExistence(timeout: timeout)
    }

    /// Swipes the row and taps its Remove, then returns the alert, which
    /// asks first.
    func swipeToRemove(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = cell(id)
        XCTAssertTrue(app.scrollToElement(row), "the row of \(id) must be reachable", file: file, line: line)
        row.swipeLeft()
        let remove = button(IDs.remove(id))
        XCTAssertTrue(remove.waitForExistence(timeout: TestData.Timeouts.medium),
                      "the swipe shows Remove for \(id)", file: file, line: line)
        remove.tap()
        return app.alerts.firstMatch
    }

    /// Pops one screen: the leading nav-bar button, labelled with the
    /// previous screen's title.
    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    private func tap(_ element: XCUIElement, _ what: String, file: StaticString, line: UInt) {
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), "\(what) must exist",
                      file: file, line: line)
        XCTAssertTrue(app.scrollToElement(element), "\(what) must be reachable", file: file, line: line)
        element.tap()
    }
}
