import XCTest

/// Issue #91 — the (i) button on each Dictionary Order row pushes a detail that
/// stacks every underlying source of the pair (provider brand header,
/// direction, source ID, version, entries, license).
///
/// Skeleton for QA: test names and flows follow DESIGN_DOC.md §6b (block
/// header = provider brand per the PM decisions; no separate Provider row).
/// Launch / interruption / orientation setup mirrors `DictionaryPairGroupingTests`.
///
/// Identifier contract (see `AccessibilityIdentifiers.Settings.dictionaryInfoButton`
/// and `AccessibilityIdentifiers.DictionaryInfo`):
/// - (i) button:      `dictionary_info_<pairKey>`
/// - detail list:     `dictionary_info_view`
/// - per source:      `dictionary_info_{source,direction,source_id,version,entries,license,no_metadata}_<sourceID>`
final class DictionaryInfoTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")
        // Issue #105: the custom-import test imports in-session (no relaunch).
        // Both hooks are inert for the other tests: the clear deletes zero
        // rows and the callback only fires when Import is tapped.
        app.launchArguments.append("-clearFixtureImports")
        app.launchArguments.append("-importFixtureViaCallback:json")
        // The detail's long license texts make every in-app XCTest query log
        // heavily; on the iOS 17.5 sim the app process then gets its os_log
        // quarantined and XCTAutomationSupport's own fault callback segfaults
        // (strcmp on NULL in runtime_issue_os_log_fault_callback), killing
        // the app mid-test. Silence os_log for the app under test.
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

        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // A fresh install is still copying the seed: give the cold start the
        // full budget (`TabBarPage` only waits 10 s).
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60), "tab bar after launch")
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// AC test. Tap `dictionary_info_eng-spa`; title "Spanish – English";
    /// headers "WordNet" (`wordnet-spa-eng`) above "FreeDict"
    /// (`freedict-eng-spa`); both licenses revealed and non-empty (FreeDict
    /// mentions "GNU General Public License"); directions "Spanish → English"
    /// / "English → Spanish".
    func testSpanishPairInfoShowsBothSourcesAndLicenses() throws {
        let settings = tabBarPage.tapSettingsTab()
        let info = settings.openInfo(pair: TestData.Pairs.spanish)
        XCTAssertTrue(info.view.exists, "(i) on Spanish – English must push the info detail")
        XCTAssertTrue(app.navigationBars["Spanish \u{2013} English"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "detail title is the pair title (no provider parenthetical)")

        let wordnet = TestData.Sources.wordnetSpaEng
        let freedict = TestData.Sources.freedictEngSpa

        // WordNet is the first block: visible without scrolling, and FreeDict
        // (if already materialised) sits below it.
        let wordnetHeader = info.element(AccessibilityIdentifiers.DictionaryInfo.sourceHeader(wordnet))
        let freedictHeader = info.element(AccessibilityIdentifiers.DictionaryInfo.sourceHeader(freedict))
        XCTAssertTrue(wordnetHeader.waitForExistence(timeout: TestData.Timeouts.medium),
                      "WordNet block must be on screen without scrolling")
        XCTAssertEqual(wordnetHeader.label, "WordNet", "PM decision #4: header = provider brand")
        let wordnetTop = wordnetHeader.frame.minY
        if freedictHeader.exists {
            XCTAssertLessThan(wordnetTop, freedictHeader.frame.minY, "WordNet block above FreeDict")
        }
        XCTAssertEqual(label(info, AccessibilityIdentifiers.DictionaryInfo.direction(wordnet)),
                       "Spanish \u{2192} English")
        XCTAssertEqual(label(info, AccessibilityIdentifiers.DictionaryInfo.sourceID(wordnet)), wordnet)
        XCTAssertFalse(label(info, AccessibilityIdentifiers.DictionaryInfo.version(wordnet)).isEmpty,
                       "bundled source shows its version")

        // WordNet license (first block, may need a swipe on small screens).
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.license(wordnet)),
                      "WordNet license must be reachable")
        let wordnetLicense = info.element(AccessibilityIdentifiers.DictionaryInfo.license(wordnet)).label
        XCTAssertGreaterThan(wordnetLicense.count, 50, "WordNet license is real text; got '\(wordnetLicense)'")

        // FreeDict block below it.
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.sourceHeader(freedict)),
                      "FreeDict block must be reachable")
        XCTAssertEqual(freedictHeader.label, "FreeDict")
        // If WordNet scrolled out it went up, i.e. it was above FreeDict.
        if wordnetHeader.exists {
            XCTAssertLessThan(wordnetHeader.frame.minY, freedictHeader.frame.minY, "WordNet block above FreeDict")
        }
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.direction(freedict)))
        XCTAssertEqual(label(info, AccessibilityIdentifiers.DictionaryInfo.direction(freedict)),
                       "English \u{2192} Spanish")
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.license(freedict)),
                      "FreeDict license must be reachable")
        let freedictLicense = info.element(AccessibilityIdentifiers.DictionaryInfo.license(freedict)).label
        XCTAssertTrue(freedictLicense.contains("GNU General Public License"),
                      "FreeDict license text must be shown; got '\(freedictLicense.prefix(120))'")
        XCTAssertNotEqual(freedictLicense, wordnetLicense, "each block shows its own license")

        // Bundled sources never show the custom-import note.
        XCTAssertFalse(info.element(AccessibilityIdentifiers.DictionaryInfo.noMetadata(wordnet)).exists)
        XCTAssertFalse(info.element(AccessibilityIdentifiers.DictionaryInfo.noMetadata(freedict)).exists)
    }

    /// For each `TestData.Pairs.all`: open info, reveal the license of every
    /// member (`TestData.Pairs.sources`), `goBack()`.
    func testEveryPairHasInfoButtonWithLicense() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder())
        for pair in TestData.Pairs.all {
            let info = settings.openInfo(pair: pair)
            XCTAssertTrue(info.view.exists, "(i) on '\(pair)' must push the info detail")
            let members = try XCTUnwrap(TestData.Pairs.sources[pair])
            for source in members {
                let header = AccessibilityIdentifiers.DictionaryInfo.sourceHeader(source)
                XCTAssertTrue(info.revealElement(header), "'\(pair)': block for '\(source)'")
                XCTAssertEqual(info.element(header).label, brands[source], "'\(source)' header brand")
                let license = AccessibilityIdentifiers.DictionaryInfo.license(source)
                XCTAssertTrue(info.revealElement(license), "'\(pair)': license for '\(source)' must be visible")
                XCTAssertGreaterThan(info.element(license).label.count, 50, "'\(source)' license text")
            }
            // No block for a source outside this pair.
            for other in Set(TestData.Pairs.sources.values.joined()).subtracting(members) {
                XCTAssertFalse(info.element(AccessibilityIdentifiers.DictionaryInfo.sourceHeader(other)).exists,
                               "'\(pair)' detail must not list '\(other)'")
            }
            info.goBack()
            XCTAssertTrue(orderView.waitForExistence(timeout: TestData.Timeouts.medium),
                          "back from '\(pair)' detail returns to the order screen")
        }
    }

    /// Opening and leaving the info detail leaves toggle state and order
    /// unchanged; tapping the toggle still flips only the toggle (no push).
    func testInfoButtonDoesNotToggleOrMoveRow() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder())
        let pairs = TestData.Pairs.all
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        let order = settings.currentOrder(of: pairs)
        XCTAssertEqual(order.count, 4)
        let states = pairs.map { settings.isDictionaryEnabled(pair: $0) }
        XCTAssertEqual(states, [true, true, true, true], "all pairs ON after -resetData")

        // (i) → detail → back: nothing on the row changed.
        let info = settings.openInfo(pair: TestData.Pairs.spanish)
        XCTAssertTrue(info.view.exists)
        info.goBack()
        XCTAssertTrue(orderView.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(settings.currentOrder(of: pairs), order, "(i) must not move the row")
        XCTAssertEqual(pairs.map { settings.isDictionaryEnabled(pair: $0) }, states, "(i) must not flip any toggle")

        // Tapping the row title is inert (edit-mode list, no row-wide hit target).
        rowLabel(TestData.Pairs.spanish).tap()
        XCTAssertFalse(info.view.waitForExistence(timeout: TestData.Timeouts.short),
                       "tapping the row title must not open the detail")
        XCTAssertEqual(pairs.map { settings.isDictionaryEnabled(pair: $0) }, states, "title tap must not flip a toggle")

        // The toggle still flips only itself and never pushes.
        settings.tapToggle(pair: TestData.Pairs.spanish)
        XCTAssertFalse(info.view.waitForExistence(timeout: TestData.Timeouts.short),
                       "toggle tap must not open the detail")
        XCTAssertTrue(orderView.exists)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.spanish), false)
        for pair in pairs where pair != TestData.Pairs.spanish {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' untouched")
        }
        XCTAssertEqual(settings.currentOrder(of: pairs), order, "toggle must not move the row")

        // The detail still opens for a disabled pair.
        let infoOff = settings.openInfo(pair: TestData.Pairs.spanish)
        XCTAssertTrue(infoOff.view.exists, "(i) works on a disabled pair")
        infoOff.goBack()
        XCTAssertTrue(orderView.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.spanish), false, "still OFF after the round trip")
    }

    /// `reorderFirstToLast(pairs:)` still changes the order with the (i)
    /// button in the row; four rows, each once.
    func testDragStillReordersWithInfoButton() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder())
        let pairs = TestData.Pairs.all
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        for pair in pairs {
            XCTAssertTrue(infoButton(pair).exists, "(i) present on '\(pair)' before the drag")
        }
        let before = settings.currentOrder(of: pairs)
        XCTAssertEqual(before.count, 4, "all four pairs laid out; got \(before)")

        let after = settings.reorderFirstToLast(pairs: pairs)
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.DictionaryInfo.view].exists,
                       "a drag must never push the info detail")
        XCTAssertNotEqual(after, before, "drag must change the order. before=\(before) after=\(after)")
        XCTAssertEqual(after.count, 4, "still exactly four rows; got \(after)")
        XCTAssertEqual(Set(after), Set(pairs), "each pair exactly once; got \(after)")
        // The helper drops on the last row's midpoint, which SwiftUI may resolve
        // to just above or below it (iOS 26.4 lands above): assert "moved down",
        // not "moved to the end".
        let dragged = before[0]
        XCTAssertGreaterThan(after.firstIndex(of: dragged) ?? 0, 0,
                             "the dragged pair '\(dragged)' moved down. before=\(before) after=\(after)")
        XCTAssertEqual(after.filter { $0 != dragged }, Array(before.dropFirst()),
                       "others keep their relative order. before=\(before) after=\(after)")
        for pair in pairs {
            XCTAssertTrue(infoButton(pair).exists, "(i) still present on '\(pair)' after the drag")
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "drag must not flip '\(pair)'")
        }

        // A press-drag that starts ON the (i) must not push the detail
        // (borderless button cancels when the press turns into a drag) and
        // must not split or drop rows, whether or not it reorders.
        let current = settings.currentOrder(of: pairs)
        let src = infoButton(current[0])
        let dst = rowLabel(current[current.count - 1])
        XCTAssertTrue(src.exists && dst.exists)
        src.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: dst.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.DictionaryInfo.view]
                        .waitForExistence(timeout: TestData.Timeouts.short),
                       "a drag starting on the (i) must not open the detail")
        XCTAssertTrue(orderView.exists, "still on the order screen")
        let afterInfoDrag = settings.currentOrder(of: pairs)
        XCTAssertEqual(afterInfoDrag.count, 4, "rows intact after a drag from the (i); got \(afterInfoDrag)")
        XCTAssertEqual(Set(afterInfoDrag), Set(pairs))

        // The moved row's (i) still opens its own detail.
        let moved = dragged
        let info = settings.openInfo(pair: moved)
        XCTAssertTrue(info.view.exists, "(i) on the moved row '\(moved)' opens the detail")
        let firstSource = try XCTUnwrap(TestData.Pairs.sources[moved]?.first)
        XCTAssertTrue(info.revealElement(AccessibilityIdentifiers.DictionaryInfo.sourceHeader(firstSource)),
                      "detail belongs to the moved pair '\(moved)'")
    }

    /// Imported fixture `custom:test_import_fixture`: header is the source ID,
    /// `no_metadata` footer exists, no license / version rows. The import
    /// happens in-session and the order screen reloads on appear (#105), so
    /// there is no relaunch between the import and the detail.
    func testCustomImportInfoShowsNoMetadataNote() throws {
        let source = "test_import_fixture"
        let pair = "custom:\(source)"

        // Always scrub the fixture afterwards: later tests assume the four
        // bundled pairs only.
        addTeardownBlock { [app] in
            guard let app else { return }
            app.terminate()
            app.launchArguments = ["-disableReviewPrompt", "-resetData", "-clearFixtureImports"]
            app.launch()
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 60)
            app.terminate()
        }

        // 1) Import the JSON fixture (bypasses the document picker).
        let settings = tabBarPage.tapSettingsTab()
        let manage = settings.tapManageDictionariesLink()
        manage.tapImportButton()
        let message = manage.waitForImportSuccessMessage(timeout: 20.0)
        XCTAssertTrue(message?.contains("Imported") ?? false, "fixture import must succeed; got \(message ?? "nil")")

        // 2) Back to the Settings root; no relaunch (#105).
        settings.goBack()
        XCTAssertTrue(app.navigationBars["Manage Dictionaries"].waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "back on the Settings root")

        // 3) Open the custom row's detail.
        XCTAssertTrue(settings.openDictionaryOrder())
        let button = infoButton(pair)
        XCTAssertTrue(button.waitForExistence(timeout: TestData.Timeouts.medium) || app.scrollToElement(button),
                      "custom import row must have an (i) button")
        let info = settings.openInfo(pair: pair)
        XCTAssertTrue(info.view.exists, "(i) on the custom row must push the detail")

        let ids = AccessibilityIdentifiers.DictionaryInfo.self
        XCTAssertTrue(info.revealElement(ids.sourceHeader(source)))
        XCTAssertEqual(info.element(ids.sourceHeader(source)).label, source, "custom header = source ID")
        XCTAssertEqual(label(info, ids.sourceID(source)), source)
        XCTAssertTrue(info.revealElement(ids.entries(source)))
        XCTAssertNotEqual(label(info, ids.entries(source)), "0", "imported entries are counted")
        XCTAssertTrue(info.revealElement(ids.noMetadata(source)), "custom import shows the no-metadata note")
        XCTAssertEqual(info.element(ids.noMetadata(source)).label,
                       "Imported dictionary. No version or license information is available.")

        // Nothing is invented for a custom import.
        XCTAssertFalse(info.element(ids.license(source)).exists, "no license row for a custom import")
        XCTAssertFalse(info.element(ids.version(source)).exists, "no version row for a custom import")
        XCTAssertFalse(info.element(ids.direction(source)).exists, "no direction row for a custom import")
        for bundled in Set(TestData.Pairs.sources.values.joined()) {
            XCTAssertFalse(info.element(ids.sourceHeader(bundled)).exists, "custom detail lists only its own source")
        }
    }

    // MARK: - Helpers

    /// Expected block header per bundled source (provider brand, PM decision #4).
    private let brands: [String: String] = [
        TestData.Sources.wordnet: "WordNet",
        TestData.Sources.openrussian: "OpenRussian",
        TestData.Sources.wordnetSpaEng: "WordNet",
        TestData.Sources.freedictEngSpa: "FreeDict",
        TestData.Sources.wordnetArbEng: "WordNet",
    ]

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

    /// Waits for a value leaf and returns its label ("" if it never appears).
    private func label(_ info: DictionaryInfoPage, _ id: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = info.element(id)
        XCTAssertTrue(element.waitForExistence(timeout: TestData.Timeouts.medium), "'\(id)' must exist",
                      file: file, line: line)
        return element.exists ? element.label : ""
    }
}
