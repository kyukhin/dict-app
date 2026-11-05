import XCTest

/// Word lists (0130, #154): the Lists screen, a list's screen and New
/// words from, pushed from the Learn home. Lists by id (`user-fixture-greek`
/// from `-wordListFixture lists`), words by their term.
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
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the list shows \(term)")
        app.scrollToElement(row)
        row.tap()
    }

    /// The leading navigation bar button, the back button, by index: its
    /// label is the previous screen's title.
    func goBack() {
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: TestData.Timeouts.medium), "a back button")
        back.tap()
    }

    /// Swipes the Lists screen row `id` and taps its Delete ("Delete", English UI).
    func swipeToDelete(_ id: String) {
        let row = row(id)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Lists screen shows \(id)")
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
