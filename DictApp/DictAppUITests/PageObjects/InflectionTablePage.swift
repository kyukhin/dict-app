import XCTest

/// Issue #144 — the inflection table on a Greek Definition screen.
///
/// The table sits in the Definition `ScrollView` (`definition_view`), which
/// is not lazy: every cell exists, with its label, before it is scrolled
/// into view. Scroll (`reveal`) only to tap or to take a screenshot.
final class InflectionTablePage: BasePage {

    private typealias IDs = AccessibilityIdentifiers.Inflection

    /// Searches `word` and opens its row from `source` (a Greek headword
    /// source), then waits for the table, or with `expectsTable` false for
    /// the definition only.
    static func open(_ word: String, source: String, from search: SearchPage, app: XCUIApplication,
                     expectsTable: Bool = true,
                     file: StaticString = #filePath, line: UInt = #line) -> InflectionTablePage {
        search.searchFor(word)
        XCTAssertTrue(search.waitForResults(), "'\(word)' must return results", file: file, line: line)
        let row = app.collectionViews.firstMatch.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            .containing(NSPredicate(format: "label == %@", word))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.long),
                      "'\(word)' from \(source) must be listed", file: file, line: line)
        search.dismissKeyboard()
        row.tap()
        let page = InflectionTablePage(app: app)
        if expectsTable {
            XCTAssertTrue(page.table.waitForExistence(timeout: TestData.Timeouts.long),
                          "the Definition screen of '\(word)' must show a table", file: file, line: line)
        } else {
            XCTAssertTrue(app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionContent]
                .waitForExistence(timeout: TestData.Timeouts.long),
                          "the Definition screen of '\(word)' must open", file: file, line: line)
        }
        return page
    }

    var scrollView: XCUIElement { app.scrollViews[AccessibilityIdentifiers.Definition.definitionView] }

    var table: XCUIElement { app.descendants(matching: .any)[IDs.table].firstMatch }

    var allFormsButton: XCUIElement { app.buttons[IDs.allFormsButton] }

    func cell(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// How many elements carry `id`: one per cell, whichever rendering fits.
    func count(_ id: String) -> Int {
        app.descendants(matching: .any).matching(identifier: id).count
    }

    /// The id and frame of every element whose id starts with one of
    /// `prefixes`, from one snapshot of the app (fast, and it includes the
    /// cells scrolled out of view).
    func frames(withPrefixes prefixes: [String]) throws -> [(id: String, frame: CGRect)] {
        var found: [(id: String, frame: CGRect)] = []
        func walk(_ element: XCUIElementSnapshot) {
            if prefixes.contains(where: element.identifier.hasPrefix) { found.append((element.identifier, element.frame)) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        return found
    }

    /// The area a user sees: below the navigation bar, above the tab bar.
    private var visibleArea: CGRect {
        var area = app.windows.firstMatch.frame
        let nav = app.navigationBars.firstMatch
        if nav.exists { area = area.divided(atDistance: nav.frame.maxY - area.minY, from: .minYEdge).remainder }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.frame.minY > area.minY {
            area.size.height = tabBar.frame.minY - area.minY
        }
        return area
    }

    /// Swipes the Definition screen until `element` lies in the visible area.
    /// Geometry only: `isHittable` can throw on slow simulators.
    @discardableResult
    func reveal(_ element: XCUIElement, maxSwipes: Int = 15) -> Bool {
        func visible() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            return frame.height > 1 && visibleArea.contains(CGPoint(x: frame.midX, y: frame.minY))
                && visibleArea.contains(CGPoint(x: frame.midX, y: min(frame.maxY, visibleArea.maxY - 1)))
        }
        for _ in 0..<maxSwipes {
            if visible() { return true }
            let below = element.exists && element.frame.minY > visibleArea.midY
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.7 : 0.3))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.3 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return visible()
    }

    func tapAllForms(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(reveal(allFormsButton), "the All forms button must be reachable", file: file, line: line)
        allFormsButton.tap()
    }

    /// Back to Search: the leading navigation-bar button carries the previous
    /// screen's title, not "Back".
    func goBack() {
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: TestData.Timeouts.medium) { back.tap() }
        _ = app.searchFields.firstMatch.waitForExistence(timeout: TestData.Timeouts.medium)
    }
}
