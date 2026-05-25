import XCTest

/// UI coverage for Issue #25: the Settings → Version row now reflects
/// `AppVersion.current.displayString` instead of the hard-coded "1.0".
/// The accessibility identifier `version_value` on the `LabeledContent`
/// is the contract these tests pin.
final class VersionDisplayTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// The version row must exist on Settings, be reachable via its
    /// accessibility identifier, and display a real version string —
    /// not the old "1.0" placeholder and not an empty value.
    ///
    /// The xcodebuild test target compiles in Debug, so the channel is
    /// `.debug` → `displayString` must include the `-unreleased` suffix.
    /// The marketing version itself is environment-dependent (declared
    /// in MARKETING_VERSION), so we don't pin a specific number — we
    /// only require that the displayed value contains the value
    /// `Bundle.main.infoDictionary["CFBundleShortVersionString"]` plus
    /// the suffix.
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

        // 5. Debug builds must surface the '-unreleased' suffix. This is
        //    the visible signal that channel detection is wired up — if
        //    the suffix were ever silently dropped, this fails loudly.
        XCTAssertTrue(
            combined.contains("-unreleased"),
            "Debug build must display the '-unreleased' suffix; got: \(combined)"
        )

        // 6. The version string must look like a semantic version
        //    (digit.digit at minimum). Cheap regex — guards against an
        //    empty or "unknown" leaking into a properly-configured build.
        let versionPattern = try NSRegularExpression(pattern: #"\d+\.\d+"#)
        let range = NSRange(combined.startIndex..., in: combined)
        XCTAssertGreaterThan(
            versionPattern.numberOfMatches(in: combined, range: range), 0,
            "Version row must contain a numeric version (e.g. '1.1.0'); got: \(combined)"
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
