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
/// Settings is reached by tab **index** (Search, History, Bookmarks, Settings
/// is fixed in `ContentView`; Russian is LTR so the index is stable), because
/// `TabBarPage` falls back to the English "Settings" label.
final class DictionaryOrderDefaultTests: XCTestCase {
    private var app: XCUIApplication!

    private let settingsTabIndex = 3   // Search, History, Bookmarks, Settings

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
        // A fresh install means the one-time ~306k-row cold seed runs on this
        // launch (ProgressView until done). 120s absorbs it on the arm64 sim
        // with headroom; `ArabicLocalizationTests` uses 60s for the same wait.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 120),
                      "Tab bar must appear once the cold seed completes")

        // Precondition: the UI really is Russian, otherwise the assertion
        // below would be testing the English default by accident.
        let settingsTab = tabBar.buttons.element(boundBy: settingsTabIndex)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Settings tab (index \(settingsTabIndex)) must exist")
        XCTAssertEqual(settingsTab.label, "Настройки",
                       "UI must be Russian for this test to be meaningful (-AppleLanguages override not applied?)")
        settingsTab.tap()

        let settings = SettingsPage(app: app)
        XCTAssertTrue(settings.openDictionaryOrder(),
                      "Dictionary-order link should push the order screen")

        let sources = ["wordnet", "openrussian", "freedict-eng-spa",
                       "wordnet-spa-eng", "wordnet-arb-eng"]
        let order = settings.currentOrder(of: sources)
        XCTAssertGreaterThanOrEqual(order.count, 2,
            "Need >=2 dictionaries present to make 'first' meaningful; got \(order)")
        XCTAssertEqual(order.first, "openrussian",
            "Fresh install on a Russian device must list openrussian first; got \(order)")
        // The remaining rows must keep the count-desc base order (wordnet is the
        // largest bundled dictionary), proving this is a promotion, not a re-sort.
        XCTAssertEqual(order.dropFirst().first, "wordnet",
            "Non-promoted dictionaries must keep their count-desc order; got \(order)")
    }
}
