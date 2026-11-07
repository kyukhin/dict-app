import XCTest

/// Issue #245 — the first-launch sheet (0237, "First launch").
///
/// - Each test is a fresh install without uninstalling: `-resetDatabase`,
///   `-resetPacks` (which also clears `packs_offered`) and `-resetData`, and
///   no `-skipWelcome`, so the sheet shows.
/// - Every download is answered from the committed assets
///   (`-packDownloads <mode>`), never the network.
/// - The launch's languages decide what is checked at first: in English
///   (`-AppleLanguages (en)`), nothing; in Arabic, Arabic.
final class WelcomeFlowTests: XCTestCase {

    var app: XCUIApplication!

    private typealias IDs = AccessibilityIdentifiers.Welcome
    private typealias Packs = AccessibilityIdentifiers.Languages

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-disableReviewPrompt", "-resetDatabase", "-resetPacks", "-resetData"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
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
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches with every download answered in `mode` and waits for the
    /// sheet. English unless a test set the languages: a simulator inherits
    /// the Mac's preferred languages, which the sheet checks.
    private func launch(downloads mode: String) -> WelcomePage {
        if !app.launchArguments.contains("-AppleLanguages") {
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
        app.launchArguments += UITestHelpers.downloadArguments(mode)
        app.launch()
        let welcome = WelcomePage(app: app)
        XCTAssertTrue(welcome.waitForSheet(), "a fresh install shows the sheet")
        return welcome
    }

    private var results: XCUIElement { app.collectionViews.firstMatch }

    /// A result row from `source` (its badge).
    private func resultRow(source: String) -> XCUIElement {
        results.cells.containing(.any, identifier: AccessibilityIdentifiers.Search.sourceBadge(source: source)).firstMatch
    }

    // MARK: - Tests

    /// 0237 Test plan: the sheet lists the four languages, none checked on
    /// an English simulator; the Import link pushes Manage Dictionaries; check
    /// Spanish, Download, its progress row, Done. `casa` then finds Es–En
    /// rows and the Spanish – English chip appears, in the same launch.
    func testDownloadSpanishThenSearch() throws {
        let welcome = launch(downloads: "ok")
        XCTAssertTrue(app.staticTexts["Welcome to LibreDict"].exists, "the title")
        XCTAssertTrue(app.staticTexts["English is included and works offline. Add other languages: "
                                      + "each downloads once, then works offline too."].exists, "the fresh text")
        for id in ["arb", "ell", "rus", "spa"] {
            XCTAssertTrue(welcome.language(id).exists, "\(id) is offered")
            XCTAssertFalse(welcome.isChecked(id), "an English UI on an English simulator checks nothing: \(id)")
        }
        XCTAssertFalse(welcome.language("eng-lists").exists, "English lists come with learning, not here")
        XCTAssertEqual(welcome.downloadButton.label, "Continue")
        XCTAssertTrue(welcome.notNowButton.exists)

        // The Import link, and back.
        welcome.importLink.tap()
        let manage = app.navigationBars["Manage Dictionaries"]
        XCTAssertTrue(manage.waitForExistence(timeout: TestData.Timeouts.medium), "Import pushes Manage Dictionaries")
        XCTAssertTrue(app.buttons["import_dictionary_button"].exists)
        manage.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(welcome.language("spa").waitForExistence(timeout: TestData.Timeouts.medium), "back on the sheet")

        welcome.toggle("spa")
        XCTAssertEqual(UITestHelpers.visible(welcome.downloadButton.label), "Download 6.9 MB")
        attachScreenshot("Welcome, Spanish checked")
        welcome.tapDownload()

        XCTAssertTrue(welcome.element(Packs.row("spa")).waitForExistence(timeout: TestData.Timeouts.medium),
                      "Spanish's progress row")
        XCTAssertFalse(welcome.element(Packs.row("ell")).exists, "only the chosen language")
        XCTAssertFalse(welcome.notNowButton.exists, "no Not now after Download")
        XCTAssertTrue(welcome.waitForInstalled("spa"), "Spanish installs")
        attachScreenshot("Welcome, Spanish installed")
        welcome.tapDone()
        XCTAssertTrue(welcome.waitForSheetGone(), "Done closes the sheet")

        let search = SearchPage(app: app)
        XCTAssertTrue(search.waitForChips(), "the chips load")
        XCTAssertTrue(search.chip(TestData.Pairs.spanish).waitForExistence(timeout: TestData.Timeouts.medium),
                      "the Spanish – English chip, without a restart")
        search.searchFor("casa")
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "casa finds rows")
        let spanish = resultRow(source: TestData.Sources.wordnetSpaEng)
        if !spanish.waitForExistence(timeout: TestData.Timeouts.short) {
            app.dismissKeyboardIfPresent()
            XCTAssertTrue(app.scrollToElement(spanish, in: results), "casa finds a Spanish – English row")
        }
    }

    /// 0237 Test plan: a download that stops (`failOnce`) shows why, and
    /// Try again installs it.
    func testFailedDownloadCanBeRetried() throws {
        let welcome = launch(downloads: "failOnce")
        welcome.toggle("rus")
        welcome.tapDownload()

        let error = welcome.element(Packs.error("rus"))
        XCTAssertTrue(error.waitForExistence(timeout: TestData.Timeouts.long), "the download stops")
        XCTAssertEqual(error.label, "The download stopped. Check your connection and try again.")
        let retry = welcome.button(Packs.retry("rus"))
        XCTAssertTrue(retry.exists, "Try again")
        attachScreenshot("Welcome, Russian failed")
        retry.tap()
        XCTAssertTrue(welcome.waitForInstalled("rus"), "the second attempt installs")
        XCTAssertFalse(error.exists, "no error left")
        welcome.tapDone()
        XCTAssertTrue(welcome.waitForSheetGone())

        let search = SearchPage(app: app)
        search.searchFor("дом")
        XCTAssertTrue(search.waitForResults(timeout: TestData.Timeouts.long), "Russian is searchable")
        XCTAssertTrue(resultRow(source: TestData.Sources.openrussian).waitForExistence(timeout: TestData.Timeouts.medium))
    }

    /// QA #245 (0237, "First launch"): after Download each chosen language
    /// shows its progress in the rows' order, Greek "… of 11.2 MB" and
    /// Spanish "Waiting"; Done closes the sheet and the downloads go on
    /// (Settings → Languages still shows them).
    func testProgressThenDoneKeepsDownloading() throws {
        let welcome = launch(downloads: "slow")
        welcome.toggle("spa")
        welcome.toggle("ell")
        XCTAssertEqual(UITestHelpers.visible(welcome.downloadButton.label), "Download 18.1 MB")
        welcome.tapDownload()

        let greek = welcome.element(Packs.progress("ell"))
        XCTAssertTrue(greek.waitForExistence(timeout: TestData.Timeouts.medium), "Greek, first in the rows, downloads")
        let downloading = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", " of ", "11.2 MB")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: downloading, object: greek)],
                                      timeout: TestData.Timeouts.long), .completed,
                       "the bar reads '… of 11.2 MB'; got '\(String(describing: greek.value))'")
        XCTAssertEqual(welcome.element(Packs.progress("spa")).value as? String, "Waiting", "Spanish waits its turn")
        XCTAssertFalse(welcome.element(Packs.row("arb")).exists, "only the chosen languages")
        attachScreenshot("Welcome, Greek downloading, Spanish waiting")
        welcome.tapDone()
        XCTAssertTrue(welcome.waitForSheetGone(), "Done closes the sheet")

        _ = TabBarPage(app: app).tapSettingsTab()
        let languages = LanguagesPage(app: app)
        XCTAssertTrue(languages.open(), "Settings → Languages must open")
        XCTAssertTrue(languages.element(Packs.progress("spa")).waitForExistence(timeout: TestData.Timeouts.medium),
                      "the downloads go on after Done")
    }

    /// QA #245 (0237, "First launch"): swiping the sheet down is Not now,
    /// and the sheet appears once: the next launch, with nothing reset,
    /// opens on Search.
    func testSwipeDownIsNotNowAndTheSheetShowsOnce() throws {
        let welcome = launch(downloads: "offline")
        welcome.sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(welcome.waitForSheetGone(), "a swipe closes the sheet")
        app.terminate()

        app.launchArguments = ["-disableReviewPrompt", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + UITestHelpers.downloadArguments("offline")
        app.launch()
        XCTAssertTrue(app.waitForDictionariesReady(), "Search shows")
        XCTAssertFalse(welcome.sheet.waitForExistence(timeout: TestData.Timeouts.short), "the sheet does not come back")
    }

    /// Arabic (#119, 0237 "UI"): the sheet in Arabic, Arabic checked as the
    /// UI language, the Download label right to left; offline, the row shows
    /// why and Try again, its name right of the button.
    func testSheetIsRightToLeftInArabic() throws {
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        let welcome = launch(downloads: "offline")
        XCTAssertTrue(app.staticTexts["مرحبًا بك في LibreDict"].exists, "the title in Arabic")
        XCTAssertTrue(welcome.isChecked("arb"), "the UI language's pack is checked")
        XCTAssertFalse(welcome.isChecked("ell"))
        let download = welcome.downloadButton.label
        XCTAssertEqual(download.unicodeScalars.first, "\u{200F}", download)
        XCTAssertTrue(UITestHelpers.visible(download).hasPrefix("تنزيل "), download)
        attachScreenshot("Welcome (ar)")

        welcome.tapDownload()
        let error = welcome.element(Packs.error("arb"))
        XCTAssertTrue(error.waitForExistence(timeout: TestData.Timeouts.long), "offline fails at once")
        XCTAssertEqual(error.label, "لا يوجد اتصال بالإنترنت.")
        let name = app.staticTexts[Packs.row("arb")]
        let retry = welcome.button(Packs.retry("arb"))
        XCTAssertEqual(name.label, "العربية")
        XCTAssertEqual(retry.label, "أعد المحاولة")
        XCTAssertGreaterThan(name.frame.minX, retry.frame.maxX, "the name is right of Try again")
        attachScreenshot("Welcome (ar), offline")
        welcome.tapDone()
        XCTAssertTrue(welcome.waitForSheetGone())
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
