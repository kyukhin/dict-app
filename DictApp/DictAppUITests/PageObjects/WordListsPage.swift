import XCTest

/// Word lists (0130, #154): the Lists screen, a list's screen and New
/// words from, pushed from the Learn home. Lists by id (`ky-ell-a1`,
/// `user-fixture-greek` from `-wordListFixture lists`), words by their term.
class WordListsPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.WordLists

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var listsScreen: XCUIElement { element(IDs.lists) }
    var listScreen: XCUIElement { element(IDs.items) }
    var newWordsFrom: XCUIElement { element(IDs.newWordsFrom) }
    var learnButton: XCUIElement { app.buttons[IDs.learnButton].firstMatch }
    var importButton: XCUIElement { app.buttons[IDs.importButton].firstMatch }
    /// New words from's footer while no list is checked.
    var noneChecked: XCUIElement { element(IDs.newWordsFromNone) }

    /// A Lists screen row.
    func row(_ id: String) -> XCUIElement { element(IDs.row(id)) }
    func count(_ id: String) -> XCUIElement { element(IDs.count(id)) }
    /// A checked list's "Learning" badge.
    func badge(_ id: String) -> XCUIElement { element(IDs.active(id)) }
    /// A row's progress bar; its label reads its numbers.
    func progress(_ id: String) -> XCUIElement { element(IDs.progress(id)) }
    /// A New words from row; selected while its list is checked.
    func newWordsFromRow(_ id: String) -> XCUIElement { app.buttons[IDs.newWordsFromRow(id)].firstMatch }

    /// The row of `term` on a list's screen; its value is the meaning.
    func word(_ term: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: IDs.item)
            .matching(NSPredicate(format: "label == %@", term)).firstMatch
    }

    // MARK: - Actions

    /// Opens list `id` from the Lists screen.
    func openList(_ id: String) {
        let row = row(id)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Lists screen shows \(id)")
        app.scrollToElement(row)
        row.tap()
        XCTAssertTrue(waitForList(), "\(id) opens its screen")
    }

    /// Taps the word `term`, scrolled to first.
    func tapWord(_ term: String) {
        let row = word(term)
        XCTAssertTrue(scrollTo(row), "the list shows \(term)")
        row.tap()
    }

    /// Scrolls the list down until `element` is on screen, in up to
    /// `maxSwipes` swipes of `velocity`. A fast swipe moves about 25 rows,
    /// so a word in the middle of a long list is not flicked past; the
    /// last word of a long list takes `bottomVelocity`, whose flicks may
    /// overshoot, since the list stops at its end.
    @discardableResult
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8,
                  velocity: XCUIGestureVelocity = .fast) -> Bool {
        let window = app.windows.firstMatch
        for _ in 0...maxSwipes {
            if element.exists, window.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                return true
            }
            app.swipeUp(velocity: velocity)
        }
        return element.exists
    }

    /// A flick that scrolls about five screens; much faster ones are too
    /// short a gesture to scroll at all.
    static let bottomVelocity = XCUIGestureVelocity(8_000)

    /// Reaches the row of `term` near the end of a long list: flicks to its
    /// last word `last`, then scrolls back up until the row is on screen. A
    /// fast swipe moves more than a screen and may pass the row; once most
    /// words on screen sort before `term`, slow swipes come back down to it.
    @discardableResult
    func scrollFromBottom(to term: String, last: String, maxSwipes: Int = 40) -> Bool {
        guard scrollTo(word(last), maxSwipes: 60, velocity: Self.bottomVelocity) else { return false }
        let element = word(term)
        let window = app.windows.firstMatch.frame
        let key = Self.sortKey(term)
        for _ in 0...maxSwipes {
            if element.exists, window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                return true
            }
            let keys = visibleTerms(in: window).map(Self.sortKey)
            if keys.filter({ $0 < key }).count * 2 > keys.count {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .fast)
            }
        }
        return element.exists
    }

    /// The terms of the word rows whose centre lies in `window`, from one
    /// snapshot of the app.
    private func visibleTerms(in window: CGRect) -> [String] {
        var terms: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if element.identifier == IDs.item, window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                terms.append(element.label)
            }
            element.children.forEach(walk)
        }
        if let snapshot = try? app.snapshot() { walk(snapshot) }
        return terms
    }

    /// A word's place in the alphabetical list, near enough to the app's
    /// `sort_key`: parenthesised parts dropped, case and accents folded.
    static func sortKey(_ term: String) -> String {
        term.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The leading navigation bar button, the back button, by index: its
    /// label is the previous screen's title.
    func goBack() {
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: TestData.Timeouts.medium), "a back button")
        back.tap()
    }

    /// Swipes the Lists screen row `id` and taps its Delete ("Delete", English UI).
    /// A row at the bottom edge is scrolled up first: a swipe over the home
    /// indicator does not reach the row (iPad, the last row of the list).
    func swipeToDelete(_ id: String) {
        let row = row(id)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Lists screen shows \(id)")
        if row.frame.maxY > app.windows.firstMatch.frame.maxY - 60 {
            app.swipeUp()
        }
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: TestData.Timeouts.medium), "the swipe shows Delete")
        delete.tap()
    }

    // MARK: - Verification

    func waitForLists(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        listsScreen.waitForExistence(timeout: timeout)
    }

    func waitForList(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        listScreen.waitForExistence(timeout: timeout)
    }

    func waitForNewWordsFrom(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        newWordsFrom.waitForExistence(timeout: timeout)
    }

    /// Waits until `element`'s `key` (`label`, `value`) equals `text`.
    func wait(for element: XCUIElement, _ key: String = "label", toBe text: String,
              timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "\(key) == %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until `element` is selected, or not.
    func wait(for element: XCUIElement, selected: Bool, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)),
                                                    object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

/// Import (0130, #155), in a sheet from the Lists screen's "+" or the Learn
/// home's "Import a list": the source choice, Paste text, the Formats help,
/// the preview and the result.
class ListImportPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.ListImport

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var fileButton: XCUIElement { app.buttons[IDs.file].firstMatch }
    var pasteRow: XCUIElement { element(IDs.paste) }
    var formatsRow: XCUIElement { element(IDs.formats) }
    var help: XCUIElement { element(IDs.help) }
    var textBox: XCUIElement { element(IDs.text) }
    /// SwiftUI's `PasteButton`, a system control.
    var pasteButton: XCUIElement { app.buttons[IDs.pasteButton].firstMatch }
    var nextButton: XCUIElement { app.buttons[IDs.next].firstMatch }
    var preview: XCUIElement { element(IDs.preview) }
    var name: XCUIElement { app.textFields[IDs.name].firstMatch }
    var language: XCUIElement { app.buttons[IDs.language].firstMatch }
    var delimiter: XCUIElement { app.buttons[IDs.delimiter].firstMatch }
    var summary: XCUIElement { app.staticTexts[IDs.summary].firstMatch }
    var errorRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: IDs.errorRow) }
    var confirmButton: XCUIElement { app.buttons[IDs.confirm].firstMatch }
    var failure: XCUIElement { element(IDs.failure) }
    var result: XCUIElement { app.staticTexts[IDs.result].firstMatch }
    var doneButton: XCUIElement { app.buttons[IDs.done].firstMatch }

    /// The sheet's source choice is up.
    func waitForSources(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        fileButton.waitForExistence(timeout: timeout)
    }

    /// "Import a file" (the `-importListFixture` file), then the preview.
    func importFile(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForSources(), "Import's source choice", file: file, line: line)
        fileButton.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: TestData.Timeouts.long), "the preview", file: file, line: line)
    }

    /// Import, then the result.
    func confirm(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(confirmButton.waitForExistence(timeout: TestData.Timeouts.medium), "Import", file: file, line: line)
        XCTAssertTrue(confirmButton.isEnabled, "Import is enabled", file: file, line: line)
        confirmButton.tap()
    }

    /// The result's Done closes the sheet.
    func done(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(doneButton.waitForExistence(timeout: TestData.Timeouts.medium), "the result's Done",
                      file: file, line: line)
        doneButton.tap()
        XCTAssertTrue(doneButton.waitForNonExistence(timeout: TestData.Timeouts.medium), "the sheet closes",
                      file: file, line: line)
    }

    /// Chooses `option` ("Spanish") in the menu picker `picker`.
    func choose(_ option: String, in picker: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(picker.waitForExistence(timeout: TestData.Timeouts.medium), "the picker", file: file, line: line)
        picker.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: TestData.Timeouts.medium), "the menu offers \(option)",
                      file: file, line: line)
        item.tap()
    }

    /// Waits until `element`'s label equals `text`.
    func wait(for element: XCUIElement, toBe text: String, timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension WordListsPage {
    /// The rows of imported lists (`word_list_row_user-…`).
    var importedRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'word_list_row_user-'"))
    }

    /// The counts of imported lists, newest first.
    var importedCounts: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'word_list_count_user-'"))
    }

    /// "+": Import's sheet.
    @discardableResult
    func openImport(file: StaticString = #filePath, line: UInt = #line) -> ListImportPage {
        XCTAssertTrue(importButton.waitForExistence(timeout: TestData.Timeouts.medium), "the + of Import",
                      file: file, line: line)
        importButton.tap()
        let page = ListImportPage(app: app)
        XCTAssertTrue(page.waitForSources(), "+ opens Import", file: file, line: line)
        return page
    }
}
