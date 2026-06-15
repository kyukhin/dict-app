import XCTest

/// UI coverage for the dictionary-import entry point.
///
/// The actual file parsing is still a stub (see `ManageDictionariesViewModel.
/// handleImport`), so these tests deliberately stop at presenting the system
/// file picker — they verify the user can *reach* the import affordance and
/// that it is interactive. Driving `UIDocumentPickerViewController` itself is
/// out of scope because its UI varies across iOS versions and is unreliable
/// in CI.
///
/// Modeled on `BookmarkFlowTests` and `DictionaryFilterTests` (the reliable
/// UI suites in this project). Each test launches with `-resetData` to start
/// from a clean state.
final class ImportDictionaryTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")

        // Same Dictation-alert handler as the other Settings suites — iOS 26
        // shows a springboard alert when the user first activates
        // `.searchable()`. Install our own dismissal monitor so it doesn't
        // block the test.
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

        // Force portrait — sim orientation persists across sessions on Intel x86_64,
        // and landscape no-ops swipeUp against SwiftUI Form/List scroll views.
        // See project memory project_xcuitest_orientation_landscape_swipe.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// Settings -> Manage Dictionaries must be reachable and land on a screen
    /// titled "Manage Dictionaries". Without this path users cannot get to
    /// the import flow at all.
    func testManageDictionariesScreenIsReachableFromSettings() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(
            settings.waitForManageDictionariesLink(timeout: TestData.Timeouts.long),
            "The 'Manage Dictionaries' navigation row must appear under Settings -> Dictionaries"
        )

        let manage = settings.tapManageDictionariesLink()
        XCTAssertTrue(
            manage.verifyNavigationTitleVisible(),
            "Tapping the link must push onto a screen titled 'Manage Dictionaries'"
        )
    }

    /// Once on the Manage Dictionaries screen, the import button must be
    /// present, enabled, and hittable. We assert each condition individually
    /// so a failure points at the specific defect rather than a single
    /// composite boolean.
    func testImportDictionaryButtonIsAvailableAndInteractive() throws {
        let manage = tabBarPage.tapSettingsTab().tapManageDictionariesLink()
        XCTAssertTrue(
            manage.waitForImportButton(timeout: TestData.Timeouts.long),
            "Import button must appear after navigating to Manage Dictionaries"
        )
        _ = manage.verifyImportButtonInteractive()
    }

    /// Tapping the import button must present the system file picker. We
    /// verify *something* outside the app's normal hierarchy appears (either
    /// a sheet, a system alert, or `Files`/`Browse` chrome from
    /// `UIDocumentPickerViewController`). We deliberately do not assert on
    /// the picker's exact contents — that surface changes between iOS
    /// versions and would make this test flaky for no real coverage gain.
    func testTappingImportButtonPresentsSystemUI() throws {
        let manage = tabBarPage.tapSettingsTab().tapManageDictionariesLink()
        XCTAssertTrue(
            manage.waitForImportButton(timeout: TestData.Timeouts.long),
            "Import button must exist before we tap it"
        )

        manage.tapImportButton()

        // The document picker runs in a separate process; XCUITest exposes
        // it as a sheet/alert or as buttons with well-known labels. Wait for
        // any of the common chrome elements to appear within a reasonable
        // window before declaring failure.
        let pickerHints: [XCUIElement] = [
            app.sheets.firstMatch,
            app.otherElements["DocumentPickerSheetView"],
            app.navigationBars["Browse"],
            app.buttons["Cancel"]
        ]
        let appeared = pickerHints.contains { $0.waitForExistence(timeout: TestData.Timeouts.long) }
        XCTAssertTrue(
            appeared,
            "Tapping import must surface some system UI (sheet, document picker, or Cancel button)"
        )
    }

    // MARK: - End-to-end: import + search
    //
    // These two tests exercise the full user flow:
    //   1. Launch the app.
    //   2. Open Settings → Manage Dictionaries.
    //   3. Tap Import — under the `-importFixtureViaCallback:<type>` launch
    //      argument the button short-circuits the system file picker and
    //      feeds the bundled fixture URL straight into `handleImport`. This
    //      simulates the user picking the file without depending on
    //      `UIDocumentPickerViewController` chrome (which is iOS-version
    //      sensitive and unreliable in CI). The real import logic and the
    //      database write path are exercised end-to-end.
    //   4. Switch to Search, search for a unique word from the fixture, and
    //      assert it appears in the results.
    //
    // Each test additionally launches with `-clearFixtureImports` so any
    // entries left over from a prior fixture import are scrubbed first;
    // otherwise the pre-import "no results" check would be meaningless.

    /// JSON path: import `test_import_fixture.json` and assert that the
    /// fixture-only word "qaflux" becomes searchable.
    func testImportingJSONFileMakesUniqueWordSearchable() throws {
        try runImportThenSearch(
            fixtureExtension: "json",
            uniqueWord: "qaflux"
        )
    }

    /// SQLite path: import `test_import_fixture.sqlite` and assert that the
    /// fixture-only word "zarboom" becomes searchable.
    func testImportingSQLiteFileMakesUniqueWordSearchable() throws {
        try runImportThenSearch(
            fixtureExtension: "sqlite",
            uniqueWord: "zarboom"
        )
    }

    // MARK: - Shared flow

    /// Both end-to-end tests follow the same shape; only the fixture
    /// extension and the expected unique word differ. Extracted to keep
    /// each test method short and intent-focused.
    private func runImportThenSearch(fixtureExtension: String, uniqueWord: String) throws {
        // Relaunch the app with the launch args this test needs:
        //   -clearFixtureImports        scrub any prior fixture entries
        //   -importFixtureViaCallback:X make the Import button fire handleImport
        //                                with the bundled fixture URL.
        // `setUpWithError` only added -resetData.
        app.terminate()
        app.launchArguments.append("-clearFixtureImports")
        app.launchArguments.append("-importFixtureViaCallback:\(fixtureExtension)")
        app.launch()
        tabBarPage = TabBarPage(app: app)

        // 1) Pre-condition: the unique word must NOT be in the DB. Otherwise
        //    a green test wouldn't prove the import worked. We wait for the
        //    empty-state view (`search_no_results`) — counting cells is
        //    unreliable because empty-state cells register as 1 in some
        //    iOS versions.
        let preSearch = tabBarPage.tapSearchTab()
        preSearch.searchFor(uniqueWord)
        let emptyState = app.descendants(matching: .any)["search_no_results"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: TestData.Timeouts.medium),
            "Pre-condition: searching for '\(uniqueWord)' before import must show the empty-state view"
        )
        preSearch.clearOverlaysBeforeTabSwitch()

        // 2) Navigate to Settings → Manage Dictionaries.
        let settings = tabBarPage.tapSettingsTab()
        let manage = settings.tapManageDictionariesLink()
        XCTAssertTrue(
            manage.waitForImportButton(timeout: TestData.Timeouts.long),
            "Import button must be present on Manage Dictionaries"
        )

        // 3) Tap Import. Under the launch arg this fires handleImport with
        //    the bundled fixture and skips the system file picker.
        manage.tapImportButton()

        // 4) Wait for the import-result message. A successful import for
        //    the fixture must report a positive entry count.
        let message = manage.waitForImportSuccessMessage(timeout: 20.0)
        XCTAssertNotNil(message, "Import-result message must appear after tapping Import")
        XCTAssertTrue(
            message?.contains("Imported") ?? false,
            "Result message should start with 'Imported …', got: \(message ?? "nil")"
        )

        // 5) Navigate to Search and verify the unique word is found.
        let search = tabBarPage.tapSearchTab()
        search.searchFor(uniqueWord)
        XCTAssertTrue(
            search.waitForResults(timeout: TestData.Timeouts.long),
            "Search for unique fixture word '\(uniqueWord)' must return results after import"
        )
        XCTAssertGreaterThan(
            search.getResultsCount(), 0,
            "Imported entries must be searchable after the import completes"
        )
    }
}
