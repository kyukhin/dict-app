import XCTest

/// Issues #129, #140: on a fresh install Search is usable at once and every
/// bundled dictionary is searchable from the first query, with no
/// "Preparing dictionaries" progress (0129-dictionary-file.md, Test plan).
///
/// `-resetDatabase` deletes the user database and `-resetData` the
/// preferences, which is a fresh install without uninstalling (the simulator
/// keeps its language and keyboard settings).
///
/// Five queries reach all nine bundled sources. In relevance order each
/// expected row is among the first four; the result sort mode survives
/// `-resetData`, so in "Preferred dictionary first" a row can sit lower, and
/// the test scrolls to it. Timing: the Search screen within 2 s of
/// `launch()` returning, and each query's results within 2 s of typing.
/// Typing itself is not timed (it is the simulator's speed, not the app's).
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
        app.launchArguments += ["-disableReviewPrompt", "-resetDatabase", "-resetData"]

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

    func testFreshInstallSearchesEveryPairAtOnce() throws {
        app.launch()
        let launched = Date()
        let searchScreen = app.descendants(matching: .any)[AccessibilityIdentifiers.TabBar.searchTab].firstMatch
        XCTAssertTrue(searchScreen.waitForExistence(timeout: TestData.Timeouts.short),
                      "the Search screen is up within 2 s of launch")
        record("Search screen", since: launched)
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
