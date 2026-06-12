import XCTest

/// WATCHPOINT 3 (Issue #6): verify XCUITest drag-to-reorder works against the
/// `DictionaryOrderView` edit-mode `List` early, before the rest of the feature
/// is built on it — XCUITest historically has friction with reorder gestures.
final class DictionaryOrderReorderTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetData"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    func testDragToReorderChangesVisibleOrder() throws {
        let settings = TabBarPage(app: app).tapSettingsTab()
        XCTAssertTrue(settings.openDictionaryOrder(),
                      "Dictionary-order link should push the order screen")

        let sources = ["wordnet", "openrussian", "freedict-eng-spa",
                       "wordnet-spa-eng", "wordnet-arb-eng"]
        let before = settings.currentOrder(of: sources)
        XCTAssertGreaterThanOrEqual(before.count, 2,
            "Need ≥2 dictionaries present to exercise reorder; got \(before)")

        let after = settings.reorderFirstToLast(sources: sources)
        XCTAssertNotEqual(after, before,
            "Drag-to-reorder must change the visible order. before=\(before) after=\(after)")
    }
}
