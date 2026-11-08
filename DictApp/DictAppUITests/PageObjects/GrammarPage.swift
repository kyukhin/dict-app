import XCTest

/// 0133, #172: the Learn home's Grammar row, the Grammar screen and a
/// grammar topic. The topic is a `ScrollView` (not lazy): every block
/// exists before it is scrolled into view; scroll only to tap.
final class GrammarPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Grammar

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var learnRow: XCUIElement { element(IDs.learnRow) }
    /// The row's value, "17 topics".
    var learnRowValue: String? { learnRow.value as? String }
    var topicList: XCUIElement { element(IDs.topics) }
    var englishNote: XCUIElement { element(IDs.englishNote) }
    var topicView: XCUIElement { element(IDs.topic) }
    var title: XCUIElement { element(IDs.title) }
    var level: XCUIElement { element(IDs.level) }
    var rule: XCUIElement { element(IDs.rule) }
    var examples: XCUIElement { element(IDs.examples) }
    var watchOut: XCUIElement { element(IDs.watchOut) }
    var practiseButton: XCUIElement { app.buttons[IDs.practiseButton].firstMatch }

    func levelHeader(_ level: String) -> XCUIElement { element(IDs.level(level)) }
    func topicRow(_ id: String) -> XCUIElement { element(IDs.topicRow(id)) }
    func table(_ n: Int) -> XCUIElement { element(IDs.table(n)) }
    func cell(_ table: Int, _ row: Int, _ column: Int) -> XCUIElement { element(IDs.cell(table, row, column)) }
    func example(_ n: Int) -> XCUIElement { element(IDs.example(n)) }
    func word(_ word: String) -> XCUIElement { element(IDs.word(word)) }
    func related(_ id: String) -> XCUIElement { element(IDs.related(id)) }

    /// How many elements carry an id starting with `prefix`, from one snapshot.
    func count(withPrefix prefix: String) throws -> Int {
        var found = Set<String>()
        func walk(_ element: XCUIElementSnapshot) {
            if element.identifier.hasPrefix(prefix) { found.insert(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        return found.count
    }

    /// The Learn home's Grammar row (below the Lists section), then the
    /// Grammar screen.
    @discardableResult
    func openGrammar(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.scrollToElement(learnRow), "the Learn home's Grammar row", file: file, line: line)
        learnRow.tap()
        return topicList.waitForExistence(timeout: TestData.Timeouts.medium)
    }

    /// From the Grammar screen: the row of topic `id`, then its screen.
    @discardableResult
    func openTopic(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let row = topicRow(id)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium) || app.scrollToElement(row),
                      "the row of \(id)", file: file, line: line)
        XCTAssertTrue(app.scrollToElement(row), "the row of \(id) on screen", file: file, line: line)
        row.tap()
        return waitForTopic()
    }

    func waitForTopic(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        title.waitForExistence(timeout: timeout)
    }

    /// Scrolls the topic until `element` is on screen, then taps it.
    func tapOnTopic(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), name, file: file, line: line)
        XCTAssertTrue(app.scrollToElement(element, in: app.scrollViews[IDs.topic].firstMatch),
                      "\(name) on screen", file: file, line: line)
        element.tap()
    }

    /// The back button, by index (it carries the previous screen's title).
    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }
}
