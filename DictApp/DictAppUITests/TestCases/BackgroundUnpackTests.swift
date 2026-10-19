import XCTest

/// Issue #111 — instant start: the bundled dictionaries are unpacked in the
/// background, with a "Preparing dictionaries… N%" bar at the bottom of Search
/// (`AccessibilityIdentifiers.Search.dictionaryUnpackProgress`).
///
/// DESIGN_DOC_111 §7.4. Every test starts from a fresh database with
/// `-resetDatabase -resetData -disableReviewPrompt`: `-resetDatabase` deletes
/// the app database before setup (a fresh install without uninstalling).
/// `-unpackSourceDelay <s>` holds the unpack between sources so mid-unpack
/// states last long enough to assert on. Both hooks are DEBUG-only.
///
/// The 5 s launch target is measured separately (median of 3, fresh install);
/// here the launch is guarded at 10 s so the suite stays stable on slow hosts.
final class BackgroundUnpackTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Force portrait — sim orientation persists across sessions on Intel x86_64.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Launches a fresh install with `extraArguments` (e.g. a source delay).
    private func launchFreshInstall(_ extraArguments: [String] = []) {
        app.launchArguments = ["-resetDatabase", "-resetData", "-disableReviewPrompt"] + extraArguments
        app.launch()
    }

    private var unpackProgress: XCUIElement {
        app.descendants(matching: .any)[AccessibilityIdentifiers.Search.dictionaryUnpackProgress]
    }

    private var searchField: XCUIElement { app.searchFields.firstMatch }

    /// The bar's value as a whole percent (Latin digits), `nil` when the bar
    /// is gone or its value has none.
    private func currentPercent() -> Int? {
        guard unpackProgress.exists, let value = unpackProgress.value as? String else { return nil }
        return Int(value.filter { $0.isASCII && $0.isNumber })
    }

    /// Polls the bar until its percent satisfies `condition`, recording every
    /// value seen. Returns the matching value, or `nil` on timeout or when the
    /// bar goes away first.
    private func waitForPercent(timeout: TimeInterval = 60, seen: inout [Int],
                                _ condition: (Int) -> Bool) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard unpackProgress.exists else { return nil }
            if let percent = currentPercent() {
                if seen.last != percent { seen.append(percent) }
                if condition(percent) { return percent }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    /// A result cell with headword `word` (exact label) and `source`'s badge.
    private func resultCell(word: String, source: String) -> XCUIElement {
        resultCells(word: word, source: source).firstMatch
    }

    private func resultCells(word: String, source: String) -> XCUIElementQuery {
        app.collectionViews.firstMatch.cells
            .containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source))
            .containing(NSPredicate(format: "label == %@", word))
    }

    // MARK: - Tests

    /// A fresh install shows the Search screen at once (guard 10 s), with the
    /// bar on its first frame ("Preparing dictionaries…", a whole percent).
    /// The bar disappears once every dictionary is in; then `καλημέρα` finds a
    /// late source (`freedict-ell-eng`). A warm relaunch never shows the bar.
    func testColdLaunchShowsSearchQuickly() throws {
        let start = Date()
        launchFreshInstall()
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.long),
                      "Search screen within 10 s of a fresh-install launch")
        let launchToSearch = Date().timeIntervalSince(start)
        XCTAssertTrue(unpackProgress.exists, "the bar is on the first Search frame of a fresh install")
        XCTAssertEqual(unpackProgress.label, "Preparing dictionaries…")
        let value = unpackProgress.value as? String ?? ""
        XCTAssertNotNil(value.range(of: #"^\d{1,3}%$"#, options: .regularExpression),
                        "the value is a whole percent; got '\(value)'")

        XCTAssertTrue(unpackProgress.waitForNonExistence(timeout: TestData.Timeouts.dictionariesReady),
                      "the bar disappears once every dictionary is unpacked")
        print("⏱ fresh install: launch → Search \(String(format: "%.2f", launchToSearch)) s, "
              + "launch → bar gone \(String(format: "%.2f", Date().timeIntervalSince(start))) s")

        let search = SearchPage(app: app)
        search.searchFor("καλημέρα")
        XCTAssertTrue(search.waitForResults(), "'καλημέρα' must return results")
        XCTAssertTrue(resultCell(word: "καλημέρα", source: TestData.Sources.freedictEllEng)
                        .waitForExistence(timeout: TestData.Timeouts.long),
                      "a source from the end of the order is searchable once the bar is gone")

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"]
        app.launch()
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.launch), "Search screen on relaunch")
        XCTAssertFalse(unpackProgress.waitForExistence(timeout: TestData.Timeouts.short),
                       "a normal launch never shows the bar")
    }

    /// `-unpackSourceDelay 4`: once `wordnet` has landed (value above 0%),
    /// `apple` returns the WordNet row while the bar is still up. When
    /// `freedict-eng-spa` lands later, its "apple" row fills in without
    /// retyping (PM decision 3). The value only ever rises.
    func testSearchWorksMidUnpack() throws {
        launchFreshInstall(["-unpackSourceDelay", "4"])
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.launch), "Search screen")
        XCTAssertTrue(unpackProgress.waitForExistence(timeout: TestData.Timeouts.short), "bar shown")
        var seen: [Int] = []
        let landed = waitForPercent(seen: &seen) { $0 > 0 }
        XCTAssertNotNil(landed, "the first dictionary (wordnet) must land; values seen \(seen)")

        let search = SearchPage(app: app)
        search.searchFor("apple")
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "results mid-unpack")
        XCTAssertTrue(resultCell(word: "apple", source: TestData.Sources.wordnet)
                        .waitForExistence(timeout: TestData.Timeouts.long),
                      "WordNet answers mid-unpack")
        XCTAssertTrue(unpackProgress.exists, "…while the bar is still up")
        XCTAssertFalse(resultCell(word: "apple", source: TestData.Sources.freedictEngSpa).exists,
                       "precondition: the English–Spanish dictionary has not landed yet")

        XCTAssertTrue(resultCell(word: "apple", source: TestData.Sources.freedictEngSpa)
                        .waitForExistence(timeout: 45),
                      "a dictionary that lands re-runs the current search, no retyping")
        XCTAssertTrue(resultCell(word: "apple", source: TestData.Sources.wordnet).exists,
                      "the WordNet row stays")
        _ = waitForPercent(timeout: 5, seen: &seen) { _ in false }
        XCTAssertEqual(seen, seen.sorted(), "the percentage never goes back; got \(seen)")
        XCTAssertTrue(unpackProgress.waitForNonExistence(timeout: TestData.Timeouts.dictionariesReady),
                      "the bar disappears at the end")
    }

    /// `-unpackSourceDelay 4`: record a value above 0%, terminate, relaunch
    /// without `-resetDatabase` and without delay. The bar starts at or above
    /// the recorded value, then disappears; `яблоко` returns an `openrussian`
    /// row and `apple` shows exactly one WordNet "apple" row.
    func testKillAndResume() throws {
        launchFreshInstall(["-unpackSourceDelay", "4"])
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.launch), "Search screen")
        var seen: [Int] = []
        let recorded = try XCTUnwrap(waitForPercent(seen: &seen) { $0 > 0 },
                                     "the first dictionary must land before the kill; values seen \(seen)")
        app.terminate()

        app.launchArguments = ["-disableReviewPrompt"]
        app.launch()
        XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.launch), "Search screen after relaunch")
        let resumedAt = try XCTUnwrap(currentPercent(), "the relaunch resumes the unpack with the bar up")
        XCTAssertGreaterThanOrEqual(resumedAt, recorded, "progress resumes where the killed launch stopped")
        XCTAssertTrue(unpackProgress.waitForNonExistence(timeout: TestData.Timeouts.dictionariesReady),
                      "the resumed unpack finishes")

        let search = SearchPage(app: app)
        search.searchFor("яблоко")
        XCTAssertTrue(search.waitForResults(), "'яблоко' must return results")
        XCTAssertTrue(resultCell(word: "яблоко", source: TestData.Sources.openrussian)
                        .waitForExistence(timeout: TestData.Timeouts.long),
                      "a dictionary pending at the kill arrived after the resume")

        search.clearSearch()
        search.searchFor("apple")
        XCTAssertTrue(search.waitForResults(), "'apple' must return results")
        XCTAssertTrue(resultCell(word: "apple", source: TestData.Sources.wordnet)
                        .waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertEqual(resultCells(word: "apple", source: TestData.Sources.wordnet).count, 1,
                       "the dictionary committed before the kill is not imported twice")
    }

    /// The bar's label is localized in every shipped UI language other than
    /// English (checked above); RTL Arabic included. `-unpackSourceDelay 4`
    /// keeps it up long enough to read.
    func testIndicatorIsLocalized() throws {
        let expected = [
            ("ru", "Подготовка словарей…"),
            ("es", "Preparando diccionarios…"),
            ("ar", "جارٍ تجهيز القواميس…"),
            ("el", "Προετοιμασία λεξικών…"),
        ]
        for (code, title) in expected {
            app.terminate()
            launchFreshInstall(["-unpackSourceDelay", "4", "-AppleLanguages", "(\(code))", "-AppleLocale", code])
            XCTAssertTrue(searchField.waitForExistence(timeout: TestData.Timeouts.launch), "\(code): Search screen")
            XCTAssertTrue(unpackProgress.waitForExistence(timeout: TestData.Timeouts.short), "\(code): bar shown")
            XCTAssertEqual(unpackProgress.label, title, "\(code): localized title")
            let value = unpackProgress.value as? String ?? ""
            XCTAssertFalse(value.isEmpty, "\(code): the bar carries a percentage")
            print("\(code): '\(unpackProgress.label)' value '\(value)'")
        }
    }
}
