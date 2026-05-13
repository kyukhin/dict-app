import XCTest

class BasePage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    func waitForElement(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.otherElements[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Element with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForButton(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Button with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForTextField(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.textFields[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "TextField with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForSearchField(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.searchFields.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "SearchField not found within \(timeout) seconds")
        return element
    }

    func waitForTable(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.tables[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Table with identifier '\(identifier)' not found within \(timeout) seconds")
        return element
    }

    func waitForTabBar(timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.tabBars.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "TabBar not found within \(timeout) seconds")
        return element
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard self.exists else {
            XCTFail("Element does not exist")
            return
        }

        self.tap()
        self.doubleTap()
        self.typeText(text)
    }
}