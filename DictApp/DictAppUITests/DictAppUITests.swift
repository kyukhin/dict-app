import XCTest

final class DictAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
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
            let settingsTab = app.buttons["Settings"]

            let anyTabExists = searchTab.exists || historyTab.exists || bookmarksTab.exists || settingsTab.exists
            XCTAssertTrue(anyTabExists, "At least one tab should be accessible")
        }
    }
}
