import XCTest

/// Issue #92 — the Dictionary Order screen groups same-language sources into
/// one row with a single toggle and a single drag slot per language pair.
///
/// Skeleton for QA: test names and flows follow DESIGN_DOC.md §7b; bodies are
/// TODO. Launch / interruption / orientation setup mirrors
/// `DictionaryFilterTests` (the reliable toggle suite in this project).
///
/// Identifier contract (product-defined, see `AccessibilityIdentifiers`):
/// - pair row (leading `Text`): `dictionary_order_row_<pairKey>`
/// - pair toggle (Switch):      `dictionary_toggle_<pairKey>`
/// - pair keys:                 `TestData.Pairs` (`eng`, `eng-rus`, `eng-spa`, `arb-eng`)
///
/// Probe terms and their exclusivity notes come from `DictionaryFilterTests`
/// (`niños` → `freedict-eng-spa` / `En–Es`, `atacar` → `wordnet-spa-eng` /
/// `Es–En`, `яблоко` → `openrussian`).
final class DictionaryPairGroupingTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")

        // iOS 26 "Enable Dictation?" springboard alert — tap a dismissal button
        // instead of XCUI's default (which opens a blocking privacy sheet).
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

        // Force portrait — sim orientation persists across sessions on Intel
        // x86_64, and landscape no-ops swipeUp against SwiftUI Form/List.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// Open the order screen; rows exist for the four pair keys;
    /// `app.switches` matching `identifier BEGINSWITH "dictionary_toggle_"`
    /// count == 4; no `dictionary_order_row_wordnet-spa-eng` /
    /// `_freedict-eng-spa` / `_wordnet` / `_openrussian`; labels: `eng-spa` ==
    /// "Spanish – English", `eng-rus` == "Russian – English", `arb-eng` ==
    /// "Arabic – English", `eng` == "English" (U+2013 en dash).
    func testEachPairAppearsOnceWithLanguageDashEnglishTitle() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary-order link should push the order screen")

        // One row per pair, each found by the leading-Text id (#6 gotcha:
        // query staticTexts, never the container).
        for pair in TestData.Pairs.all {
            XCTAssertTrue(rowLabel(pair).waitForExistence(timeout: TestData.Timeouts.medium),
                          "Row for pair '\(pair)' must exist")
        }
        XCTAssertEqual(settings.currentOrder(of: TestData.Pairs.all).count, TestData.Pairs.all.count,
                       "every pair is laid out exactly once")

        // Exactly four toggles: the two Spanish directions share one switch.
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_toggle_"))
        XCTAssertEqual(toggles.count, 4, "one toggle per pair; got \(toggles.allElementsBoundByIndex.map(\.identifier))")
        let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_order_row_"))
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)),
                       Set(TestData.Pairs.all.map(AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair:))),
                       "row ids are pair keys only")

        // No per-source rows survive.
        for source in ["wordnet-spa-eng", "freedict-eng-spa", "wordnet", "openrussian", "wordnet-arb-eng"] {
            XCTAssertFalse(app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: source)].exists,
                           "per-source row '\(source)' must be gone")
            XCTAssertFalse(app.switches[AccessibilityIdentifiers.Settings.dictionaryToggle(pair: source)].exists,
                           "per-source toggle '\(source)' must be gone")
        }

        // `<Language> – English` titles (U+2013), plain "English" for WordNet,
        // no provider parenthetical.
        let expected: [String: String] = [
            TestData.Pairs.spanish: "Spanish \u{2013} English",
            TestData.Pairs.russian: "Russian \u{2013} English",
            TestData.Pairs.arabic: "Arabic \u{2013} English",
            TestData.Pairs.english: "English",
        ]
        for (pair, title) in expected {
            XCTAssertEqual(rowLabel(pair).label, title, "title for '\(pair)'")
        }
        // Every pair starts ON after -resetData.
        for pair in TestData.Pairs.all {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' must start ON")
        }
    }

    /// Baseline `niños` → results with `En–Es` at index 0 and `atacar` →
    /// `Es–En`; `tapToggle(pair: spanish)`; both terms → `search_no_results`;
    /// toggle back → both return.
    func testSingleToggleHidesBothDirectionsInSearch() throws {
        // 1) Baseline: each direction's exclusive probe returns its own badge.
        var searchPage = tabBarPage.tapSearchTab()
        assertProbe(searchPage, term: spanishOnlyTerm, badge: freeDictBadge)
        assertProbe(searchPage, term: spanishHeadwordTerm, badge: spanishWordNetBadge)
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) ONE toggle for the Spanish pair.
        var settings = tabBarPage.tapSettingsTab()
        settings.tapToggle(pair: TestData.Pairs.spanish)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.spanish), false)
        // Neighbouring pairs untouched.
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.english), true)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.russian), true)

        // 3) Both directions are gone.
        searchPage = tabBarPage.tapSearchTab()
        for term in [spanishOnlyTerm, spanishHeadwordTerm] {
            searchPage.clearSearch()
            searchPage.searchFor(term)
            XCTAssertTrue(searchPage.waitForNoResults(),
                          "With the Spanish pair OFF, '\(term)' must show the no-results view")
        }
        searchPage.clearOverlaysBeforeTabSwitch()

        // 4) Toggle back → both directions return.
        settings = tabBarPage.tapSettingsTab()
        settings.tapToggle(pair: TestData.Pairs.spanish)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.spanish), true)
        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        assertProbe(searchPage, term: spanishOnlyTerm, badge: freeDictBadge)
        assertProbe(searchPage, term: spanishHeadwordTerm, badge: spanishWordNetBadge)
    }

    /// `reorderFirstToLast(pairs:)` → order changed, still exactly four rows,
    /// each key once.
    func testDragMovesPairAsOneRow() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary-order link should push the order screen")
        let pairs = TestData.Pairs.all
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        let before = settings.currentOrder(of: pairs)
        // The seed's count-desc base order decides the rest (FreeDict eng-spa
        // outranks OpenRussian), so only pin what #74 guarantees for `en`.
        XCTAssertEqual(before.count, 4, "all four pairs laid out; got \(before)")
        XCTAssertEqual(before.first, TestData.Pairs.english, "English pair first on an English fresh install")

        let after = settings.reorderFirstToLast(pairs: pairs)
        XCTAssertNotEqual(after, before, "drag must change the order. before=\(before) after=\(after)")
        XCTAssertEqual(after.count, 4, "still exactly four rows after the drag; got \(after)")
        XCTAssertEqual(Set(after), Set(pairs), "each pair exactly once; got \(after)")
        XCTAssertEqual(after.last, before.first, "the dragged pair moved as one row to the end")
        XCTAssertEqual(Array(after.dropLast()), Array(before.dropFirst()),
                       "the other pairs keep their relative order")
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_toggle_"))
        XCTAssertEqual(toggles.count, 4, "the drag must not split a pair into per-source rows")
    }

    /// Toggle `eng-rus` off and move the first row to last; `app.terminate()`;
    /// relaunch WITHOUT `-resetData`; order screen shows the same order and
    /// `eng-rus` still OFF; `яблоко` → `search_no_results`.
    func testPairPreferencesSurviveRelaunch() throws {
        var settings = tabBarPage.tapSettingsTab()
        settings.tapToggle(pair: TestData.Pairs.russian)
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.russian), false)
        let pairs = TestData.Pairs.all
        let before = settings.currentOrder(of: pairs)
        let moved = settings.reorderFirstToLast(pairs: pairs)
        XCTAssertNotEqual(moved, before, "precondition: the drag changed the order")
        XCTAssertEqual(moved.count, 4)

        // Relaunch WITHOUT -resetData: the stored source-level prefs must
        // round-trip through the launch-time normalisation unchanged.
        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60), "tab bar after relaunch")
        tabBarPage = TabBarPage(app: app)

        settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(), "order screen after relaunch")
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(settings.currentOrder(of: pairs), moved, "pair order must survive a relaunch")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: TestData.Pairs.russian), false,
                       "Russian pair must still be OFF after relaunch")
        for pair in pairs where pair != TestData.Pairs.russian {
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), true, "'\(pair)' must still be ON")
        }

        // The persisted OFF state still filters search.
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(searchPage.waitForNoResults(),
                      "'\(russianOnlyTerm)' must show no results while the Russian pair is OFF after relaunch")
    }

    // MARK: - Probe data (exclusivity verified in DictionaryFilterTests)

    /// Only in `freedict-eng-spa` (plural never a Spanish-WordNet lemma).
    private let spanishOnlyTerm = "niños"
    /// Only in `wordnet-spa-eng`.
    private let spanishHeadwordTerm = "atacar"
    /// Only in `openrussian`.
    private let russianOnlyTerm = "яблоко"
    /// `sourceLabel` badges (U+2013), which stay per source.
    private let freeDictBadge = "En\u{2013}Es"
    private let spanishWordNetBadge = "Es\u{2013}En"

    /// The pair row's leading label (the row id lives on the Text, #6).
    private func rowLabel(_ pair: String) -> XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)].firstMatch
    }

    private func assertProbe(_ page: SearchPage, term: String, badge: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        page.clearSearch()
        page.searchFor(term)
        XCTAssertTrue(page.waitForResults(), "'\(term)' must return results", file: file, line: line)
        XCTAssertTrue(page.verifyResultContainsText(badge, at: 0),
                      "first result for '\(term)' must carry the '\(badge)' badge", file: file, line: line)
    }
}
