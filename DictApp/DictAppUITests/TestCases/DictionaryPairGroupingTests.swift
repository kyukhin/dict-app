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
/// - pair keys:                 `TestData.Pairs` (`eng`, `eng-rus`, `eng-spa`, `arb-eng`, `ell-eng`)
///
/// Probe terms and their exclusivity notes come from `DictionaryFilterTests`
/// (`niños` → `freedict-eng-spa`, `atacar` → `wordnet-spa-eng`, `яблоко` →
/// `openrussian`). Badges are matched by `source_badge_<source>` (Issue #87).
final class DictionaryPairGroupingTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")
        // Same os_log quarantine crash as `DictionaryInfoTests` (Issue #125).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

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

    /// Open the order screen; rows exist for the five pair keys;
    /// `app.switches` matching `identifier BEGINSWITH "dictionary_toggle_"`
    /// count == 5; no per-source rows (`dictionary_order_row_wordnet-spa-eng`,
    /// `_freedict-ell-eng`, …); labels: `eng-spa` == "Spanish – English",
    /// `eng-rus` == "Russian – English", `arb-eng` == "Arabic – English",
    /// `ell-eng` == "Greek – English", `eng` == "English" (U+2013 en dash).
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

        // Exactly five toggles: the two Spanish directions share one switch,
        // the four Greek sources another (Issue #87).
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_toggle_"))
        XCTAssertEqual(toggles.count, TestData.Pairs.all.count,
                       "one toggle per pair; got \(toggles.allElementsBoundByIndex.map(\.identifier))")
        let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_order_row_"))
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)),
                       Set(TestData.Pairs.all.map(AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair:))),
                       "row ids are pair keys only")

        // No per-source rows survive.
        for source in TestData.Pairs.sources.values.joined() {
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
            TestData.Pairs.greek: "Greek \u{2013} English",
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

    /// Baseline `niños` → `freedict-eng-spa` badge at index 0 and `atacar` →
    /// `wordnet-spa-eng`; `tapToggle(pair: spanish)`; both terms →
    /// `search_no_results`; toggle back → both return.
    func testSingleToggleHidesBothDirectionsInSearch() throws {
        // 1) Baseline: each direction's exclusive probe returns its own badge.
        var searchPage = tabBarPage.tapSearchTab()
        assertProbe(searchPage, term: spanishOnlyTerm, source: TestData.Sources.freedictEngSpa)
        assertProbe(searchPage, term: spanishHeadwordTerm, source: TestData.Sources.wordnetSpaEng)
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
        assertProbe(searchPage, term: spanishOnlyTerm, source: TestData.Sources.freedictEngSpa)
        assertProbe(searchPage, term: spanishHeadwordTerm, source: TestData.Sources.wordnetSpaEng)
    }

    /// `reorderFirstToLast(pairs:)` → order changed, still exactly five rows,
    /// each key once.
    func testDragMovesPairAsOneRow() throws {
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary-order link should push the order screen")
        let pairs = TestData.Pairs.all
        XCTAssertTrue(rowLabel(pairs[0]).waitForExistence(timeout: TestData.Timeouts.medium))
        let before = settings.currentOrder(of: pairs)
        // The seed's count-desc base order decides the rest (FreeDict eng-spa
        // outranks OpenRussian), so only pin what #74 guarantees for `en`.
        XCTAssertEqual(before.count, pairs.count, "all five pairs laid out; got \(before)")
        XCTAssertEqual(before.first, TestData.Pairs.english, "English pair first on an English fresh install")

        let after = settings.reorderFirstToLast(pairs: pairs)
        XCTAssertNotEqual(after, before, "drag must change the order. before=\(before) after=\(after)")
        XCTAssertEqual(after.count, pairs.count, "still exactly five rows after the drag; got \(after)")
        XCTAssertEqual(Set(after), Set(pairs), "each pair exactly once; got \(after)")
        XCTAssertEqual(after.last, before.first, "the dragged pair moved as one row to the end")
        XCTAssertEqual(Array(after.dropLast()), Array(before.dropFirst()),
                       "the other pairs keep their relative order")
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary_toggle_"))
        XCTAssertEqual(toggles.count, pairs.count, "the drag must not split a pair into per-source rows")
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
        XCTAssertEqual(moved.count, pairs.count)

        // Relaunch WITHOUT -resetData: the stored source-level prefs must
        // round-trip through the launch-time normalisation unchanged.
        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"]
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search screen after relaunch")
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
    /// Headword only in `wordnet-spa-eng` (3 `freedict-eng-spa` definitions
    /// also mention it since #108; both sit behind the `eng-spa` toggle).
    private let spanishHeadwordTerm = "atacar"
    /// Only in `openrussian`.
    private let russianOnlyTerm = "яблоко"
    /// The pair row's leading label (the row id lives on the Text, #6).
    private func rowLabel(_ pair: String) -> XCUIElement {
        app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: pair)].firstMatch
    }

    /// `term` returns results and the first one carries `source`'s badge
    /// (`source_badge_<source>`, Issue #87).
    private func assertProbe(_ page: SearchPage, term: String, source: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        page.clearSearch()
        page.searchFor(term)
        XCTAssertTrue(page.waitForResults(), "'\(term)' must return results", file: file, line: line)
        XCTAssertTrue(page.verifyResultHasBadge(source: source, at: 0),
                      "first result for '\(term)' must carry the \(source) badge", file: file, line: line)
    }
}
