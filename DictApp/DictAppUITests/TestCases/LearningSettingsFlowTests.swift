import XCTest

/// 0131, #162: Settings → Learning. The section replacing the old stub, the
/// new-word limit, the learned languages (stop, add again, change the via,
/// a limited pair's warning) and the reminder's permission prompt. English
/// UI, `-resetData` first.
///
/// The notification permission survives relaunches and cannot be reset by
/// XCUITest, so only `testPermissionAskedOnlyWhenTurnedOn` touches the
/// reminder, and it needs a fresh install: run the suite after
/// uninstalling the app.
final class LearningSettingsFlowTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testNewWordsPerDayZeroOffersNoNewWords") { return ["-learningFixture", "myWords5"] }
        if name.contains("testLimitedPairWarningInSettings") { return ["-learningLanguages", "ell:rus"] }
        if name.contains("testPermissionAskedOnlyWhenTurnedOn") {
            return ["-learningFixture", "due", "-learningAnswerHints"]
        }
        if name.contains("testChangeTheVia") {
            return ["-learningFixture", "bilingual", "-learningAnswerHints", "-learningSeed", "162"]
        }
        if name.contains("testStopAndResumeALanguage") { return ["-learningFixture", "bilingual"] }
        if name.contains("testNewWordsFromOpensTheScreen") { return ["-learningLanguages", "ell"] }
        if name.contains("testStepperRowsStackAtTheLargestTextSize") {
            return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        return []
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek and Spanish packs,
        // which hold the meanings, installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + learningArguments + UITestHelpers.packArguments()
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

    /// SpringBoard's permission alert, if one shows.
    private var springboardAlert: XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    }

    // MARK: - Tests

    /// The Learning section stands where "Coming Soon" was, with every
    /// setting at its default; Haptics only on a device with haptics, and
    /// the reminder's time only while it is on.
    func testSettingsSectionReplacesComingSoon() throws {
        let page = openSettings()
        page.reveal(page.languagesRow)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Learning")).firstMatch.exists,
                      "the Learning header")
        XCTAssertFalse(app.staticTexts["Coming Soon"].exists, "no stub")
        XCTAssertEqual(page.languagesRow.label, "Languages", "nothing learned yet")
        XCTAssertEqual(page.value(of: page.newPerDay), 10)
        XCTAssertTrue(page.newPerDay.label.contains("New words per day"), page.newPerDay.label)
        page.reveal(page.goal)
        XCTAssertEqual(page.value(of: page.goal), 20)
        XCTAssertTrue(page.goal.label.contains("20 exercises"), page.goal.label)
        page.reveal(page.order)
        XCTAssertEqual(page.order.label, "New words order, By frequency")
        page.reveal(page.answerMode)
        XCTAssertEqual(page.answerMode.label, "Typed answers, Lenient")
        page.reveal(page.sounds)
        XCTAssertEqual(page.sounds.value as? String, "1", "Sounds on")
        XCTAssertFalse(page.haptics.exists, "the simulator has no haptics: the row is hidden")
        page.reveal(page.reminder)
        XCTAssertEqual(page.reminder.value as? String, "0", "the reminder is off")
        XCTAssertFalse(page.reminderTime.exists, "no time while off")

        page.choose("Random", in: page.order)
        page.choose("Strict accents", in: page.answerMode)
        page.step(page.goal, to: 30)
        XCTAssertTrue(page.goal.label.contains("30 exercises"), page.goal.label)
    }

    /// `-learningFixture myWords5`: five new words. New words per day at 0
    /// leaves none: the Learn home is all done, with no Start; at 3, three.
    func testNewWordsPerDayZeroOffersNoNewWords() throws {
        var learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "5 new words left today"))

        var page = openSettings()
        page.step(page.newPerDay, to: 0)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.allDone.waitForExistence(timeout: TestData.Timeouts.medium), "All done for today")
        XCTAssertFalse(learnPage.startButton.exists, "no Start")
        XCTAssertFalse(learnPage.newCount.exists)

        page = openSettings()
        page.step(page.newPerDay, to: 3)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.newCount, toBe: "3 new words left today"))
        XCTAssertTrue(learnPage.startButton.exists)
    }

    /// 0130, #154: the "New words from" row opens E3's New words from, the
    /// same set the Learn home checks: Greek A1 checked here is checked on
    /// the Learn home's screen too.
    func testNewWordsFromOpensTheScreen() throws {
        let page = openSettings()
        page.reveal(page.newWordsFromRow)
        XCTAssertEqual(page.newWordsFromRow.label, "New words from")
        page.newWordsFromRow.tap()
        let lists = WordListsPage(app: app)
        XCTAssertTrue(lists.waitForNewWordsFrom(), "New words from")
        XCTAssertTrue(lists.noneChecked.waitForExistence(timeout: TestData.Timeouts.medium), "nothing checked yet")
        let greekA1 = lists.newWordsFromRow("ky-ell-a1")
        XCTAssertTrue(greekA1.waitForExistence(timeout: TestData.Timeouts.medium), "Greek A1")
        greekA1.tap()
        XCTAssertTrue(lists.wait(for: greekA1, selected: true), "Greek A1 checked")

        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(), "the Learn home")
        XCTAssertTrue(learnPage.listRow("ky-ell-a1").waitForExistence(timeout: TestData.Timeouts.medium),
                      "the Lists section shows Greek A1")
    }

    /// Fresh install: a session and the Settings screen ask nothing; turning
    /// the reminder on shows iOS's permission alert, and Allow keeps it on
    /// with its time.
    func testPermissionAskedOnlyWhenTurnedOn() throws {
        let learnPage = tabBarPage.tapLearnTab()
        let run = learnPage.startSession()
        XCTAssertTrue(run.waitForQuestionOrSummary(), "a question")
        if run.isTyped {
            run.dontKnowButton.tap()
        } else {
            run.choose(right: true)
        }
        XCTAssertNotNil(run.waitForFeedback(), "answered")
        run.tapContinue()
        XCTAssertTrue(run.closeButton.waitForExistence(timeout: TestData.Timeouts.medium))
        run.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertFalse(springboardAlert.exists, "no permission alert from a session")

        let page = openSettings()
        page.reveal(page.reminder)
        XCTAssertFalse(springboardAlert.waitForExistence(timeout: TestData.Timeouts.short),
                       "no permission alert from Settings")

        page.reminder.switches.firstMatch.tap()
        guard springboardAlert.waitForExistence(timeout: TestData.Timeouts.medium) else {
            if page.reminder.value as? String == "1" {
                throw XCTSkip("the permission was decided before: not a fresh install")
            }
            XCTFail("turning the reminder on shows the permission alert")
            return
        }
        let allow = springboardAlert.buttons["Allow"]
        XCTAssertTrue(allow.exists, "the alert offers Allow")
        allow.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: page.reminder)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: TestData.Timeouts.medium), .completed, "the reminder stays on")
        XCTAssertTrue(page.reminderTime.waitForExistence(timeout: TestData.Timeouts.medium), "its time shows")
    }

    /// `-learningFixture bilingual`, English via English: changing English
    /// to via Spanish in Settings asks house and water with their Spanish
    /// meanings from the next question; the due count stays.
    func testChangeTheVia() throws {
        var learnPage = tabBarPage.tapLearnTab()
        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"))

        let page = openSettings()
        XCTAssertTrue(page.openLanguages(), "the Languages screen")
        XCTAssertEqual(page.via("eng").label, "via English")
        page.chooseVia("via Spanish", for: "eng")
        XCTAssertFalse(page.limited("eng").exists, "a full pair has no warning")

        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(learnPage.languageSwitch.buttons["English"].isSelected, "English stays chosen")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"), "no card changed")
        let run = learnPage.openTrainer()
        let spanish = ["house": "casalicio, casa", "water": "agua, aguacha, linfa, wata"]
        var asked: Set<String> = []
        while asked.count < 2, run.waitForQuestionOrSummary(), !run.summary.exists {
            let prompt = run.prompt.label
            XCTAssertEqual(run.rightOption?.label, spanish[prompt], "\(prompt)'s meaning, in Spanish")
            asked.insert(prompt)
            run.choose(right: true)
            XCTAssertEqual(run.waitForFeedback(), "right")
            run.tapContinue()
        }
        XCTAssertEqual(asked, Set(spanish.keys), "only English words")
    }

    /// Greek via Russian, limited: its row warns "Words are practised in
    /// English."; the warning goes with Greek via English.
    func testLimitedPairWarningInSettings() throws {
        let page = openSettings()
        XCTAssertTrue(page.openLanguages())
        XCTAssertEqual(page.via("ell").label, "via Russian")
        XCTAssertTrue(page.limited("ell").exists, "the limited pair's warning")
        XCTAssertEqual(page.limited("ell").label, "Words are practised in English.")
        page.chooseVia("via English", for: "ell")
        XCTAssertTrue(page.limited("ell").waitForNonExistence(timeout: TestData.Timeouts.medium), "no warning via English")
    }

    /// `-learningFixture bilingual`: stopping English removes it from the
    /// switch; adding it again from Settings brings the switch and its 2
    /// due words back, its progress kept.
    func testStopAndResumeALanguage() throws {
        var learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "Greek | English")

        let page = openSettings()
        XCTAssertTrue(page.waitForLabel(of: page.reveal(page.languagesRow), containing: "Greek, English"))
        XCTAssertTrue(page.openLanguages())
        XCTAssertTrue(page.languageRow("ell").exists)
        page.stopLearning("eng", expectingTitle: "Stop learning English?")
        XCTAssertTrue(page.languageRow("ell").exists, "Greek stays")

        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"), "Greek's words")
        XCTAssertFalse(learnPage.languageSwitch.exists, "one language: no switch")

        tabBarPage.tapSettingsTab()
        XCTAssertTrue(page.languagesView.waitForExistence(timeout: TestData.Timeouts.medium), "still on Languages")
        page.addLanguage.tap()
        XCTAssertTrue(learnPage.waitForPicker(), "the picker")
        XCTAssertFalse(learnPage.pickerRow("ell", via: "eng").exists, "Greek is learned: not offered")
        XCTAssertTrue(learnPage.pickerRow("eng", via: "eng").waitForExistence(timeout: TestData.Timeouts.medium))
        learnPage.pickerRow("eng", via: "eng").tap()
        XCTAssertTrue(page.languageRow("eng").waitForExistence(timeout: TestData.Timeouts.medium), "English is back")

        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "the switch returns")
        XCTAssertTrue(learnPage.languageSwitch.buttons["English"].isSelected, "the language just added")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"), "house and water, still due")
    }

    /// #181: at the largest accessibility text size, in Russian, the daily
    /// goal and new words per day put their − + control on its own line
    /// under the title and value, so "Цель на день" keeps the row's width
    /// instead of breaking mid-word beside the control. VoiceOver still
    /// reads the control with its title and value, and it still steps.
    ///
    /// The check is where the − + buttons sit, at the leading edge (beside
    /// the title they end at the trailing edge), not the stepper's frame:
    /// on iOS 17 that frame is the whole row in both layouts.
    func testStepperRowsStackAtTheLargestTextSize() throws {
        let page = openSettings()
        let window = app.windows.firstMatch.frame
        page.reveal(page.goal)
        XCTAssertTrue(page.goal.label.contains("Цель на день"), page.goal.label)
        XCTAssertTrue(page.goal.label.contains("20 упражнений"), page.goal.label)
        let goalControl = controlFrame(of: page.goal)
        XCTAssertLessThan(goalControl.maxX, window.width / 2,
                          "the control on its own line, not beside the title: \(goalControl) in \(window)")
        page.reveal(page.newPerDay)
        XCTAssertTrue(page.newPerDay.label.contains("Новых слов в день"), page.newPerDay.label)
        let newPerDayControl = controlFrame(of: page.newPerDay)
        XCTAssertLessThan(newPerDayControl.maxX, window.width / 2,
                          "the control on its own line: \(newPerDayControl) in \(window)")

        page.reveal(page.goal)
        page.goal.buttons.element(boundBy: 1).tap()
        let stepped = NSPredicate(format: "label CONTAINS %@", "25 упражнений")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stepped, object: page.goal)],
                                      timeout: TestData.Timeouts.medium), .completed,
                       "+ steps the goal by 5; got '\(page.goal.label)'")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings (ru), largest text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The − + control: the union of the stepper's two buttons.
    private func controlFrame(of stepper: XCUIElement) -> CGRect {
        let buttons = stepper.buttons.allElementsBoundByIndex
        XCTAssertEqual(buttons.count, 2, "the stepper's − and + buttons")
        return buttons.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
}
