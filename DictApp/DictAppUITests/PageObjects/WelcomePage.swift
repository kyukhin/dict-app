import XCTest

/// Issue #245 — the first-launch sheet (0237, "First launch"). Every element
/// is found by id (`AccessibilityIdentifiers.Welcome`); after Download the
/// rows are `PackRow`s with the `Languages` ids.
final class WelcomePage: BasePage {

    private typealias IDs = AccessibilityIdentifiers.Welcome

    var sheet: XCUIElement { element(IDs.sheet) }
    var downloadButton: XCUIElement { button(IDs.download) }
    var notNowButton: XCUIElement { button(IDs.notNow) }
    var doneButton: XCUIElement { button(IDs.done) }
    var importLink: XCUIElement { button(IDs.importLink) }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func button(_ id: String) -> XCUIElement {
        app.buttons[id].firstMatch
    }

    /// A language row before Download.
    func language(_ id: String) -> XCUIElement {
        button(IDs.language(id))
    }

    /// Checked rows carry the selected trait.
    func isChecked(_ id: String) -> Bool {
        language(id).isSelected
    }

    @discardableResult
    func waitForSheet(timeout: TimeInterval = TestData.Timeouts.launch) -> Bool {
        sheet.waitForExistence(timeout: timeout)
    }

    /// The sheet has closed.
    func waitForSheetGone(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: sheet)],
                              timeout: timeout) == .completed
    }

    /// Checks or unchecks a language and waits for the row to show it.
    func toggle(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = language(id)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the row of \(id) must exist",
                      file: file, line: line)
        XCTAssertTrue(app.scrollToElement(row, in: sheet), "the row of \(id) must be reachable", file: file, line: line)
        let before = row.isSelected
        row.tap()
        let flipped = NSPredicate(format: "isSelected == %@", NSNumber(value: !before))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: flipped, object: row)],
                                      timeout: TestData.Timeouts.medium), .completed,
                       "the row of \(id) toggles", file: file, line: line)
    }

    func tapDownload(file: StaticString = #filePath, line: UInt = #line) {
        tap(downloadButton, "Download", file: file, line: line)
    }

    func tapNotNow(file: StaticString = #filePath, line: UInt = #line) {
        tap(notNowButton, "Not now", file: file, line: line)
    }

    func tapDone(file: StaticString = #filePath, line: UInt = #line) {
        tap(doneButton, "Done", file: file, line: line)
    }

    /// The pack row is installed ("Installed · …") after Download.
    func waitForInstalled(_ id: String, timeout: TimeInterval = 60) -> Bool {
        element(AccessibilityIdentifiers.Languages.installed(id)).waitForExistence(timeout: timeout)
    }

    private func tap(_ element: XCUIElement, _ what: String, file: StaticString, line: UInt) {
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), "\(what) must exist",
                      file: file, line: line)
        element.tap()
    }
}
