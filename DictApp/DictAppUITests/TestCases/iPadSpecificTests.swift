import XCTest

/// iPad-only UI tests.
///
/// Scope is intentionally narrow: the app has no iPad-specific layout
/// (no `NavigationSplitView`, no sidebar, no two-column adaptive layout),
/// so its `TabView`-based UI behaves identically on both idioms — except
/// that on iPadOS 18+ SwiftUI renders the tab bar as a *top pill* instead
/// of a bottom `UITabBar`. That alone means the standard `TabBarPage`
/// (which looks under `app.tabBars`) does not work on iPad; this file
/// does its tab lookups directly through accessibility identifiers, which
/// SwiftUI exposes on the TabView children regardless of the rendered
/// chrome.
///
/// This file keeps only the two cases that have value beyond re-running an
/// iPhone suite on a different device:
///
///   1) Launch regression for Issue #4 (`TARGETED_DEVICE_FAMILY = 1` once
///      produced a blank "Designed for iPhone" letterbox screen on iPad).
///   2) Orientation handling — the one piece of iPad-only behavior the
///      otherwise-shared UI must survive.
///
/// All tests skip cleanly on non-iPad destinations.
final class iPadSpecificTests: XCTestCase {

    var app: XCUIApplication!

    /// Tab labels as rendered in the SwiftUI `TabView`. The accessibility
    /// *identifier* set on the TabView children in ContentView attaches to
    /// the content view, not to the tab control rendered by the OS — on the
    /// iPad pill in iOS 26 the only stable handle is the displayed label.
    private let allTabLabels = ["Search", "History", "Bookmarks", "Settings"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Skip *before* doing setup work — saves the launch cost on iPhone
        // destinations where every test would XCTSkip anyway.
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "iPad-only tests; current destination is not iPad")

        app = XCUIApplication()
        app.launchArguments.append("-resetData")

        // iOS 26 surfaces an "Enable Dictation?" springboard alert the first
        // time `.searchable()` is activated. XCUI's default handler taps the
        // wrong button and the resulting privacy sheet covers the tab area,
        // breaking every subsequent step. Install our own dismissal handler.
        addUIInterruptionMonitor(withDescription: "Enable Dictation alert") { alert in
            for label in ["Not Now", "Cancel", "Don't Enable", "Don't Allow", "Enable Dictation"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
    }

    override func tearDownWithError() throws {
        // Restore portrait so a rotated test doesn't leak orientation into
        // whichever test the runner picks next.
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: - Helpers

    /// Locates a tab control by its visible label. On iPad iOS 26 SwiftUI
    /// renders the TabView as a top pill rather than a `UITabBar`, so
    /// `app.tabBars` is empty — but the labels are exposed as buttons in
    /// the app element tree.
    ///
    /// `.firstMatch` because some labels (notably "Search") collide with
    /// other affordances in the toolbar — the tab is rendered first in the
    /// hierarchy so the first match is the right one.
    private func tab(_ label: String) -> XCUIElement {
        app.buttons[label].firstMatch
    }

    /// Taps a tab via coordinate, the same technique TabBarPage uses on
    /// iPhone (XCUI's `.tap()` invokes `scrollToVisible` which can fail on
    /// iOS 26 SwiftUI layouts).
    private func tapTab(_ label: String) {
        let element = tab(label)
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Tab '\(label)' must exist before being tapped")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// True iff every tab label is exposed as a button somewhere in the
    /// app's element tree.
    private func allTabsPresent() -> Bool {
        allTabLabels.allSatisfy { tab($0).exists }
    }

    // MARK: - Tests

    /// Regression for Issue #4: the app once shipped with
    /// `TARGETED_DEVICE_FAMILY = 1` (iPhone only) which caused UIKit to
    /// launch the app in "Designed for iPhone" letterbox mode on iPad and
    /// never attach a window for the iPad idiom — the user saw a blank
    /// white screen. This test fails loudly if that regresses: a native
    /// iPad launch must surface all four tab controls, and tapping Search
    /// must reveal a usable search field.
    func testAppLaunchesOnIPad() throws {
        XCTAssertTrue(
            tab("Search")
                .waitForExistence(timeout: TestData.Timeouts.long),
            "Search tab must be reachable on iPad launch (regression guard for Issue #4)"
        )
        XCTAssertTrue(allTabsPresent(),
                      "All four tab controls must exist on iPad")

        tapTab("Search")
        // On iPadOS 26 the `.searchable()` field collapses into a top-right
        // magnifying-glass icon that only expands when tapped — so we can't
        // rely on `app.searchFields` being on screen at rest. Instead we
        // assert the Search tab's NavigationStack title ("Dictionary")
        // appears, which is the unambiguous "Search view is rendered"
        // signal.
        XCTAssertTrue(
            app.staticTexts["Dictionary"].waitForExistence(timeout: TestData.Timeouts.medium),
            "SearchView's 'Dictionary' title must render on the Search tab on iPad"
        )
    }

    /// The TabView layout must survive orientation changes — every tab
    /// control stays reachable and the Search tab still pushes its content
    /// view after each rotation. This is the one piece of iPad-only
    /// behavior the otherwise-shared SwiftUI views must handle.
    ///
    /// We cycle portrait → landscapeLeft → portrait → landscapeRight and
    /// assert at each step that all four tabs are present and tapping
    /// Search produces SearchView's "Dictionary" navigation title.
    func testIPadStaysUsableAcrossOrientationChanges() throws {
        let device = XCUIDevice.shared

        device.orientation = .portrait
        XCTAssertTrue(
            tab("Search")
                .waitForExistence(timeout: TestData.Timeouts.long),
            "Tabs must render in portrait before we start rotating"
        )

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            device.orientation = orientation
            // Give SwiftUI a beat to settle the new layout before probing.
            _ = tab("Search")
                .waitForExistence(timeout: TestData.Timeouts.medium)

            XCTAssertTrue(
                allTabsPresent(),
                "All four tabs must remain reachable after rotating to \(orientation.rawValue)"
            )

            tapTab("Search")
            XCTAssertTrue(
                app.staticTexts["Dictionary"].waitForExistence(timeout: TestData.Timeouts.medium),
                "SearchView title must render after rotating to \(orientation.rawValue)"
            )
        }
    }
}
