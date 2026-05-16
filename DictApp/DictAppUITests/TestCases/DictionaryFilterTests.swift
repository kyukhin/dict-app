import XCTest

/// Issue #2 — per-dictionary enable/disable toggle in Settings.
///
/// These tests verify the end-to-end behavior of the toggle in Settings →
/// Dictionaries: search results must respect the toggle state, and disabling
/// every dictionary must produce an empty result set on the Search screen.
///
/// Modeled on `BookmarkFlowTests` (the reliable UI suite in this project).
///
/// Each test launches with `-resetData`, which (in
/// `DictApp.initializeDatabase`) resets `SettingsService.enabledSources = nil`
/// — the first-launch default in which every dictionary is enabled. Tests
/// therefore start from a baseline of "all toggles ON".
///
/// We probe the source-filter behavior with a *Russian* query ("яблоко"),
/// because the seed's English source (WordNet) has no Cyrillic entries —
/// so disabling OpenRussian must produce ContentUnavailableView, with no
/// false positives from cross-language definition text. Probing with an
/// English query like "apple" is unreliable: OpenRussian definitions
/// contain English translations, so disabling WordNet still returns
/// OpenRussian matches whose definition contains "apple".
final class DictionaryFilterTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// The two sources shipped in the seed database.
    private let englishSource = "wordnet"
    private let russianSource = "openrussian"

    /// A search term that exists in OpenRussian and *only* in OpenRussian
    /// (no Cyrillic in WordNet). Disabling OpenRussian must drop it to 0.
    private let russianOnlyTerm = "яблоко"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-resetData")

        // iOS 26 surfaces an "Enable Dictation?" springboard alert the first
        // time the user activates `.searchable()`. XCUI's default handler
        // taps the *default* button which on iOS 26 happens to be the
        // "About Siri, Dictation & Privacy…" info link — that opens a
        // full-screen privacy sheet that blocks the tab bar. Install our
        // own monitor that taps a dismissal button instead.
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
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    /// Disabling one dictionary must remove its entries from search results.
    ///
    /// Strategy: search "яблоко" with both dictionaries on → results appear
    /// (OpenRussian entries). Disable `openrussian` → repeat the same search
    /// → ContentUnavailableView appears, because WordNet has no Cyrillic.
    func testDisablingDictionaryHidesItsResults() throws {
        // 1) Baseline: with all dictionaries enabled, "яблоко" returns results.
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "Search for '\(russianOnlyTerm)' should return results when all dictionaries are enabled"
        )
        XCTAssertGreaterThan(
            searchPage.getResultsCount(), 0,
            "Baseline result count must be > 0"
        )

        // The keyboard overlays the tab bar after a `.searchable()` query,
        // so we must dismiss it before switching tabs.
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) Disable the Russian dictionary.
        let settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(source: russianSource)

        // 3) Re-run the same search. Results must be empty because "яблоко"
        //    only exists in the (now-disabled) Russian source.
        let searchPageAgain = tabBarPage.tapSearchTab()
        searchPageAgain.clearSearch()
        searchPageAgain.searchFor(russianOnlyTerm)

        XCTAssertTrue(
            searchPageAgain.waitForNoResults(),
            "After disabling '\(russianSource)', search for '\(russianOnlyTerm)' must show ContentUnavailableView"
        )
    }

    /// Disabling every dictionary must produce an empty result set for any query.
    ///
    /// Turn both `wordnet` and `openrussian` off, then issue a query. Search
    /// must return zero rows — this is the SQL short-circuit path in
    /// `DatabaseService.search()` when `enabledSources` is the empty set.
    func testDisablingAllDictionariesReturnsEmpty() throws {
        // 1) Disable both dictionaries in Settings.
        let settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(source: englishSource)
        settingsPage.tapToggle(source: russianSource)

        // 2) Search for a word that would normally hit at least one dict.
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)

        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "With all dictionaries disabled, search must show ContentUnavailableView"
        )
    }

    /// Re-enabling a previously disabled dictionary must restore its results.
    /// Round-trip sanity check so the off→on path is exercised too.
    func testReEnablingDictionaryRestoresResults() throws {
        // 1) Disable, search, expect empty.
        var settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(source: russianSource)

        var searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "Search must show ContentUnavailableView while '\(russianSource)' is disabled"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) Re-enable, search again, expect results.
        settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(source: russianSource)

        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "Search must return results after '\(russianSource)' is re-enabled"
        )
    }
}

