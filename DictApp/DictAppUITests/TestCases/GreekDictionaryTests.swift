import XCTest

/// Issue #87 — Greek ↔ English dictionaries: one "Greek – English" pair with
/// four sources (`freedict-ell-eng`, `wordnet-ell-eng`, `freedict-eng-ell`,
/// `wordnet-eng-ell`) and accent-free Greek search in both directions.
///
/// Test names and flows follow DESIGN_DOC.md §8b. Launch / interruption /
/// orientation setup mirrors `DictionaryPairGroupingTests`, plus a 120 s
/// cold-seed wait (the seed grew by ~36% rows).
///
/// - Badges are read by identifier (`AccessibilityIdentifiers.Search.sourceBadge`):
///   with a VoiceOver label set, a badge's `label` is the spoken text
///   ("Greek to English, FreeDict"), not "El–En · FD".
/// - Results may sit below the fold (`σκυλος` → "dog" from `wordnet-eng-ell`
///   is ~19th): scroll, then assert. Never bound a probe by `cells.count`
///   (lazy `List`).
/// - Definitions of the Greek sources are stored decomposed (NFD); compare
///   their text after NFC.
/// - Greek is typed through `SearchPage.searchFor`. If "search field should
///   contain typed term" fails, check the simulator's hardware-keyboard
///   setting first.
final class GreekDictionaryTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-disableReviewPrompt")
        app.launchArguments.append("-resetData")
        // The Greek (i) detail carries two ~9 KB Apache texts: as in
        // `DictionaryInfoTests`, silence the app's os_log so XCTest's log
        // volume cannot crash the app under test on the iOS 17.5 sim.
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
        // A fresh install copies ~417k seed rows before the tab bar appears.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 120),
                      "tab bar after the cold seed")
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Tests

    /// `καλημέρα` and `καλημερα` → `καλημέρα` with a Greek → English badge.
    func testGreekWordFoundWithAndWithoutTonos() throws {
        let search = isolateGreekPair()
        for query in ["καλημέρα", "καλημερα"] {
            search.clearSearch()
            search.searchFor(query)
            XCTAssertTrue(search.waitForResults(), "'\(query)' must return results")
            XCTAssertTrue(waitForCell(word: "καλημέρα", source: TestData.Sources.freedictEllEng),
                          "'\(query)' must find καλημέρα (El–En · FD)")
            XCTAssertTrue(waitForCell(word: "καλημέρα", source: TestData.Sources.wordnetEllEng),
                          "'\(query)' must find καλημέρα (El–En · WN)")
            waitForFirstResult(word: "καλημέρα", sources: [TestData.Sources.freedictEllEng, TestData.Sources.wordnetEllEng],
                               query: query)
        }
    }

    /// `λογοσ` and `ΛΟΓΟΣ` → `λόγος` (final sigma typed as σ, all caps).
    func testFinalSigmaAndCaseVariantsMatch() throws {
        let search = isolateGreekPair()
        for query in ["λογοσ", "ΛΟΓΟΣ"] {
            search.clearSearch()
            search.searchFor(query)
            XCTAssertTrue(search.waitForResults(), "'\(query)' must return results")
            waitForFirstResult(word: "λόγος", sources: [TestData.Sources.freedictEllEng, TestData.Sources.wordnetEllEng],
                               query: query)
            XCTAssertTrue(waitForCell(word: "λόγος", source: TestData.Sources.wordnetEllEng),
                          "'\(query)' must also find the WordNet λόγος")
        }
    }

    /// `σκυλος` → a cell "dog" with `source_badge_freedict-eng-ell` AND a cell
    /// "dog" with `source_badge_wordnet-eng-ell`, plus `σκύλος` with a
    /// Greek → English badge. Repeat with `σκύλος`. Scroll, then assert.
    func testAccentFreeGreekFindsEnglishToGreekEntries() throws {
        let search = isolateGreekPair()
        for query in ["σκυλος", "σκύλος"] {
            search.clearSearch()
            search.searchFor(query)
            XCTAssertTrue(search.waitForResults(), "'\(query)' must return results")
            waitForFirstResult(word: "σκύλος", sources: [TestData.Sources.freedictEllEng, TestData.Sources.wordnetEllEng],
                               query: query)
            XCTAssertTrue(waitForCell(word: "σκύλος", source: TestData.Sources.wordnetEllEng),
                          "'\(query)' must find σκύλος (El–En · WN)")
            search.dismissKeyboard()
            for source in [TestData.Sources.freedictEngEll, TestData.Sources.wordnetEngEll] {
                let dog = resultCell(word: "dog", source: source)
                XCTAssertTrue(app.scrollToElement(dog),
                              "'\(query)' must find \"dog\" from \(source) through the Greek in its definition")
            }
            scrollResultsToTop(showing: resultCell(word: "σκύλος", source: TestData.Sources.freedictEllEng))
        }
    }

    /// `γρηγορα` → first result `γρήγορα` with `source_badge_freedict-ell-eng`;
    /// the row and the definition view show "quickly".
    func testWordOnlyInFreeDictGreekToEnglish() throws {
        let search = isolateGreekPair()
        search.searchFor("γρηγορα")
        XCTAssertTrue(search.waitForResults(), "'γρηγορα' must return results")
        waitForFirstResult(word: "γρήγορα", sources: [TestData.Sources.freedictEllEng], query: "γρηγορα")
        XCTAssertTrue(search.verifyResultContainsText("quickly", at: 0), "the row snippet shows the translation")

        let definition = search.tapSearchResult(at: 0)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "definition view must load")
        XCTAssertTrue(app.navigationBars["γρήγορα"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "definition title is the accented headword")
        XCTAssertTrue(nfc(definition.getDefinitionText()).contains("quickly"),
                      "definition shows 'quickly'; got '\(definition.getDefinitionText())'")
    }

    /// `tomorrow` → first result "tomorrow" with `source_badge_freedict-eng-ell`;
    /// the definition shows `αύριο` (stored decomposed, compared after NFC).
    /// OMW `eng-ell` has no "tomorrow".
    func testWordOnlyInFreeDictEnglishToGreek() throws {
        let search = isolateGreekPair()
        search.searchFor("tomorrow")
        XCTAssertTrue(search.waitForResults(), "'tomorrow' must return results")
        waitForFirstResult(word: "tomorrow", sources: [TestData.Sources.freedictEngEll], query: "tomorrow")
        XCTAssertFalse(resultCell(word: "tomorrow", source: TestData.Sources.wordnetEngEll).exists,
                       "Greek WordNet has no 'tomorrow' headword")

        let definition = search.tapSearchResult(at: 0)
        XCTAssertTrue(definition.waitForDefinitionToLoad(), "definition view must load")
        let text = nfc(definition.getDefinitionText())
        XCTAssertTrue(text.contains("αύριο"), "definition shows αύριο (NFD renders as NFC); got '\(text)'")
    }

    /// English UI: badge labels are the spoken text, not the abbreviation:
    /// `freedict-eng-ell` == "English to Greek, FreeDict", `freedict-ell-eng`
    /// == "Greek to English, FreeDict", `wordnet-ell-eng` == "Greek to
    /// English, WordNet".
    func testBadgeVoiceOverLabels() throws {
        let search = isolateGreekPair()
        search.searchFor("tomorrow")
        XCTAssertTrue(search.waitForResults())
        waitForFirstResult(word: "tomorrow", sources: [TestData.Sources.freedictEngEll], query: "tomorrow")
        XCTAssertEqual(badge(in: firstCell, source: TestData.Sources.freedictEngEll).label, "English to Greek, FreeDict")

        search.clearSearch()
        search.searchFor("καλημερα")
        XCTAssertTrue(search.waitForResults())
        XCTAssertTrue(waitForCell(word: "καλημέρα", source: TestData.Sources.freedictEllEng))
        let fd = badge(in: resultCell(word: "καλημέρα", source: TestData.Sources.freedictEllEng),
                       source: TestData.Sources.freedictEllEng)
        XCTAssertEqual(fd.label, "Greek to English, FreeDict")
        XCTAssertTrue(waitForCell(word: "καλημέρα", source: TestData.Sources.wordnetEllEng))
        let wn = badge(in: resultCell(word: "καλημέρα", source: TestData.Sources.wordnetEllEng),
                       source: TestData.Sources.wordnetEllEng)
        XCTAssertEqual(wn.label, "Greek to English, WordNet")
        XCTAssertNotEqual(fd.label, "El\u{2013}En \u{00B7} FD", "VoiceOver must not read the abbreviation")
    }

    /// No isolation (the other pairs stay ON):
    /// - `dictionary_order_row_ell-eng` titled "Greek – English", one switch
    ///   `dictionary_toggle_ell-eng`, no per-source Greek rows;
    /// - (i) shows the four blocks in §5.1 order (`TestData.Pairs.sources[greek]`)
    ///   with directions and licenses (Attribution-ShareAlike ×2, Apache ×2);
    /// - switching the Greek pair off removes all four Greek sources from the
    ///   `σκυλος` and `tomorrow` searches, while `tomorrow` still returns the
    ///   `wordnet` English row.
    func testGreekPairRowToggleAndInfo() throws {
        let greek = TestData.Pairs.greek
        let settings = tabBarPage.tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder())

        // 1) One row, one switch.
        let row = app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: greek)].firstMatch
        XCTAssertTrue(app.scrollToElement(row), "Greek pair row must be on the order screen")
        XCTAssertEqual(row.label, "Greek \u{2013} English")
        let greekSwitches = app.switches.matching(identifier: AccessibilityIdentifiers.Settings.dictionaryToggle(pair: greek))
        XCTAssertEqual(greekSwitches.count, 1, "one switch for all four Greek sources")
        XCTAssertEqual(settings.isDictionaryEnabled(pair: greek), true, "Greek ON after -resetData")
        for source in greekSources {
            XCTAssertFalse(app.staticTexts[AccessibilityIdentifiers.Settings.dictionaryOrderRow(pair: source)].exists,
                           "no per-source row for \(source)")
            XCTAssertFalse(app.switches[AccessibilityIdentifiers.Settings.dictionaryToggle(pair: source)].exists,
                           "no per-source switch for \(source)")
        }

        // 2) (i) detail: four blocks in order, each with direction and license.
        let info = settings.openInfo(pair: greek)
        XCTAssertTrue(info.view.exists, "(i) on Greek – English must push the info detail")
        XCTAssertTrue(app.navigationBars["Greek \u{2013} English"].waitForExistence(timeout: TestData.Timeouts.medium))
        let ids = AccessibilityIdentifiers.DictionaryInfo.self
        let expected: [(source: String, brand: String, direction: String, license: [String])] = [
            (TestData.Sources.freedictEllEng, "FreeDict", "Greek \u{2192} English", ["Attribution-ShareAlike 3.0", "Wiktionary"]),
            (TestData.Sources.wordnetEllEng, "WordNet", "Greek \u{2192} English", ["Apache License", "Version 2.0"]),
            (TestData.Sources.freedictEngEll, "FreeDict", "English \u{2192} Greek", ["Attribution-ShareAlike 3.0", "Freelang"]),
            (TestData.Sources.wordnetEngEll, "WordNet", "English \u{2192} Greek", ["Apache License", "Version 2.0"]),
        ]
        XCTAssertEqual(expected.map(\.source), greekSources, "TestData lists the Greek sources in detail order")
        var previousHeader: XCUIElement?
        for block in expected {
            let header = info.element(ids.sourceHeader(block.source))
            XCTAssertTrue(info.revealElement(ids.sourceHeader(block.source)), "block for \(block.source)")
            XCTAssertEqual(header.label, block.brand, "\(block.source) header")
            // Anything still on screen from the previous block sits above it.
            if let previousHeader, previousHeader.exists {
                XCTAssertLessThan(previousHeader.frame.minY, header.frame.minY, "\(block.source) comes after the previous block")
            }
            XCTAssertTrue(info.revealElement(ids.direction(block.source)))
            XCTAssertEqual(info.element(ids.direction(block.source)).label, block.direction, "\(block.source) direction")
            XCTAssertTrue(info.revealElement(ids.license(block.source)), "license of \(block.source) must be reachable")
            let license = info.element(ids.license(block.source)).label
            for part in block.license {
                XCTAssertTrue(license.contains(part), "\(block.source) license must contain '\(part)'; got '\(license.prefix(120))'")
            }
            previousHeader = header
        }
        for other in Set(TestData.Pairs.sources.values.joined()).subtracting(greekSources) {
            XCTAssertFalse(info.element(ids.sourceHeader(other)).exists, "Greek detail must not list '\(other)'")
        }
        info.goBack()

        // 3) Baseline search with every pair ON.
        var search = tabBarPage.tapSearchTab()
        search.searchFor("tomorrow")
        XCTAssertTrue(search.waitForResults())
        XCTAssertTrue(waitForCell(word: "tomorrow", source: TestData.Sources.freedictEngEll),
                      "baseline: the Greek 'tomorrow' row is listed")
        search.clearOverlaysBeforeTabSwitch()

        // 4) ONE toggle switches the whole Greek pair off.
        let settingsAgain = tabBarPage.tapSettingsTab()
        settingsAgain.tapToggle(pair: greek)
        XCTAssertEqual(settingsAgain.isDictionaryEnabled(pair: greek), false)

        // 5) Greek-only text has no source left; 'tomorrow' falls back to the
        //    other dictionaries with no Greek badge in sight.
        search = tabBarPage.tapSearchTab()
        search.clearSearch()
        search.searchFor("σκυλος")
        XCTAssertTrue(search.waitForNoResults(), "with Greek off, σκυλος has no result anywhere")
        search.clearSearch()
        search.searchFor("tomorrow")
        XCTAssertTrue(search.waitForResults(), "'tomorrow' still has non-Greek results")
        XCTAssertTrue(waitForCell(word: "tomorrow", source: TestData.Sources.wordnet), "the English WordNet row remains")
        for source in greekSources {
            let badges = app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            XCTAssertEqual(badges.count, 0, "no \(source) badge once the Greek pair is off")
        }
    }

    // MARK: - Helpers

    /// The Greek pair's sources, in (i) detail order.
    private let greekSources = TestData.Pairs.sources[TestData.Pairs.greek] ?? []

    /// Switches off every pair but Greek (`eng`, `eng-rus`, `eng-spa`,
    /// `arb-eng`) so Greek and English probes surface only Greek rows, then
    /// returns to the Search tab.
    @discardableResult
    private func isolateGreekPair() -> SearchPage {
        let settings = tabBarPage.tapSettingsTab()
        for pair in TestData.Pairs.all where pair != TestData.Pairs.greek {
            settings.tapToggle(pair: pair)
        }
        return tabBarPage.tapSearchTab()
    }

    private var resultsContainer: XCUIElement { app.collectionViews.firstMatch }

    private var firstCell: XCUIElement { resultsContainer.cells.element(boundBy: 0) }

    /// A result cell with headword `word` (exact label) and `source`'s badge.
    private func resultCell(word: String, source: String) -> XCUIElement {
        resultsContainer.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            .containing(NSPredicate(format: "label == %@", word))
            .firstMatch
    }

    private func badge(in cell: XCUIElement, source: String) -> XCUIElement {
        cell.descendants(matching: .any)[AccessibilityIdentifiers.Search.sourceBadge(source: source)].firstMatch
    }

    private func waitForCell(word: String, source: String, timeout: TimeInterval = 10) -> Bool {
        resultCell(word: word, source: source).waitForExistence(timeout: timeout)
    }

    /// Polls until the first result row is `word` with one of `sources`'
    /// badges: right after typing, the list can still show a partial query's
    /// results for one debounce cycle.
    private func waitForFirstResult(word: String, sources: [String], query: String, timeout: TimeInterval = 10,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var matched = false
        repeat {
            let cell = firstCell
            matched = cell.exists
                && cell.staticTexts.matching(NSPredicate(format: "label == %@", word)).count > 0
                && sources.contains { badge(in: cell, source: $0).exists }
            if matched { break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        XCTAssertTrue(matched, "'\(query)': first result must be '\(word)' from \(sources)", file: file, line: line)
    }

    /// Swipes the (lazy) results list back down until `top` — the row that
    /// heads the list — is on screen again, so the next search's
    /// `firstCell` is really row 0 and not the first still-materialised row.
    private func scrollResultsToTop(showing top: XCUIElement) {
        for _ in 0..<8 {
            if top.exists, top.frame.height > 1, top.frame.minY >= resultsContainer.frame.minY - 1 { return }
            resultsContainer.swipeDown()
        }
    }

    private func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
}
