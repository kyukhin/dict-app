import XCTest

/// UI coverage for Issue #23: the app must present a fully localized
/// Spanish interface when the user selects Español.
///
/// We drive the language switch through the in-app picker
/// (`ui_language_link` → `ui_language_option_es`) rather than the
/// `-AppleLanguages (es)` launch argument. Two reasons:
///   1. The app resolves its UI language through `LocalizationManager`
///      (persisted preference → device language → English), applied via
///      `.environment(\.locale)` + a root `.id(...)` rebuild — the picker
///      is the real mechanism users (and the app) use.
///   2. `LocalizationManager.shared` reads the persisted preference at
///      init, before any launch-time reset could run, so a launch
///      argument can't reliably override a previously-persisted choice.
///
/// Tab navigation here is intentionally **by index**, not via `TabBarPage`:
/// the tab-bar buttons carry no `*_tab` accessibility identifier (those
/// live on each tab's content container), so `TabBarPage` falls back to
/// matching the English label "Settings" — which breaks the moment the UI
/// is in Spanish. The tab order (Search, History, Bookmarks, Settings) is
/// fixed in `ContentView`, so index 3 is always Settings regardless of
/// language.
///
/// Every test restores English in `tearDown` so a persisted Spanish
/// selection can't bleed into suites that assert on English labels.
final class SpanishLocalizationTests: XCTestCase {

    private var app: XCUIApplication!

    private let settingsTabIndex = 3   // Search, History, Bookmarks, Settings

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-resetData")
        app.launch()
    }

    override func tearDownWithError() throws {
        // Leave the app in English for the next suite. Guard on app state
        // so a crashed/closed app doesn't make teardown itself fail.
        if let app, app.state == .runningForeground {
            _ = selectLanguage(code: "en")
        }
        app = nil
    }

    // MARK: - Tests

    /// The picker must offer "Español" (by its native name) alongside the
    /// other shipped languages, and selecting it must flip the whole UI to
    /// Spanish — proven by the Settings tab reading "Ajustes".
    func testLanguagePickerOffersSpanish() throws {
        openLanguagePicker()

        let esOption = option(for: "es")
        XCTAssertTrue(esOption.waitForExistence(timeout: 5),
                      "Picker must offer a Spanish ('es') option")
        XCTAssertTrue(app.staticTexts["Español"].exists,
                      "The Spanish option must display its native name 'Español'")
        // The other two shipped languages must remain on offer. Wait
        // rather than probe immediately — the pushed picker list can
        // still be materialising on slower CI devices.
        XCTAssertTrue(option(for: "en").waitForExistence(timeout: 5), "Picker must still offer English")
        XCTAssertTrue(option(for: "ru").waitForExistence(timeout: 5), "Picker must still offer Russian")

        // Selecting Spanish must switch the interface.
        esOption.tap()
        XCTAssertTrue(
            tabButton(label: "Ajustes").waitForExistence(timeout: 5),
            "After selecting Español, the tab bar must localize (Settings → 'Ajustes')"
        )
    }

    /// The tab bar must read its Spanish labels once Spanish is selected,
    /// with no English labels left behind.
    func testTabBarIsLocalizedInSpanish() throws {
        XCTAssertTrue(selectLanguage(code: "es"),
                      "Must be able to switch to Spanish via the picker")

        for spanish in ["Buscar", "Historial", "Marcadores", "Ajustes"] {
            XCTAssertTrue(
                tabButton(label: spanish).waitForExistence(timeout: 5),
                "Tab bar must show the Spanish label '\(spanish)'"
            )
        }
        // No English leakage in the tab bar. Wait for each old English button
        // to disappear rather than sampling immediately — the `.id(lang)`
        // rebuild can still be tearing down the previous tree, so an instant
        // `.exists` check can catch a button mid-transition.
        let gone = NSPredicate(format: "exists == FALSE")
        for english in ["Search", "History", "Bookmarks", "Settings"] {
            expectation(for: gone, evaluatedWith: tabButton(label: english), handler: nil)
        }
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "English tab labels must disappear in the Spanish UI")
        }
    }

    /// The Settings screen must render Spanish chrome: the navigation
    /// title "Ajustes", the language row labeled "Idioma", and the
    /// "Diccionarios" section header.
    func testSettingsScreenIsLocalizedInSpanish() throws {
        XCTAssertTrue(selectLanguage(code: "es"),
                      "Must be able to switch to Spanish via the picker")

        // The root view rebuilds on a language change (.id(lang)), which
        // resets the tab selection — re-open Settings explicitly.
        tapSettingsTab()

        XCTAssertTrue(
            app.navigationBars["Ajustes"].waitForExistence(timeout: 5),
            "Settings navigation title must read 'Ajustes'"
        )

        // The language row's label is the Spanish "Idioma"
        // (settings.language.picker). Anchor the assertion on the row element
        // itself (by accessibility id) rather than a global static-text search,
        // which could be satisfied by "Idioma" appearing anywhere on screen.
        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(app.scrollToElement(link),
                      "Language row must be reachable in Settings")
        XCTAssertTrue(
            link.staticTexts["Idioma"].exists || link.label.contains("Idioma"),
            "The language row must be labeled 'Idioma' in Spanish"
        )

        // A section header in Spanish. CONTAINS[cd] tolerates the
        // uppercasing SwiftUI applies to grouped-list section headers.
        XCTAssertTrue(
            staticTextContaining("Diccionarios"),
            "Settings must show the Spanish 'Diccionarios' section header"
        )
    }

    // MARK: - Navigation helpers (language-independent)

    /// The tab bar, waited into existence.
    private var tabBar: XCUIElement {
        let bar = app.tabBars.firstMatch
        _ = bar.waitForExistence(timeout: 10)
        return bar
    }

    /// A tab-bar button by its visible (localized) label.
    private func tabButton(label: String) -> XCUIElement {
        tabBar.buttons[label]
    }

    /// Taps the Settings tab by index. iOS 26's `.tap()` first runs an AX
    /// `scrollToVisible` that can fail on tab-bar buttons; a coordinate tap
    /// skips it. Index is language-independent (unlike a label match).
    private func tapSettingsTab() {
        let bar = tabBar
        XCTAssertTrue(bar.exists, "Tab bar must appear")
        let settings = bar.buttons.element(boundBy: settingsTabIndex)
        XCTAssertTrue(settings.waitForExistence(timeout: 5),
                      "Settings tab (index \(settingsTabIndex)) must exist")
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Settings tab → language picker.
    private func openLanguagePicker() {
        tapSettingsTab()
        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(app.scrollToElement(link),
                      "Language picker row ('ui_language_link') must be reachable")
        link.tap()
    }

    /// Switches the in-app UI language to `code` via the picker. Returns
    /// false (rather than asserting) so `tearDown` can call it defensively.
    @discardableResult
    private func selectLanguage(code: String) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.waitForExistence(timeout: 10) else { return false }
        let settings = bar.buttons.element(boundBy: settingsTabIndex)
        guard settings.waitForExistence(timeout: 5) else { return false }
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let link = app.descendants(matching: .any)["ui_language_link"]
        guard app.scrollToElement(link) else { return false }
        link.tap()

        let opt = option(for: code)
        guard opt.waitForExistence(timeout: 5) else { return false }
        opt.tap()
        return true
    }

    private func option(for code: String) -> XCUIElement {
        app.descendants(matching: .any)["ui_language_option_\(code)"]
    }

    /// True if any static text's label contains `substring` (case- and
    /// diacritic-insensitive), within the timeout.
    private func staticTextContaining(_ substring: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", substring)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }
}
