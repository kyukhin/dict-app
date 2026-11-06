import XCTest

/// Issues #129, #140, #237: on a fresh install Search is usable at once with
/// English, with no "Preparing dictionaries" progress; every other language
/// is a pack (0129-dictionary-file.md and 0237-downloads.md, Test plans).
///
/// `-resetDatabase` deletes the user database, `-resetPacks` the installed
/// packs and `-resetData` the preferences, which is a fresh install without
/// uninstalling (the simulator keeps its language and keyboard settings).
///
/// `testEnglishWorksWithoutPacks`: the bundle alone answers English, and no
/// other language. The first-launch sheet, the "not downloaded" hint and the
/// Languages screen of 0237's `testEnglishWorksOffline` come with #243 and
/// #245; until then the test passes `-skipWelcome`.
///
/// `testInstalledPacksSearchEveryPairAtOnce`: with every pack installed at
/// launch (`-installPacks all`, from the committed assets), five queries
/// reach all nine dictionaries. In relevance order each expected row is among
/// the first four; the result sort mode survives `-resetData`, so in
/// "Preferred dictionary first" a row can sit lower, and the test scrolls to
/// it. Timing: the Search screen within 2 s of `launch()` returning (English
/// alone; the pack install delays it), and each query's results within 2 s
/// of typing. Typing itself is not timed (it is the simulator's speed, not
/// the app's).
final class FreshInstallTests: XCTestCase {

    var app: XCUIApplication!

    /// One query per language pair and the rows it must find, as
    /// `(headword, source)`. Headwords are stored spellings (the Arabic one
    /// is vocalized, the Greek one accented).
    private static let probes: [(query: String, rows: [(word: String, source: String)])] = [
        ("dog", [("dog", TestData.Sources.wordnet),
                 ("dog", TestData.Sources.freedictEngSpa),
                 ("dog", TestData.Sources.freedictEngEll),
                 ("dog", TestData.Sources.wordnetEngEll)]),
        ("дом", [("дом", TestData.Sources.openrussian)]),
        ("casa", [("casa", TestData.Sources.wordnetSpaEng)]),
        ("كتاب", [("كِتاب", TestData.Sources.wordnetArbEng)]),
        ("γραφω", [("γράφω", TestData.Sources.freedictEllEng),
                   ("γράφω", TestData.Sources.wordnetEllEng)]),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-disableReviewPrompt", "-resetDatabase", "-resetPacks", "-resetData",
                                UITestHelpers.skipWelcome]

        // iOS 26 "Enable Dictation?" springboard alert on the first search.
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
        // Landscape no-ops swipes on the results list (Intel simulators).
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// #237: English works on a fresh install with no pack; nothing else.
    func testEnglishWorksWithoutPacks() throws {
        app.launch()
        let launched = Date()
        let searchScreen = app.descendants(matching: .any)[AccessibilityIdentifiers.TabBar.searchTab].firstMatch
        XCTAssertTrue(searchScreen.waitForExistence(timeout: TestData.Timeouts.short),
                      "the Search screen is up within 2 s of launch")
        record("Search screen", since: launched)
        XCTAssertEqual(app.progressIndicators.count, 0, "no loading progress on a fresh install's Search screen")

        let search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips(), "the dictionary chips load")
        XCTAssertTrue(search.chip(TestData.Pairs.english).exists, "English is in the bundle")
        for pair in [TestData.Pairs.spanish, TestData.Pairs.russian, TestData.Pairs.arabic, TestData.Pairs.greek] {
            XCTAssertFalse(search.chip(pair).exists, "\(pair) is not installed, so it has no chip")
        }

        search.searchFor("dog")
        let typed = Date()
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.short), "'dog' returns results within 2 s of typing")
        record("'dog' results", since: typed)
        XCTAssertTrue(findRow(word: "dog", source: TestData.Sources.wordnet), "'dog' finds WordNet's dog")
        for source in [TestData.Sources.freedictEngSpa, TestData.Sources.freedictEngEll, TestData.Sources.wordnetEngEll] {
            XCTAssertFalse(resultCell(word: "dog", source: source).exists, "no pack is installed: no \(source) row")
        }
        scrollBackToSearchField()

        search.searchFor("дом")
        XCTAssertTrue(search.waitForNoResults(timeout: TestData.Timeouts.medium), "Russian is not installed: no results")
    }

    /// #129, #140, #237: with every pack installed through the install path,
    /// every dictionary answers from the first query.
    func testInstalledPacksSearchEveryPairAtOnce() throws {
        app.launchArguments += UITestHelpers.packArguments()
        app.launch()
        let launched = Date()
        let searchScreen = app.descendants(matching: .any)[AccessibilityIdentifiers.TabBar.searchTab].firstMatch
        XCTAssertTrue(searchScreen.waitForExistence(timeout: TestData.Timeouts.launch),
                      "the Search screen is up once the packs are installed")
        record("Search screen with every pack installed", since: launched)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: TestData.Timeouts.short),
                      "the search field is up within 2 s of launch")
        XCTAssertEqual(app.progressIndicators.count, 0,
                       "no loading or unpack progress on a fresh install's Search screen")

        let search = SearchPage(app: app)
        var found: Set<String> = []
        for probe in Self.probes {
            search.searchFor(probe.query)
            let typed = Date()
            XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.short),
                          "'\(probe.query)' returns results within 2 s of typing")
            record("'\(probe.query)' results", since: typed)

            for row in probe.rows {
                if findRow(word: row.word, source: row.source) {
                    found.insert(row.source)
                } else {
                    XCTFail("'\(probe.query)' finds '\(row.word)' from \(row.source)")
                }
            }
            scrollBackToSearchField()
        }
        XCTAssertEqual(found.count, 9, "every bundled source answered on the first launch: \(found.sorted())")
        record("all five queries", since: launched)
    }

    // MARK: - Helpers

    private var results: XCUIElement { app.collectionViews.firstMatch }

    /// A result cell with headword `word` (exact label) and `source`'s badge.
    private func resultCell(word: String, source: String) -> XCUIElement {
        results.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            .containing(NSPredicate(format: "label == %@", word))
            .firstMatch
    }

    /// Whether the row is in the results, scrolling the lazy list if it is
    /// below the fold (preferred mode). The keyboard goes first, so a swipe
    /// lands on the list.
    private func findRow(word: String, source: String) -> Bool {
        let cell = resultCell(word: word, source: source)
        if cell.waitForExistence(timeout: TestData.Timeouts.short) { return true }
        app.dismissKeyboardIfPresent()
        return app.scrollToElement(cell, in: results)
    }

    /// Swipes the results back to the top until the search field is on
    /// screen again, so the next query can be typed.
    private func scrollBackToSearchField() {
        let field = app.searchFields.firstMatch
        for _ in 0..<8 {
            let frame = field.frame
            if field.exists, frame.height > 1, app.windows.firstMatch.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return
            }
            results.swipeDown()
        }
    }

    /// Adds the elapsed time to the test report, for the QA record.
    private func record(_ what: String, since start: Date) {
        let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
        XCTContext.runActivity(named: "\(what): \(seconds) s") { _ in }
        print("FreshInstallTests: \(what): \(seconds) s")
    }
}
