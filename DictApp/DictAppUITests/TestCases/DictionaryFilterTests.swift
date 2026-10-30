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

    /// Language-pair keys as rendered on the Dictionary Order screen (Issue
    /// #92): one row / one toggle per pair. `spanishPair` covers BOTH
    /// `freedict-eng-spa` and `wordnet-spa-eng`.
    private let englishPair = TestData.Pairs.english
    private let russianPair = TestData.Pairs.russian
    private let spanishPair = TestData.Pairs.spanish

    /// Source IDs: badges and stripes stay per source, and badges are
    /// matched by `source_badge_<source>` (Issue #87).
    private let englishSpanishSource = TestData.Sources.freedictEngSpa
    private let spanishEnglishSource = TestData.Sources.wordnetSpaEng

    /// A search term that exists in OpenRussian and *only* in OpenRussian
    /// (no Cyrillic in WordNet). Disabling OpenRussian must drop it to 0.
    private let russianOnlyTerm = "яблоко"

    /// A Spanish term that exists *only* in FreeDict eng-spa — and stays
    /// exclusive even after Spanish WordNet (#42) added 36k Spanish
    /// headwords. We deliberately use the **plural** "niños": Spanish
    /// WordNet stores singular lemmas ("niño"), so the plural never
    /// appears as a `wordnet-spa-eng` headword, whereas FreeDict spells
    /// translations in context (including plurals) inside its
    /// definitions. The `ñ` rules out collisions with WordNet's
    /// plain-ASCII English headwords, and the Latin script rules out
    /// OpenRussian's Cyrillic. Re-verified against the nine-source seed
    /// (#87, with #108's extra translations): 6 FTS matches, all
    /// `source = 'freedict-eng-spa'`.
    ///
    /// (The earlier choice "español" stopped being exclusive once #42
    /// landed — it became an exact `wordnet-spa-eng` headword, which then
    /// out-ranked the FreeDict definition match and broke the index-0
    /// badge assertion. The lesson: probe terms for source-isolation
    /// tests must be re-validated whenever a new source is bundled.)
    private let spanishOnlyTerm = "niños"

    /// A Spanish headword that exists *only* in Spanish WordNet
    /// (`wordnet-spa-eng`): the one exact `atacar` headword. Since #108
    /// keeps every FreeDict translation, three `freedict-eng-spa`
    /// definitions (assail, come at, lash out) also mention it, so the term
    /// is exclusive to the Spanish *pair*, not to one source: the exact
    /// headword still ranks first, and disabling the `eng-spa` pair (both
    /// sources) still drops it to zero results. Re-verified against the
    /// nine-source seed (#87). 'atacar' → 'attack' is a transparent cognate,
    /// so a hit also confirms the spa→eng synset mapping resolved to the
    /// right word.
    private let spanishHeadwordTerm = "atacar"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")
        // Issue #145: the chip tests query the whole tree often; on iOS 17.5
        // that hit the os_log quarantine crash of `DictionaryInfoTests` (#125).
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

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
        settingsPage.tapToggle(pair: russianPair)

        // 3) Re-run the same search. Results must be empty because "яблоко"
        //    only exists in the (now-disabled) Russian source.
        let searchPageAgain = tabBarPage.tapSearchTab()
        searchPageAgain.clearSearch()
        searchPageAgain.searchFor(russianOnlyTerm)

        XCTAssertTrue(
            searchPageAgain.waitForNoResults(),
            "After disabling '\(russianPair)', search for '\(russianOnlyTerm)' must show ContentUnavailableView"
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
        settingsPage.tapToggle(pair: englishPair)
        settingsPage.tapToggle(pair: russianPair)

        // 2) Search for a word that would normally hit at least one dict.
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)

        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "With all dictionaries disabled, search must show ContentUnavailableView"
        )
    }

    // MARK: - FreeDict eng-spa (Issue #24)

    /// Searching a Spanish-only word ("español", with the unambiguous `ñ`)
    /// must surface FreeDict eng-spa entries end-to-end:
    ///   - the results list must be non-empty,
    ///   - the first row must carry the `freedict-eng-spa` source badge
    ///     (`source_badge_freedict-eng-spa`, visible text "En–Es · FD").
    ///
    /// Without the badge assertion this test would still pass if some
    /// other source happened to mention "español" in its definitions; the
    /// badge proves the contribution comes from the new bundle.
    func testSearchingSpanishOnlyWordSurfacesFreeDictResults() throws {
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(spanishOnlyTerm)

        XCTAssertTrue(
            searchPage.waitForResults(),
            "Search for '\(spanishOnlyTerm)' must return at least one result from \(englishSpanishSource)"
        )
        XCTAssertTrue(
            searchPage.verifyResultHasBadge(source: englishSpanishSource, at: 0),
            "First result for '\(spanishOnlyTerm)' must carry the \(englishSpanishSource) source badge, proving the entry came from it"
        )
    }

    /// Disabling the Spanish pair must eliminate Spanish-only hits, and
    /// re-enabling must bring them back. Round-trips the toggle so we
    /// cover both edges of the per-source filter for the new source.
    ///
    /// Issue #92: `freedict-eng-spa` and `wordnet-spa-eng` share the single
    /// `eng-spa` row, so the one toggle must also hide the Spanish-WordNet
    /// probe (`atacar`) — asserted here because both directions now
    /// exercise the same row.
    ///
    /// Probing with a term that exists exclusively in `freedict-eng-spa`
    /// keeps the empty-state assertion meaningful — without an
    /// exclusivity guarantee, leftover hits from another dictionary's
    /// loanword entries would mask a regression in the toggle wiring.
    func testDisablingFreeDictHidesAndRestoresSpanishResults() throws {
        // 1) Baseline: with all dictionaries enabled, '\(spanishOnlyTerm)'
        //    returns results.
        var searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(spanishOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "Baseline: '\(spanishOnlyTerm)' must return results before toggling"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) Disable the Spanish pair (freedict-eng-spa AND wordnet-spa-eng).
        var settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: spanishPair)

        // 3) The same search now drops to ContentUnavailableView — the
        //    Spanish-only term has no remaining home in the enabled set.
        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(spanishOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "After disabling the '\(spanishPair)' pair, '\(spanishOnlyTerm)' must show ContentUnavailableView"
        )
        //    …and so does the other direction's probe (same row, Issue #92).
        searchPage.clearSearch()
        searchPage.searchFor(spanishHeadwordTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "After disabling the '\(spanishPair)' pair, '\(spanishHeadwordTerm)' (\(spanishEnglishSource)) must also show ContentUnavailableView"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 4) Re-enable the Spanish pair; results must come back.
        settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: spanishPair)

        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(spanishOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "After re-enabling the '\(spanishPair)' pair, '\(spanishOnlyTerm)' must return results again"
        )
    }

    // MARK: - Spanish WordNet spa-eng (Issue #42)

    /// Searching a Spanish headword that exists only in Spanish WordNet
    /// ("atacar") must surface a `wordnet-spa-eng` row end-to-end:
    ///   - the results list is non-empty, and
    ///   - the first row carries the `wordnet-spa-eng` source badge
    ///     (`source_badge_wordnet-spa-eng`, visible text "Es–En · WN").
    ///
    /// Because the only "atacar" headword is in `wordnet-spa-eng` (FreeDict
    /// eng-spa only mentions it in definitions, which rank below an exact
    /// headword), the first result is that row — the badge assertion
    /// makes this a provenance check, not a generic "search returned
    /// something". Mirrors the #24 eng-spa coverage in the opposite
    /// translation direction.
    func testSearchingSpanishHeadwordSurfacesSpanishWordNetResults() throws {
        let searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(spanishHeadwordTerm)

        XCTAssertTrue(
            searchPage.waitForResults(),
            "Search for '\(spanishHeadwordTerm)' must return at least one result from \(spanishEnglishSource)"
        )
        XCTAssertTrue(
            searchPage.verifyResultHasBadge(source: spanishEnglishSource, at: 0),
            "First result for '\(spanishHeadwordTerm)' must carry the \(spanishEnglishSource) badge, proving the entry came from it"
        )
    }

    /// Disabling the Spanish pair must eliminate the Spanish-headword
    /// hits, and re-enabling must restore them. Round-trips the toggle so
    /// both edges of the per-source filter are covered for the fourth
    /// source.
    ///
    /// Issue #92: `wordnet-spa-eng` shares the single `eng-spa` row with
    /// `freedict-eng-spa`, so the one toggle must also hide the FreeDict
    /// probe (`niños`) — asserted here because both directions now
    /// exercise the same row.
    ///
    /// Probing with a term exclusive to the Spanish pair keeps the
    /// empty-state assertion meaningful: its only other hits (three
    /// FreeDict eng-spa definitions since #108) sit behind the same
    /// `eng-spa` toggle, so a leftover hit would mean a regression in the
    /// toggle wiring.
    func testDisablingSpanishWordNetHidesAndRestoresResults() throws {
        // 1) Baseline: with all dictionaries enabled, '\(spanishHeadwordTerm)'
        //    returns results.
        var searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(spanishHeadwordTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "Baseline: '\(spanishHeadwordTerm)' must return results before toggling"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) Disable the Spanish pair (wordnet-spa-eng AND freedict-eng-spa).
        var settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: spanishPair)

        // 3) The same search now drops to ContentUnavailableView — the
        //    term has no remaining home in the enabled set.
        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(spanishHeadwordTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "After disabling the '\(spanishPair)' pair, '\(spanishHeadwordTerm)' must show ContentUnavailableView"
        )
        //    …and so does the other direction's probe (same row, Issue #92).
        searchPage.clearSearch()
        searchPage.searchFor(spanishOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "After disabling the '\(spanishPair)' pair, '\(spanishOnlyTerm)' (\(englishSpanishSource)) must also show ContentUnavailableView"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 4) Re-enable the Spanish pair; results must come back.
        settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: spanishPair)

        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(spanishHeadwordTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "After re-enabling the '\(spanishPair)' pair, '\(spanishHeadwordTerm)' must return results again"
        )
    }

    // MARK: - Dictionary chips on Search (Issue #145)
    //
    // The chips and the Settings switches drive one setting. "яблоко" is
    // found only while the Russian pair is on (see `russianOnlyTerm`).

    /// #146: "English off", "everything" and "only English" in one or two
    /// taps; the results follow each step without retyping.
    func testThreeCasesInOneOrTwoTaps() throws {
        let search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips(), "the chips row must show on Search")
        search.searchFor(russianOnlyTerm)
        XCTAssertTrue(search.waitForResults(), "baseline: '\(russianOnlyTerm)' with every dictionary on")

        // English off: one tap.
        search.tapChip(englishPair)
        XCTAssertEqual(search.isChipOn(englishPair), false)
        for pair in TestData.Pairs.all where pair != englishPair {
            XCTAssertEqual(search.isChipOn(pair), true, "'\(pair)' stays on")
        }
        XCTAssertFalse(search.isAllSelected(), "'All' is not selected while English is off")
        XCTAssertTrue(search.waitForResults(), "Russian is on: '\(russianOnlyTerm)' still has results")

        // Everything: one tap.
        search.tapAllChip()
        for pair in TestData.Pairs.all {
            XCTAssertEqual(search.isChipOn(pair), true, "'\(pair)' is on after 'All'")
        }
        XCTAssertTrue(search.isAllSelected())
        XCTAssertTrue(search.waitForResults())

        // Only English: long press, "Only this".
        search.onlyThis(englishPair)
        for pair in TestData.Pairs.all {
            XCTAssertEqual(search.isChipOn(pair), pair == englishPair, "'\(pair)' after 'Only this' on English")
        }
        XCTAssertFalse(search.isAllSelected())
        XCTAssertTrue(search.waitForNoResults(), "Russian is off: '\(russianOnlyTerm)' has no results")
        XCTAssertTrue(search.verifySearchFieldContains(russianOnlyTerm), "the query stays")

        // The Settings switches show the same state.
        search.clearOverlaysBeforeTabSwitch()
        let settings = tabBarPage.tapSettingsTab()
        for pair in TestData.Pairs.all {
            XCTAssertTrue(settings.waitForToggle(pair: pair), "Settings switch '\(pair)' must be reachable")
            XCTAssertEqual(settings.isDictionaryEnabled(pair: pair), pair == englishPair, "Settings switch '\(pair)'")
        }
    }

    /// #146, #145: a chip changes the Settings switch and a Settings switch
    /// changes the chip.
    func testChipAndSettingsSwitchShowTheSameState() throws {
        var search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        search.tapChip(russianPair)

        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.waitForToggle(pair: russianPair))
        XCTAssertEqual(settings.isDictionaryEnabled(pair: russianPair), false,
                       "the Russian chip turned the Settings switch off")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: spanishPair), true, "precondition")
        settings.tapToggle(pair: spanishPair)

        search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        XCTAssertEqual(search.isChipOn(spanishPair), false, "the Settings switch turned the Spanish chip off")
        XCTAssertEqual(search.isChipOn(russianPair), false)
        XCTAssertEqual(search.isChipOn(englishPair), true)
        XCTAssertFalse(search.isAllSelected())
    }

    /// #146, #145: the chips follow Dictionary Order; after a reorder in
    /// Settings they show the new order.
    func testChipsFollowDictionaryOrder() throws {
        var search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        let chipsBefore = search.chipOrder(of: TestData.Pairs.all)
        XCTAssertEqual(chipsBefore.count, TestData.Pairs.all.count, "one chip per bundled pair")

        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary order must open")
        XCTAssertTrue(settings.waitForToggle(pair: englishPair))
        let rowsBefore = settings.currentOrder(of: TestData.Pairs.all)
        XCTAssertEqual(chipsBefore, rowsBefore, "the chips follow the Dictionary Order sequence")

        let rowsAfter = settings.reorderFirstToLast(pairs: TestData.Pairs.all)
        XCTAssertNotEqual(rowsAfter, rowsBefore, "precondition: the drag reordered the list")

        search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        XCTAssertEqual(search.chipOrder(of: TestData.Pairs.all), rowsAfter, "the chips show the new order")
    }

    /// #145: a tap toggles the pair and the results refresh at once, without
    /// retyping; the query stays in the field.
    func testChipTapRefreshesResultsAtOnce() throws {
        let search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        search.searchFor(russianOnlyTerm)
        XCTAssertTrue(search.waitForResults(), "baseline: '\(russianOnlyTerm)' has results")
        XCTAssertTrue(search.searchFieldHasFocus(), "precondition: the field has the focus after typing")
        let keyboardUp = app.keyboards.firstMatch.exists

        search.tapChip(russianPair)
        XCTAssertTrue(search.waitForNoResults(), "Russian off: 'no results' without retyping")
        XCTAssertTrue(search.verifySearchFieldContains(russianOnlyTerm), "the field still holds the query")
        XCTAssertTrue(search.searchFieldHasFocus(), "the field keeps the focus after a chip tap")
        XCTAssertEqual(app.keyboards.firstMatch.exists, keyboardUp, "the keyboard stays as it was")

        search.tapChip(russianPair)
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "Russian on again: results return")
        XCTAssertTrue(search.verifySearchFieldContains(russianOnlyTerm))
    }

    /// #145: with every pair off, "Choose a dictionary" replaces the results;
    /// "All" brings them back.
    func testAllOffShowsHint() throws {
        let search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        search.searchFor(russianOnlyTerm)
        XCTAssertTrue(search.waitForResults())

        search.onlyThis(englishPair)
        search.tapChip(englishPair)
        for pair in TestData.Pairs.all {
            XCTAssertEqual(search.isChipOn(pair), false, "'\(pair)' is off")
        }
        XCTAssertTrue(search.waitForNoDictionariesHint(), "'Choose a dictionary' with every chip off")
        XCTAssertFalse(search.verifyContentUnavailableShown(), "the hint, not 'no results'")
        XCTAssertTrue(search.verifyNoResultCells(), "and no result row")

        search.tapAllChip()
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "results return after 'All'")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.Search.noDictionariesHint].exists)
    }

    /// #145, VoiceOver: a pair chip is a switch labelled with its Dictionary
    /// Order title whose value flips between 1 and 0; "All" reads "All
    /// dictionaries" and is selected only while every chip is on.
    func testChipAccessibility() throws {
        let search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        XCTAssertEqual(search.chipsRow.label, "Dictionaries", "the row is a container named 'Dictionaries'")
        XCTAssertEqual(search.chip(englishPair).label, "English", "the label is the Dictionary Order title")
        XCTAssertEqual(search.chip(russianPair).label, "Russian – English")
        XCTAssertEqual(search.allChip.label, "All dictionaries")
        XCTAssertEqual(search.chip(englishPair).elementType, .switch, "a pair chip reads as a switch")
        XCTAssertEqual(search.allChip.elementType, .button, "'All' is a button")
        XCTAssertEqual(search.isChipOn(englishPair), true, "value 1 while on")
        XCTAssertTrue(search.isAllSelected(), "'All' is selected while every chip is on")

        search.tapChip(englishPair)
        XCTAssertEqual(search.isChipOn(englishPair), false, "value 0 while off")
        XCTAssertFalse(search.isAllSelected(), "'All' is not selected while a chip is off")

        search.tapChip(englishPair)
        XCTAssertEqual(search.isChipOn(englishPair), true)
        XCTAssertTrue(search.isAllSelected())
    }

    /// #145, Dynamic Type: at the largest accessibility size the labels still
    /// fit on one line; the last chip is reached by scrolling the row and
    /// toggles.
    func testChipsAtAccessibilityTextSize() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tabBarPage = TabBarPage(app: app)

        let search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips())
        let order = search.chipOrder(of: TestData.Pairs.all)
        XCTAssertEqual(order.count, TestData.Pairs.all.count, "every chip exists")
        let last = try XCTUnwrap(order.last)
        let chip = search.chip(last)
        XCTAssertTrue(search.revealChip(chip), "the last chip is reached by scrolling the row")
        XCTAssertGreaterThan(chip.frame.height, 44, "the row grows taller with the text size")

        search.tapChip(last)
        XCTAssertEqual(search.isChipOn(last), false)
        search.tapChip(last)
        XCTAssertEqual(search.isChipOn(last), true)
    }

    /// #145 (Kirill, 2026-10-30): the row stays pinned under the search
    /// field: with an empty field, with the keyboard up, and while the
    /// results scroll under it.
    func testChipsStayPinnedUnderTheField() throws {
        let search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        let row = search.chipsRow
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: TestData.Timeouts.medium))
        // The "Dictionaries" container covers the chips only. On iOS 26 a
        // container around the scroll view started at the top of the screen,
        // over the title and the search field (#145, Kirill 2026-10-31).
        XCTAssertGreaterThanOrEqual(row.frame.minY, field.frame.maxY - 1,
                                    "empty field: the row's frame starts below the search field")

        search.searchFor("apple")
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "results for 'apple'")
        XCTAssertTrue(row.exists, "keyboard up: the row stays")
        XCTAssertGreaterThanOrEqual(row.frame.minY, field.frame.maxY - 1, "keyboard up: the row is under the field")

        search.dismissKeyboard()
        XCTAssertGreaterThanOrEqual(app.cells.element(boundBy: 0).frame.minY, row.frame.maxY - 1,
                                    "before scrolling, the first result starts under the row")
        // Pinned to the field, not to the screen: a large title (iPadOS 26)
        // collapses as the results scroll and takes the field and the row up.
        let gapToField = row.frame.minY - field.frame.maxY
        let swipeTarget = app.cells.element(boundBy: 4)
        XCTAssertTrue(swipeTarget.waitForExistence(timeout: TestData.Timeouts.medium))
        swipeTarget.swipeUp()

        XCTAssertLessThan(app.cells.element(boundBy: 0).frame.minY, row.frame.maxY - 10,
                          "precondition: the results scrolled under the row")
        XCTAssertTrue(row.exists, "the row stays while the results scroll")
        XCTAssertEqual(row.frame.minY - field.frame.maxY, gapToField, accuracy: 1,
                       "the row stays right under the field while the results scroll")
        XCTAssertGreaterThan(row.frame.minY, app.windows.firstMatch.frame.minY, "the row stays on screen")
        XCTAssertTrue(search.revealChip(search.chip(englishPair)), "the chips stay reachable")
    }

    /// #145: the chips are the stored setting, so their state survives a
    /// relaunch: a pair turned off stays off, and "All" stays all.
    func testChipStateSurvivesRelaunch() throws {
        var search = tabBarPage.tapSearchTab()
        XCTAssertTrue(search.waitForChips())
        search.tapChip(russianPair)

        relaunchKeepingData()
        search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips())
        XCTAssertEqual(search.isChipOn(russianPair), false, "Russian stays off after a relaunch")
        for pair in TestData.Pairs.all where pair != russianPair {
            XCTAssertEqual(search.isChipOn(pair), true, "'\(pair)' stays on after a relaunch")
        }
        XCTAssertFalse(search.isAllSelected())

        search.tapAllChip()
        relaunchKeepingData()
        search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips())
        XCTAssertTrue(search.isAllSelected(), "'All' stays selected after a relaunch")
        for pair in TestData.Pairs.all {
            XCTAssertEqual(search.isChipOn(pair), true, "'\(pair)' is on after 'All' and a relaunch")
        }
    }

    /// #145, 0129: the chips filter Search only. With every chip off, an
    /// empty field still lists a Recent word read in Russian, shows no hint,
    /// and the word still opens its Russian entry.
    func testRecentWordsIgnoreTheChips() throws {
        var search = tabBarPage.tapSearchTab()
        search.searchFor(russianOnlyTerm)
        XCTAssertTrue(search.waitForResults(), "'\(russianOnlyTerm)' has results")
        let read = search.tapSearchResult(at: 0)
        XCTAssertTrue(read.waitForDefinitionToLoad(), "Definition should load for '\(russianOnlyTerm)'")
        read.navigateBack()
        // A fresh launch shows the Recent words on the empty Search screen.
        relaunchKeepingData()

        search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips())
        let recent = app.staticTexts[russianOnlyTerm].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: TestData.Timeouts.long),
                      "precondition: Search lists the Recent word '\(russianOnlyTerm)'")
        search.onlyThis(englishPair)
        search.tapChip(englishPair)
        for pair in TestData.Pairs.all {
            XCTAssertEqual(search.isChipOn(pair), false, "'\(pair)' is off")
        }
        XCTAssertTrue(recent.exists, "Recent words stay with every chip off")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.Search.noDictionariesHint].exists,
                       "no hint with an empty field")

        recent.tap()
        let opened = DefinitionPage(app: app)
        XCTAssertTrue(opened.waitForDefinitionToLoad(), "the Recent word opens while Russian is off")
        XCTAssertTrue(opened.verifyDefinitionContainsText("apple"),
                      "it opens the Russian entry; got '\(opened.getDefinitionText())'")
    }

    /// Terminates and relaunches on the same data (no `-resetData`).
    private func relaunchKeepingData() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetData" }
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    /// Re-enabling a previously disabled dictionary must restore its results.
    /// Round-trip sanity check so the off→on path is exercised too.
    func testReEnablingDictionaryRestoresResults() throws {
        // 1) Disable, search, expect empty.
        var settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: russianPair)

        var searchPage = tabBarPage.tapSearchTab()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForNoResults(),
            "Search must show ContentUnavailableView while '\(russianPair)' is disabled"
        )
        searchPage.clearOverlaysBeforeTabSwitch()

        // 2) Re-enable, search again, expect results.
        settingsPage = tabBarPage.tapSettingsTab()
        settingsPage.tapToggle(pair: russianPair)

        searchPage = tabBarPage.tapSearchTab()
        searchPage.clearSearch()
        searchPage.searchFor(russianOnlyTerm)
        XCTAssertTrue(
            searchPage.waitForResults(),
            "Search must return results after '\(russianPair)' is re-enabled"
        )
    }
}

