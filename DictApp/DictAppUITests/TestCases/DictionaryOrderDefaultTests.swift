import XCTest

/// Issue #74 acceptance criterion: on a fresh install with the device language
/// set to Russian, Settings → Dictionary Order must list `openrussian` first.
///
/// Launch strategy mirrors `ArabicLocalizationTests`: the UI language is driven
/// by `-AppleLanguages ("ru")`. `-resetData` clears both the persisted in-app
/// language choice (`ui_language`, left behind by picker-driven suites) and the
/// persisted dictionary order (#74), so the first-launch default is re-derived
/// even after an earlier suite picked a language or reordered the list.
///
/// Settings is reached through `app.tabButton(.settings)`: by index in a tab
/// bar (the order is fixed in `ContentView`; Russian is LTR so it is stable),
/// by SF Symbol on the iPadOS 26 tab strip. Never by the localized label.
final class DictionaryOrderDefaultTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetData", "-disableReviewPrompt"]
        app.launchArguments += ["-AppleLanguages", "(ru)"]
        app.launchArguments += ["-AppleLocale", "ru"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testFreshRussianInstallListsOpenRussianFirst() throws {
        // The order is read once the Search screen is up.
        XCTAssertTrue(app.waitForDictionariesReady(),
                      "Search screen after launch")
        // Precondition: the UI really is Russian, otherwise the assertion
        // below would be testing the English default by accident.
        let settingsTab = app.tabButton(.settings)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Settings tab must exist")
        XCTAssertEqual(settingsTab.label, "Настройки",
                       "UI must be Russian for this test to be meaningful (-AppleLanguages override not applied?)")
        settingsTab.tap()

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(),
                      "Dictionary-order link should push the order screen")

        // Issue #92: rows are language pairs (`eng-rus` = openrussian, `eng` = wordnet).
        let order = settings.currentOrder(of: TestData.Pairs.all)
        XCTAssertGreaterThanOrEqual(order.count, 2,
            "Need >=2 dictionaries present to make 'first' meaningful; got \(order)")
        XCTAssertEqual(order.first, TestData.Pairs.russian,
            "Fresh install on a Russian device must list the Russian – English pair first; got \(order)")
        // The remaining rows must keep the count-desc base order (wordnet is the
        // largest bundled dictionary), proving this is a promotion, not a re-sort.
        XCTAssertEqual(order.dropFirst().first, TestData.Pairs.english,
            "Non-promoted dictionaries must keep their count-desc order; got \(order)")
    }
}
