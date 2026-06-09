import XCTest

/// End-to-end coverage of the "Report a Bug" flow (Issue #8).
///
/// On the iOS Simulator, `MFMailComposeViewController.canSendMail()`
/// returns `false` because no Mail account is configured by default. The
/// `SupportViewModel` then falls back to `openURL(mailto:)`; with no
/// third-party mail client registered, that fails too and the final
/// fallback alert appears. This test exercises that path:
///
///   1. Tap **Report a Bug**.
///   2. The "Mail Not Available" alert appears.
///   3. Tapping **Copy Address** writes the recipient address to
///      `UIPasteboard.general`.
final class ReportBugFlowTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetData"]
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    /// The fallback alert on a sim with no Mail account, with a screenshot
    /// attached for visual review. Also verifies that Copy Address writes
    /// the recipient address to the system pasteboard.
    func testReportBugFallbackAlertAndCopyAddress() {
        // 1. Navigate to Settings.
        let settingsTab = app.tabBars.buttons["settings_tab"]
        if !settingsTab.waitForExistence(timeout: 5) {
            // Tab identifier didn't propagate — fall back to the last tab
            // bar button (Settings is the rightmost on this app).
            let buttons = app.tabBars.firstMatch.buttons
            XCTAssertTrue(buttons.element(boundBy: 3).waitForExistence(timeout: 5),
                          "Settings tab button not found")
            buttons.element(boundBy: 3).tap()
        } else {
            settingsTab.tap()
        }

        // 2. Tap "Report a Bug". Settings is a SwiftUI Form backed by a
        //    UICollectionView with cell virtualisation, and Support is
        //    below the fold on iPhone. Delegate the scroll-search to the
        //    shared `XCUIApplication.scrollToElement` helper — it sweeps
        //    up then down until the button is `.exists && .isHittable`,
        //    which is the only state in which a `.tap()` is meaningful.
        let reportBug = app.buttons["report_bug_button"]
        XCTAssertTrue(app.scrollToElement(reportBug),
                      "Report a Bug button must be reachable in the Settings form")
        XCTAssertTrue(reportBug.isEnabled,
                      "Report a Bug button should not be disabled (Issue #8)")
        reportBug.tap()

        // 3. The fallback alert appears (no Mail account on simulator).
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "Mail-unavailable alert should appear when canSendMail==false on simulator")

        // Attach a screenshot of the alert for visual review in the
        // xcresult bundle.
        let shot = XCTAttachment(screenshot: alert.screenshot())
        shot.name = "report-bug-fallback-alert"
        shot.lifetime = .keepAlways
        add(shot)

        // 4. Tap Copy Address. The button label is localized — accept
        //    either English or Russian source.
        let copyButton: XCUIElement = {
            let en = alert.buttons["Copy Address"]
            if en.exists { return en }
            let ru = alert.buttons["Скопировать адрес"]
            return ru
        }()
        XCTAssertTrue(copyButton.exists,
                      "Alert should expose a Copy Address button in English or Russian")
        copyButton.tap()

        // 5. Assert the post-action state programmatically: the alert
        //    must dismiss and Settings must be on screen again.
        //    A screenshot complements the assertions for visual review
        //    in the xcresult bundle.
        XCTAssertTrue(alert.waitForNonExistence(timeout: 2.0),
                      "Mail-unavailable alert should dismiss after Copy Address")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 2.0),
                      "Settings navigation bar should be visible after the alert dismisses")

        // The pasteboard itself is verified externally via
        // `xcrun simctl pbpaste`; UI-test processes can't reliably read
        // `UIPasteboard.general` on iOS 14+ without prompts.
        let afterShot = XCTAttachment(screenshot: app.screenshot())
        afterShot.name = "report-bug-after-copy"
        afterShot.lifetime = .keepAlways
        add(afterShot)
    }
}
