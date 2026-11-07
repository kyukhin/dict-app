import XCTest

/// Issue #243 — Settings → Dictionaries → Languages downloads more and
/// removes (Kirill 2026-11-03; 0237, "Settings → Dictionaries").
///
/// - Every download is answered from the committed assets (`-packDownloads`),
///   never the network.
/// - Each test starts with no pack (`-resetPacks`) but Russian, installed at
///   launch from the assets, so Dictionary Order has a pair before the ones
///   downloaded here.
/// - Greek is typed through `SearchPage.searchFor`. If "search field should
///   contain typed term" fails, check the simulator's hardware keyboard.
final class LanguagesFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private typealias IDs = AccessibilityIdentifiers.Languages
    private let russian = TestData.Pairs.russian
    private let greek = TestData.Pairs.greek
    private let spanish = TestData.Pairs.spanish

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-disableReviewPrompt", "-resetData", "-resetPacks"]
        // `-skipWelcome`, and Russian from the committed assets.
        app.launchArguments += UITestHelpers.packArguments("rus")
        // Long texts (definitions, the inflection table): silence the app's
        // os_log so XCTest's log volume cannot crash it on iOS 17.5 (#125).
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
        tabBarPage = nil
    }

    /// Launches with every download answered in `mode` (`ok`, `slow`, …).
    private func launch(downloads mode: String) {
        app.launchArguments += ["-packDownloads", mode]
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    // MARK: - Tests

    /// Download Greek (then Spanish, so a pair follows it): Installed, and
    /// γραφω finds γράφω with its table; Remove asks first, then γραφω finds
    /// nothing and Greek leaves Dictionary Order; downloaded again, Greek
    /// is back in its place, between Russian and Spanish.
    func testDownloadAndRemoveGreek() throws {
        launch(downloads: "ok")
        let settings = tabBarPage.tapSettingsTab()
        let languages = LanguagesPage(app: app)
        XCTAssertTrue(languages.open(), "Settings → Languages must open")
        XCTAssertTrue(languages.element(IDs.row("eng")).exists, "English is listed")
        XCTAssertTrue(languages.waitForInstalled("rus", timeout: TestData.Timeouts.medium),
                      "Russian, installed at launch, shows Installed")
        XCTAssertEqual(Self.visible(languages.button(IDs.download("ell")).label), "Download · 11.9 MB")
        attachScreenshot("Languages, Russian installed")

        languages.tapDownload("ell")
        XCTAssertTrue(languages.waitForInstalled("ell"), "Greek installs")
        XCTAssertEqual(Self.visible(languages.element(IDs.installed("ell")).label), "Installed · 60.6 MB")
        languages.tapDownload("spa")
        XCTAssertTrue(languages.waitForInstalled("spa"), "Spanish installs")
        attachScreenshot("Languages, Greek and Spanish installed")

        languages.goBack()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary Order must open")
        XCTAssertEqual(settings.currentOrder(of: [russian, greek, spanish]), [russian, greek, spanish],
                       "each language joins the order last")
        settings.goBack()

        // γραφω finds γράφω, and its Definition shows the table.
        var search = tabBarPage.tapSearchTab()
        _ = InflectionTablePage.open("γράφω", query: "γραφω", source: TestData.Sources.freedictEllEng,
                                     from: search, app: app)

        // Remove, with its alert.
        _ = tabBarPage.tapSettingsTab()
        XCTAssertTrue(languages.open(), "Settings → Languages must open again")
        let alert = languages.swipeToRemove("ell")
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "Remove asks first")
        XCTAssertEqual(Self.visible(alert.label), "Remove Greek?")
        XCTAssertTrue(alert.staticTexts["Its dictionaries, word forms and word lists are deleted. "
                                        + "Your History, My words and learning progress stay."].exists,
                      "the alert says what goes and what stays")
        attachScreenshot("Remove Greek?")
        alert.buttons["Remove"].tap()
        XCTAssertTrue(languages.button(IDs.download("ell")).waitForExistence(timeout: TestData.Timeouts.long),
                      "Greek shows Download again")
        XCTAssertTrue(languages.element(IDs.installed("spa")).exists, "Spanish stays")

        // γραφω finds nothing.
        search = tabBarPage.tapSearchTab()
        search.searchFor("γραφω")
        XCTAssertTrue(search.waitForNoResults(timeout: TestData.Timeouts.long), "no Greek without its pack")
        search.dismissKeyboard()

        // Dictionary Order lists installed dictionaries only, and keeps
        // Greek's place for the next install.
        _ = tabBarPage.tapSettingsTab()
        if languages.screen.exists {
            languages.goBack()
        }
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary Order must open")
        let pairs = [russian, greek, spanish]
        XCTAssertEqual(settings.currentOrder(of: pairs), [russian, spanish])
        let more = languages.button(IDs.moreLanguages)
        XCTAssertTrue(app.scrollToElement(more), "the footer links to Languages")
        XCTAssertEqual(more.label, "More languages")
        more.tap()
        XCTAssertTrue(languages.screen.waitForExistence(timeout: TestData.Timeouts.medium),
                      "More languages opens Languages")
        languages.tapDownload("ell")
        XCTAssertTrue(languages.waitForInstalled("ell"), "Greek installs again")
        languages.goBack()
        XCTAssertTrue(app.descendants(matching: .any)["dictionary_order_view"]
                        .waitForExistence(timeout: TestData.Timeouts.medium), "back on Dictionary Order")
        let back = NSPredicate { _, _ in settings.currentOrder(of: pairs) == pairs }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)],
                                      timeout: TestData.Timeouts.medium), .completed,
                       "Greek is back between Russian and Spanish, not last: \(settings.currentOrder(of: pairs))")
        attachScreenshot("Dictionary Order, Greek back in its place")
    }

    /// Cancel (0237, "Cancel"): a running download shows its progress and
    /// stops; one queued behind it shows Waiting. Nothing is installed.
    func testCancelDownload() throws {
        launch(downloads: "slow")
        let settings = tabBarPage.tapSettingsTab()
        let languages = LanguagesPage(app: app)
        XCTAssertTrue(languages.open(), "Settings → Languages must open")

        languages.tapDownload("ell")
        let greekProgress = languages.element(IDs.progress("ell"))
        XCTAssertTrue(greekProgress.waitForExistence(timeout: TestData.Timeouts.medium), "Greek shows its progress")
        let downloading = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", " of ", "11.9 MB")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: downloading, object: greekProgress)],
                                      timeout: TestData.Timeouts.long), .completed,
                       "the bar reads '… of 11.9 MB'; got '\(String(describing: greekProgress.value))'")
        XCTAssertTrue(languages.button(IDs.cancel("ell")).exists, "a download can be cancelled")

        languages.tapDownload("spa")
        let spanishProgress = languages.element(IDs.progress("spa"))
        XCTAssertTrue(spanishProgress.waitForExistence(timeout: TestData.Timeouts.medium), "Spanish is queued")
        XCTAssertEqual(spanishProgress.value as? String, "Waiting")
        attachScreenshot("Greek downloading, Spanish waiting")

        languages.tapCancel("spa")
        XCTAssertTrue(languages.button(IDs.download("spa")).waitForExistence(timeout: TestData.Timeouts.medium),
                      "a cancelled wait shows Download again")
        XCTAssertTrue(greekProgress.exists, "Greek goes on")
        languages.tapCancel("ell")
        XCTAssertTrue(languages.button(IDs.download("ell")).waitForExistence(timeout: TestData.Timeouts.medium),
                      "a cancelled download shows Download again")
        XCTAssertFalse(greekProgress.exists, "no progress left")
        XCTAssertFalse(languages.element(IDs.installed("ell")).exists)
        XCTAssertFalse(languages.element(IDs.error("ell")).exists, "a cancel shows no error")

        languages.goBack()
        XCTAssertTrue(settings.openDictionaryOrder(), "Dictionary Order must open")
        XCTAssertEqual(settings.currentOrder(of: [russian, greek, spanish]), [russian], "nothing was installed")
    }

    /// Edit and Done follow the in-app language, not the device's: the
    /// system `EditButton` reads "Edit" on an English simulator whatever the
    /// app's language. Edit's remove button asks first, as the swipe does.
    func testEditFollowsTheInAppLanguage() throws {
        launch(downloads: "ok")
        _ = tabBarPage.tapSettingsTab()
        // Russian in the app; the simulator stays English.
        let link = app.descendants(matching: .any)["ui_language_link"]
        XCTAssertTrue(app.scrollToElement(link), "the language row must be reachable")
        link.tap()
        let russian = app.descendants(matching: .any)["ui_language_option_ru"]
        XCTAssertTrue(russian.waitForExistence(timeout: TestData.Timeouts.medium), "Russian is offered")
        russian.tap()
        // The rebuild resets the tab selection.
        _ = tabBarPage.tapSettingsTab()
        let languages = LanguagesPage(app: app)
        XCTAssertTrue(languages.open(), "Settings → Languages must open")
        XCTAssertTrue(app.navigationBars["Языки"].waitForExistence(timeout: TestData.Timeouts.medium),
                      "the screen is in Russian")

        let edit = languages.button(IDs.edit)
        XCTAssertTrue(edit.waitForExistence(timeout: TestData.Timeouts.medium), "Russian is installed: Edit shows")
        XCTAssertEqual(edit.label, "Править", "Edit in the in-app language")
        edit.tap()
        let done = NSPredicate(format: "label == %@", "Готово")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: done, object: edit)],
                                      timeout: TestData.Timeouts.medium), .completed,
                       "Done in the in-app language; got '\(edit.label)'")
        attachScreenshot("Languages (ru), editing")

        // Russian, the one installed pack, has the delete control; it shows
        // Remove, and Remove asks first.
        let minus = app.images["minus.circle.fill"].firstMatch
        XCTAssertTrue(minus.waitForExistence(timeout: TestData.Timeouts.medium), "editing shows the delete control")
        minus.tap()
        let remove = languages.button(IDs.remove("rus"))
        XCTAssertTrue(remove.waitForExistence(timeout: TestData.Timeouts.medium), "the control shows Remove")
        XCTAssertEqual(remove.label, "Удалить")
        remove.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "Remove asks first")
        XCTAssertEqual(Self.visible(alert.label), "Удалить русский?")
        alert.buttons["Отменить"].tap()
        XCTAssertTrue(languages.element(IDs.installed("rus")).waitForExistence(timeout: TestData.Timeouts.medium),
                      "Cancel keeps Russian")

        edit.tap()
        let editAgain = NSPredicate(format: "label == %@", "Править")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: editAgain, object: edit)],
                                      timeout: TestData.Timeouts.medium), .completed,
                       "Done ends editing; got '\(edit.label)'")
        XCTAssertFalse(app.images["minus.circle.fill"].exists, "no delete control after Done")
    }

    /// `s` without Foundation's U+2068/U+2069 isolates around arguments.
    private static func visible(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0 != "\u{2068}" && $0 != "\u{2069}" })
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
