import XCTest

/// Issue #105 — a dictionary imported on Manage Dictionaries shows up on
/// Dictionary Order without a relaunch, ON, appended at the end, even when
/// the user had switched another pair OFF before the import.
///
/// The flow follows DESIGN_DOC.md §7b (AC3). Launch / interruption /
/// orientation setup mirrors `DictionaryInfoTests`. AC2 (removal) has no UI:
/// it is covered at data level by
/// `SettingsViewModelPairTests.testReloadAfterRemovalDropsRowLikeRelaunch`.
final class DictionaryOrderRefreshTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-clearFixtureImports` scrubs any leftover fixture rows at launch;
        // `-importFixtureViaCallback:json` makes the Import button feed the
        // bundled fixture to `handleImport` without the document picker.
        app.launchArguments += ["-disableReviewPrompt", "-resetData",
                                "-clearFixtureImports", "-importFixtureViaCallback:json"]
        // Same os_log quarantine crash as `DictionaryInfoTests` (long texts).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

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

        // Cleanup, not a workaround: later suites assume the five bundled
        // pairs only and all of them ON (`-resetData` clears the enabled set).
        addTeardownBlock { [app] in
            guard let app else { return }
            app.terminate()
            app.launchArguments = ["-disableReviewPrompt", "-resetData", "-clearFixtureImports"]
            app.launch()
            _ = app.waitForDictionariesReady()
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // `TabBarPage` waits for the Search screen.
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// AC3. No relaunch anywhere between the import and the assertions.
    /// 1. Order screen BEFORE the import: the five bundled rows, no custom row
    ///    (the Settings view model has loaded, so on 85e2e02, where it never
    ///    reloads, step 4 fails).
    /// 2. Russian OFF (materialises `enabled_sources` without the fixture).
    /// 3. Back; Manage Dictionaries → Import → "Imported …".
    /// 4. Back; reopen Dictionary order: the fixture row appears.
    /// 5. Fixture ON, Russian OFF, the other three ON; fixture row last.
    /// 6. (i) on the fixture row opens its detail; back does not re-push it.
    /// 7. Fixture OFF; leave and reopen the screen: still OFF, Russian still
    ///    OFF, order unchanged.
    func testImportedDictionaryAppearsInOrderWithoutRelaunch() throws {
        let fixture = TestData.Pairs.importFixture
        let russian = TestData.Pairs.russian
        let bundled = TestData.Pairs.all
        let settings = tabBarPage.tapSettingsTab()

        // 1) Before the import.
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must open")
        for pair in bundled {
            XCTAssertTrue(rowLabel(pair).waitForExistence(timeout: TestData.Timeouts.medium),
                          "bundled row '\(pair)' before the import")
        }
        XCTAssertFalse(rowLabel(fixture).exists, "no custom row before the import")
        XCTAssertFalse(infoButton(fixture).exists, "no custom (i) before the import")
        XCTAssertNil(settings.isDictionaryEnabled(pair: fixture), "no custom toggle before the import")
        let bundledOrder = settings.currentOrder(of: bundled)
        XCTAssertEqual(bundledOrder.count, bundled.count, "all five bundled rows laid out; got \(bundledOrder)")
        for pair in bundled {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' ON after -resetData")
        }

        // 2) Russian OFF.
        settings.tapToggle(pair: russian)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: russian), false, "Russian switched OFF")

        // 3) Import on the sibling Manage Dictionaries screen.
        settings.goBack()
        XCTAssertTrue(orderView.waitForNonExistence(timeout: TestData.Timeouts.medium), "back on the Settings root")
        let manage = settings.tapManageDictionariesLink()
        XCTAssertTrue(manage.verifyNavigationTitleVisible(), "Manage Dictionaries pushed")
        manage.tapImportButton()
        let message = manage.waitForImportSuccessMessage(timeout: 20.0)
        XCTAssertTrue(message?.contains("Imported") ?? false, "fixture import must succeed; got \(message ?? "nil")")
        XCTAssertTrue(message?.contains(TestData.Sources.importFixture) ?? false,
                      "the message names the imported source; got \(message ?? "nil")")

        // 4) Back to the Settings root and reopen Dictionary order.
        settings.goBack()
        XCTAssertTrue(app.navigationBars["Manage Dictionaries"].waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "back on the Settings root")
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must reopen")
        XCTAssertTrue(rowLabel(fixture).waitForExistence(timeout: TestData.Timeouts.medium)
                      || app.scrollToElement(rowLabel(fixture)),
                      "the imported dictionary's row appears without a relaunch")

        // 5) ON, last; the user's earlier choice is kept.
        XCTAssertEqual(settings.isDictionaryEnabled(pair: fixture), true,
                       "the import lands ON although the user had toggled (PM decision 2)")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: russian), false, "the reload keeps Russian OFF")
        for pair in bundled where pair != russian {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' still ON")
        }
        let fixtureTop = rowLabel(fixture).frame.minY
        for pair in bundled where rowLabel(pair).exists {
            XCTAssertGreaterThan(fixtureTop, rowLabel(pair).frame.minY, "the import is appended below '\(pair)'")
        }
        let orderWithImport = settings.currentOrder(of: bundled + [fixture])
        XCTAssertEqual(orderWithImport, bundledOrder + [fixture], "bundled rows keep their order, the import is last")

        // 6) (i) on the new row; back from the detail does not re-push it.
        let info = settings.openInfo(pair: fixture)
        XCTAssertTrue(info.view.exists, "(i) on the imported row must push its detail")
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.noMetadata(TestData.Sources.importFixture)),
                      "the custom detail shows the no-metadata note")
        info.goBack()
        XCTAssertTrue(info.view.waitForNonExistence(timeout: TestData.Timeouts.medium), "the detail pops")
        XCTAssertTrue(orderView.waitForExistence(timeout: TestData.Timeouts.medium), "back on the order screen")
        XCTAssertFalse(info.view.waitForExistence(timeout: TestData.Timeouts.short),
                       "the reload on re-appear must not push the detail again")
        XCTAssertTrue(rowLabel(fixture).waitForExistence(timeout: TestData.Timeouts.medium), "custom row still listed")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: fixture), true, "custom row still ON")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: russian), false, "Russian still OFF")

        // 7) A toggle on the new row survives leaving and reopening the screen.
        settings.tapToggle(pair: fixture)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: fixture), false, "custom row switched OFF")
        settings.goBack()
        XCTAssertTrue(orderView.waitForNonExistence(timeout: TestData.Timeouts.medium), "back on the Settings root")
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must reopen")
        XCTAssertTrue(rowLabel(fixture).waitForExistence(timeout: TestData.Timeouts.medium), "custom row still listed")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: fixture), false, "the reload keeps the custom row OFF")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: russian), false, "the reload keeps Russian OFF")
        for pair in bundled where pair != russian {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' still ON")
        }
        XCTAssertEqual(settings.currentOrder(of: bundled + [fixture]), orderWithImport, "order unchanged")
    }

    // MARK: - Helpers

    private var orderView: XCUIElement {
        app.descendants(matching: .any)["dictionary_order_view"]
    }

    /// The pair row's leading label (the row id lives on the Text, #6).
    private func rowLabel(_ pair: String) -> XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)].firstMatch
    }

    private func infoButton(_ pair: String) -> XCUIElement {
        app.buttons[AccessibilityIdentifiers.Settings.dictionaryInfoButton(pair: pair)].firstMatch
    }
}
