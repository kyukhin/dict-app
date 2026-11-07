import XCTest

/// Issue #245 — the sheet after an update from 1.x (0237, "Update from 1.x
/// and from the 2.0 alpha").
///
/// - `-legacyFixture` makes a launch an update from 1.4.0: the fixture is
///   the 1.x database, on an empty user database, with `packs_offered` and
///   `packs_installed` cleared. Every 1.x dictionary was on (`-resetData`
///   clears `enabled_sources`), so the sheet checks all four languages.
/// - Until its language is installed, a History word opens the "not
///   downloaded" view, whose Download opens the word.
/// - Every download is answered from the committed assets, never the network.
final class UpgradeOfferTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-disableReviewPrompt"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// 0237 Test plan: the sheet's upgrade text with the four languages
    /// checked; one Download restores them; History keeps the 1.x rows, and
    /// the Greek one opens its entry.
    func testUpgradeOffersEnabledDictionaries() throws {
        app.launchArguments += ["-resetPacks", "-resetData", "-legacyFixture", UITestHelpers.legacyFixture140.path]
        app.launchArguments += UITestHelpers.downloadArguments("ok")
        app.launch()
        let welcome = WelcomePage(app: app)
        XCTAssertTrue(welcome.waitForSheet(), "an update from 1.x shows the sheet")
        XCTAssertTrue(app.staticTexts["LibreDict 2.0 downloads languages other than English once. "
                                      + "Your History and My words are here."].exists, "the upgrade text")
        for id in ["arb", "ell", "rus", "spa"] {
            XCTAssertTrue(welcome.isChecked(id), "every dictionary was on: \(id) is checked")
        }
        XCTAssertEqual(UITestHelpers.visible(welcome.downloadButton.label), "Download 23.1 MB")
        attachScreenshot("Welcome after 1.4.0")

        welcome.tapDownload()
        for id in ["arb", "ell", "rus", "spa"] {
            XCTAssertTrue(welcome.waitForInstalled(id, timeout: 120), "\(id) installs")
        }
        welcome.tapDone()
        XCTAssertTrue(welcome.waitForSheetGone(), "Done closes the sheet")

        let history = TabBarPage(app: app).tapHistoryTab()
        XCTAssertTrue(history.waitForHistoryToLoad(), "History loads")
        // On iOS 26 a row's identifier is on its button, not its cell.
        func row(_ word: String) -> XCUIElement {
            app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyItem(word: word)].firstMatch
        }
        for word in ["dog", "house", "дом", "σπίτι"] {
            XCTAssertTrue(row(word).waitForExistence(timeout: TestData.Timeouts.medium), "the 1.x History row \(word)")
        }
        row("σπίτι").tap()
        XCTAssertTrue(definitionContent.waitForExistence(timeout: TestData.Timeouts.long),
                      "the Greek History row opens its entry")
        attachScreenshot("σπίτι from History")
    }

    /// 0237, "Update from 1.x": a History word of a language that is not
    /// installed opens "This word is in the Greek dictionaries." with its
    /// Download; once Greek installs, the word opens. The first launch
    /// installs Greek and views γράφω; the second removes the packs.
    func testHistoryWordOfAMissingLanguageOffersItsDownload() throws {
        app.launchArguments += ["-resetDatabase", "-resetData"] + UITestHelpers.packArguments("ell")
        app.launch()
        _ = InflectionTablePage.open("γράφω", query: "γραφω", source: TestData.Sources.freedictEllEng,
                                     from: TabBarPage(app: app).tapSearchTab(), app: app,
                                     expectsTable: false)
        app.terminate()

        app.launchArguments = ["-disableReviewPrompt", "-resetPacks", UITestHelpers.skipWelcome]
            + UITestHelpers.downloadArguments("ok")
        app.launch()
        let history = TabBarPage(app: app).tapHistoryTab()
        XCTAssertTrue(history.waitForHistoryToLoad(), "History loads")
        let row = app.descendants(matching: .any)[AccessibilityIdentifiers.History.historyItem(word: "γράφω")].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "γράφω stays in History")
        row.tap()

        XCTAssertTrue(app.staticTexts["This word is in the Greek dictionaries."]
                        .waitForExistence(timeout: TestData.Timeouts.medium), "the \"not downloaded\" view")
        let download = app.buttons[AccessibilityIdentifiers.Welcome.notDownloadedDownload]
        XCTAssertTrue(download.exists)
        XCTAssertEqual(UITestHelpers.visible(download.label), "Download Greek · 11.9 MB")
        attachScreenshot("γράφω, Greek not downloaded")
        download.tap()
        XCTAssertTrue(definitionContent.waitForExistence(timeout: 60), "γράφω opens once Greek installs")
        attachScreenshot("γράφω after the download")
    }

    /// The Definition text, of any element type: `DefinitionPage` picks
    /// the type before the screen has loaded.
    private var definitionContent: XCUIElement {
        app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionContent].firstMatch
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
