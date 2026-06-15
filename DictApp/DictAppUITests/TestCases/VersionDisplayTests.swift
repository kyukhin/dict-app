import XCTest

/// UI coverage for Issue #25: the Settings → Version row now reflects
/// `AppVersion.current.displayString` instead of the hard-coded "1.0".
/// The accessibility identifier `version_value` on the `LabeledContent`
/// is the contract these tests pin.
final class VersionDisplayTests: XCTestCase {

    /// Application under test. Recreated for every test method.
    var app: XCUIApplication!
    /// Page object used to navigate to the Settings tab.
    var tabBarPage: TabBarPage!

    /// Launches the app fresh for each test and wires up the page
    /// object. Halts the suite on first failure to keep stack traces
    /// pointing at the real problem.
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    /// Releases per-test state so each method gets a clean slate.
    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// The version row must exist on Settings, be reachable via its
    /// accessibility identifier, and display a real version string —
    /// not the old "1.0" placeholder, not an empty value, and (Issue #39)
    /// never the retired `-unreleased` suffix.
    ///
    /// The test build runs from a git working copy, so the Build pre-action
    /// stamps `GIT_DESCRIBE` with a dev describe (e.g. `v1.2.0-8-gc7238e0`)
    /// and the row shows the stripped form (`1.2.0-8-gc7238e0`). The exact
    /// string is environment-dependent, so we don't pin it — we require a
    /// describe-shaped value (a numeric version, optionally a `-N-g<sha>`
    /// suffix) and the absence of `-unreleased`.
    func testVersionRowDisplaysAppVersion() throws {
        // 1. Navigate to Settings.
        tabBarPage.tapSettingsTab()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings screen should appear after tapping the Settings tab"
        )

        // 2. The version row is in the last section of the Form. Sweep up
        //    until we find it (Form is a UICollectionView, so cells off-
        //    screen aren't materialised).
        let versionRow = app.descendants(matching: .any)[
            AccessibilityIdentifiers.Settings.versionValue
        ]
        var swipes = 0
        while !versionRow.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            versionRow.waitForExistence(timeout: 2),
            "version_value row must be reachable in the Settings form"
        )

        // 3. Collect the human-readable text for the row. LabeledContent
        //    exposes its value through one of several XCUI surfaces;
        //    look at the element's own value/label *and* any descendant
        //    static texts so we don't depend on iOS version specifics.
        var visibleStrings: [String] = []
        if let label = versionRow.label as String?, !label.isEmpty {
            visibleStrings.append(label)
        }
        if let value = versionRow.value as? String, !value.isEmpty {
            visibleStrings.append(value)
        }
        let staticChildren = versionRow.descendants(matching: .staticText)
        for i in 0..<staticChildren.count {
            let text = staticChildren.element(boundBy: i).label
            if !text.isEmpty { visibleStrings.append(text) }
        }
        let combined = visibleStrings.joined(separator: " | ")

        // 4. Must NOT be the old hard-coded "1.0" placeholder. We check
        //    that no visible string is *exactly* "1.0" — substring matches
        //    against newer versions like "1.0.0" or "1.1.0" don't count.
        for piece in visibleStrings {
            XCTAssertNotEqual(
                piece.trimmingCharacters(in: .whitespaces), "1.0",
                "Version row still surfaces the old hard-coded '1.0' placeholder; got: \(combined)"
            )
        }

        // 5. The retired '-unreleased' suffix (Issue #25's buggy channel
        //    machinery, removed in #39) must never appear. The version now
        //    comes from `git describe`, so a tag build shows a bare version
        //    and a dev build shows a `-N-g<sha>` describe — never the old
        //    runtime-guessed suffix.
        XCTAssertFalse(
            combined.contains("-unreleased"),
            "Version row must not display the retired '-unreleased' suffix; got: \(combined)"
        )

        // 6. The version string must look like a `git describe` output:
        //    either a semver/describe (digit.digit at minimum, optionally
        //    with a `-N-g<sha>` dev suffix) OR a bare abbreviated SHA
        //    (the `git describe --always` fallback documented for tagless
        //    repos). Guards against an empty or "unknown" leaking through.
        let versionPattern = try NSRegularExpression(
            pattern: #"(\d+\.\d+(?:\.\d+)?(?:-\d+-g[0-9a-f]+)?|[0-9a-f]{7,})"#
        )
        let range = NSRange(combined.startIndex..., in: combined)
        XCTAssertGreaterThan(
            versionPattern.numberOfMatches(in: combined, range: range), 0,
            "Version row must contain a git-describe version or bare SHA; got: \(combined)"
        )

        // 7. Defensive: the literal fallback string 'unknown' would mean
        //    Info.plist lost CFBundleShortVersionString during the build.
        //    Should never happen with GENERATE_INFOPLIST_FILE = YES.
        XCTAssertFalse(
            combined.contains("unknown"),
            "Version row surfaced the fallback 'unknown' — Info.plist is misconfigured: \(combined)"
        )
    }
}
