import XCTest

/// Issue #6 UI coverage: result-sort picker, per-source colour stripe (asserted
/// by AX id, badge stays present), and reorder → preferred-search-order.
final class SearchHighlightTests: XCTestCase {
    private var app: XCUIApplication!

    private let seedSources = ["wordnet", "openrussian", "freedict-eng-spa",
                               "wordnet-spa-eng", "wordnet-arb-eng"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetData", "-disableReviewPrompt"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    private var sortModePicker: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Settings.resultSortModePicker)
            .firstMatch
    }

    func testResultSortModePickerPresent() throws {
        _ = TabBarPage(app: app).tapSettingsTab()
        XCTAssertTrue(sortModePicker.waitForExistence(timeout: TestData.Timeouts.long),
                      "Result-sort picker must be present in Settings")
    }

    /// §4d / §7: every result row exposes a `source_stripe_<source>` element,
    /// and the source badge (primary signal) is still rendered.
    func testSearchResultsExposeSourceStripe() throws {
        let search = TabBarPage(app: app).tapSearchTab()
        search.searchFor("book")
        XCTAssertTrue(search.waitForResults(), "Results should appear for 'book'")

        let anyStripe = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "source_stripe_"))
            .firstMatch
        XCTAssertTrue(anyStripe.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Each result row must expose a source_stripe_<source> element (§7)")

        // Badge text stays the primary, spoken identity (§4d): a source badge
        // must be on screen alongside the stripe. ('book' surfaces WordNet
        // and/or the Arabic translation, depending on FTS ranking.)
        let badges = ["WordNet", "OpenRussian", "En–Es", "Es–En", "Ar–En"]
        let anyBadge = badges.contains { app.staticTexts[$0].firstMatch.exists }
        XCTAssertTrue(anyBadge,
                      "A source badge (primary signal) must remain present (color is secondary)")
    }

    /// §7: reordering dictionaries changes the preferred-mode result order on a
    /// known seed. Build on the verified reorder gesture (DictionaryOrderReorderTests).
    func testReorderChangesPreferredSearchTopResult() throws {
        let tabBar = TabBarPage(app: app)
        let settings = tabBar.tapSettingsTab()

        // Switch to "Preferred dictionary first".
        XCTAssertTrue(sortModePicker.waitForExistence(timeout: TestData.Timeouts.long))
        sortModePicker.tap()
        let preferred = app.staticTexts["Preferred dictionary first"]
        let preferredBtn = app.buttons["Preferred dictionary first"]
        if preferredBtn.waitForExistence(timeout: 3) { preferredBtn.tap() }
        else if preferred.waitForExistence(timeout: 3) { preferred.tap() }
        else { XCTFail("Could not find the 'Preferred dictionary first' option") }

        // Open the order list, move the first dictionary to the end so a new
        // dictionary becomes first.
        XCTAssertTrue(settings.openDictionaryOrder(), "Open dictionary order")
        let before = settings.currentOrder(of: seedSources)
        XCTAssertGreaterThanOrEqual(before.count, 2, "Need ≥2 dictionaries; got \(before)")
        let after = settings.reorderFirstToLast(sources: seedSources)
        XCTAssertNotEqual(before, after, "Reorder must change the visible order")
        let newFirst = after[0]

        // Search a broad term that matches multiple dictionaries; the FIRST
        // result's stripe must be the now-first dictionary. Scoping to the
        // first cell — not "anywhere in the results" — is the only assertion
        // shape that actually validates the top-result preferred-ordering
        // contract (#6 review): an "appears anywhere" check would pass even
        // if preferred-first silently regressed to relevance ordering and
        // the source merely showed up later in the tail.
        let search = tabBar.tapSearchTab()
        search.searchFor("a")
        XCTAssertTrue(search.waitForResults(), "Results should appear")
        let firstResultCell = app.cells.firstMatch
        XCTAssertTrue(firstResultCell.waitForExistence(timeout: TestData.Timeouts.medium),
                      "First result cell must exist")
        let firstCellStripe = firstResultCell.descendants(matching: .any)
            .matching(identifier: "source_stripe_\(newFirst)").firstMatch
        XCTAssertTrue(firstCellStripe.exists,
                      "After reorder, the FIRST result's stripe must be source_stripe_\(newFirst) (top-result preferred-ordering contract); first cell did not contain it")
    }
}
