import XCTest

/// Settings → Learning (0131, #162): the section's rows and the Languages
/// screen. Every row lives in the Settings `Form`, which only materialises
/// the rows near the screen, so each lookup scrolls to its row first.
class LearningSettingsPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.LearningSettings

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var languagesRow: XCUIElement { app.buttons[IDs.languages].firstMatch }
    var newPerDay: XCUIElement { app.steppers[IDs.newPerDay].firstMatch }
    var newWordsFromRow: XCUIElement { app.buttons[IDs.newWordsFrom].firstMatch }
    var goal: XCUIElement { app.steppers[IDs.goal].firstMatch }
    var order: XCUIElement { app.buttons[IDs.order].firstMatch }
    var answerMode: XCUIElement { app.buttons[IDs.answerMode].firstMatch }
    var sounds: XCUIElement { app.switches[IDs.sounds].firstMatch }
    var haptics: XCUIElement { app.switches[IDs.haptics].firstMatch }
    var reminder: XCUIElement { app.switches[IDs.reminder].firstMatch }
    var reminderTime: XCUIElement { element(IDs.reminderTime) }

    // MARK: Languages screen

    var languagesView: XCUIElement { element(IDs.languagesView) }
    var addLanguage: XCUIElement { app.buttons[IDs.addLanguage].firstMatch }
    func languageRow(_ lang: String) -> XCUIElement { element(IDs.row(lang)) }
    func via(_ lang: String) -> XCUIElement { element(IDs.via(lang)) }
    func limited(_ lang: String) -> XCUIElement { element(IDs.limited(lang)) }
    func stopButton(_ lang: String) -> XCUIElement { app.buttons[IDs.stop(lang)].firstMatch }

    // MARK: - Actions

    /// Scrolls the Settings form until `row` is on screen and clear of the
    /// bars: on iOS 26 the navigation and tab bars float over the form, so a
    /// row under one is in the window but its taps land on the bar.
    @discardableResult
    func reveal(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let nav = app.navigationBars.firstMatch
        _ = nav.waitForExistence(timeout: TestData.Timeouts.medium)
        XCTAssertTrue(app.scrollToElement(row), "\(row) reachable in Settings", file: file, line: line)
        for _ in 0..<3 where row.exists {
            let top = nav.exists ? nav.frame.maxY : 0
            let tabBar = app.tabBars.firstMatch
            let bottom = tabBar.exists && tabBar.frame.minY > top ? tabBar.frame.minY : app.windows.firstMatch.frame.maxY
            let above = row.frame.minY < top
            guard above || row.frame.maxY > bottom else { break }
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: above ? 0.3 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset:
                CGVector(dx: 0.3, dy: above ? 0.7 : 0.3)))
        }
        return row
    }

    /// A stepper's value as a number ("10").
    func value(of stepper: XCUIElement) -> Int? {
        (stepper.value as? String).flatMap(Int.init)
    }

    /// Taps a stepper's + or − until it reads `target`.
    func step(_ stepper: XCUIElement, to target: Int, file: StaticString = #filePath, line: UInt = #line) {
        reveal(stepper, file: file, line: line)
        for _ in 0..<60 {
            guard let current = value(of: stepper), current != target else { break }
            let button = stepper.buttons.element(boundBy: current > target ? 0 : 1)
            button.tap()
        }
        XCTAssertEqual(value(of: stepper), target, "\(stepper.identifier) reads \(target)", file: file, line: line)
    }

    /// Chooses `option` ("Strict accents") in a menu picker row.
    func choose(_ option: String, in picker: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(picker, file: file, line: line)
        picker.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: TestData.Timeouts.medium), "menu item \(option)", file: file, line: line)
        item.tap()
        XCTAssertTrue(waitForLabel(of: picker, containing: option), "\(picker.identifier) shows \(option)",
                      file: file, line: line)
    }

    /// Opens Settings → Learning → Languages.
    @discardableResult
    func openLanguages(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        reveal(languagesRow, file: file, line: line).tap()
        return languagesView.waitForExistence(timeout: TestData.Timeouts.medium)
    }

    /// Changes `lang`'s via in its menu to the item `item` ("via Spanish").
    func chooseVia(_ item: String, for lang: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = via(lang)
        XCTAssertTrue(menu.waitForExistence(timeout: TestData.Timeouts.medium), "\(lang)'s via menu", file: file, line: line)
        menu.tap()
        let option = app.buttons[item].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: TestData.Timeouts.medium), "menu item \(item)", file: file, line: line)
        option.tap()
        XCTAssertTrue(waitForLabel(of: via(lang), containing: item), "\(lang) is now \(item)", file: file, line: line)
    }

    /// Stop learning `lang`, confirmed in the alert "Stop learning %@?".
    func stopLearning(_ lang: String, expectingTitle title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = stopButton(lang)
        XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.medium), "Stop learning \(lang)", file: file, line: line)
        button.tap()
        let alert = app.alerts[title].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert \(title)", file: file, line: line)
        XCTAssertTrue(alert.staticTexts["Your progress is kept."].exists, "its message", file: file, line: line)
        alert.buttons["Stop learning"].tap()
        XCTAssertTrue(languageRow(lang).waitForNonExistence(timeout: TestData.Timeouts.medium), "\(lang) is gone",
                      file: file, line: line)
    }

    /// Pops one screen: the leading nav-bar button, by index (its label is
    /// the previous screen's title).
    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    /// Waits until `element`'s label contains `text`.
    func waitForLabel(of element: XCUIElement, containing text: String,
                      timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                              timeout: timeout) == .completed
    }
}
