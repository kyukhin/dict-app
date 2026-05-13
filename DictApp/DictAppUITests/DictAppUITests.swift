import XCTest

final class DictAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppLaunches() throws {
        // Basic smoke test to verify app launches successfully
        let tabBar = app.tabBars.firstMatch

        // Wait for the tab bar to appear with a longer timeout
        let tabBarExists = tabBar.waitForExistence(timeout: 10.0)
        XCTAssertTrue(tabBarExists, "Tab bar should exist after app launch")

        // Also check for any tabs by label as fallback
        if !tabBarExists {
            let searchTab = app.buttons["Search"]
            let historyTab = app.buttons["History"]
            let bookmarksTab = app.buttons["Bookmarks"]
            let manageTab = app.buttons["Manage"]

            let anyTabExists = searchTab.exists || historyTab.exists || bookmarksTab.exists || manageTab.exists
            XCTAssertTrue(anyTabExists, "At least one tab should be accessible")
        }
    }
}