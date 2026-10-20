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
        // Basic smoke test to verify app launches successfully: the tab bar
        // (or the iPadOS 26 tab strip) shows its Search tab button.
        XCTAssertTrue(app.tabButton(.search).waitForExistence(timeout: 10.0),
                      "Tab bar should exist after app launch")
    }
}
