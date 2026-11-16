import XCTest

/// 0131, #291: Settings → Learning → Sound theme. The row shows while
/// Sounds is on, Classic by default; a theme chosen on its screen is
/// checked, shows on the row and survives a relaunch. English UI,
/// `-resetData` first. Tests never make a sound (`-muteSounds`).
final class SoundThemeFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = LibreDictApp()
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + UITestHelpers.packArguments()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    private func openSettings() -> LearningSettingsPage {
        tabBarPage.tapSettingsTab()
        return LearningSettingsPage(app: app)
    }

    /// Sounds on: the Sound theme row, Classic; Sounds off hides it, on
    /// again brings it back.
    func testPickerShowsWithSoundsOn() throws {
        let page = openSettings()
        page.reveal(page.sounds)
        XCTAssertEqual(page.sounds.value as? String, "1", "Sounds on by default")
        XCTAssertTrue(page.soundTheme.waitForExistence(timeout: TestData.Timeouts.medium), "the theme row")
        XCTAssertTrue(page.soundTheme.label.contains("Sound theme"), page.soundTheme.label)
        XCTAssertTrue(page.soundTheme.label.contains("Classic"), "Classic by default: \(page.soundTheme.label)")

        page.sounds.switches.firstMatch.tap()
        XCTAssertTrue(page.soundTheme.waitForNonExistence(timeout: TestData.Timeouts.medium), "Sounds off: no theme")
        XCTAssertEqual(page.sounds.value as? String, "0")

        page.reveal(page.sounds).switches.firstMatch.tap()
        XCTAssertTrue(page.soundTheme.waitForExistence(timeout: TestData.Timeouts.medium), "Sounds on: back")
        XCTAssertTrue(page.soundTheme.label.contains("Classic"), page.soundTheme.label)
    }

    /// The seven themes by name (#340: Mellstroy); Retro chosen on the Sound
    /// theme screen is checked there and named on the row, after a relaunch
    /// too.
    func testChosenThemeSurvivesARelaunch() throws {
        var page = openSettings()
        XCTAssertTrue(page.openSoundTheme(), "the Sound theme screen")
        let names = ["classic": "Classic", "cheerful": "Cheerful", "retro": "Retro", "grumpy": "Grumpy",
                     "silly": "Silly", "meme": "Meme", "mellstroy": "Mellstroy"]
        for (theme, name) in names {
            XCTAssertEqual(page.soundThemeOption(theme).label, name, theme)
        }
        XCTAssertTrue(page.soundThemeOption("classic").isSelected, "Classic is checked")

        page.soundThemeOption("retro").tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"),
                                                 object: page.soundThemeOption("retro"))
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: TestData.Timeouts.medium), .completed, "Retro checked")
        XCTAssertFalse(page.soundThemeOption("classic").isSelected, "one theme at a time")
        page.goBack()
        XCTAssertTrue(page.waitForLabel(of: page.reveal(page.soundTheme), containing: "Retro"), "the row names it")

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"] + UITestHelpers.packArguments()
        app.launch()
        tabBarPage = TabBarPage(app: app)
        page = openSettings()
        XCTAssertTrue(page.waitForLabel(of: page.reveal(page.soundTheme), containing: "Retro"), "kept after a relaunch")
        XCTAssertTrue(page.openSoundTheme())
        XCTAssertTrue(page.soundThemeOption("retro").isSelected, "still checked")
    }
}
