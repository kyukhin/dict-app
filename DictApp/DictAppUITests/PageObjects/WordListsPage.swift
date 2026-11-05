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
