import XCTest

/// 0131, #293, #295: the Learn tab's pair tabs. A tab per learned pair and
/// "+", "…" and its sheet when they do not fit (a tab shows flags, 2026-11-10;
/// tests find tabs by their ids and labels, never by what they show), drag to reorder, Stop
/// learning on a long press, the goal and streak shared by every tab, and
/// what each tab holds for its language only. English UI, `-resetData`, the
/// packs installed from the committed assets.
final class PairTabsTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!
    var learnPage: LearnPage!

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testFiveTabsOverflow") || name.contains("testTabsAccessibility") {
            return ["-learningLanguages", "ell,eng,spa,rus,arb"]
        }
        if name.contains("testDraggedOrderSurvivesRelaunch") { return ["-learningLanguages", "ell,eng"] }
        if name.contains("testGoalAndStreakShared") { return ["-learningFixture", "stats"] }
        if name.contains("testConjugationWhileTrainersAreOff") { return ["-learningLanguages", "ell"] }
        return ["-learningFixture", "bilingual"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + learningArguments
            + UITestHelpers.packArguments()
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
        learnPage = nil
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: - Tabs, "+" and "…"

    /// Greek and English learned: two tabs and "+", in that order; "+" opens
    /// the picker without them; Spanish via English is added last, selected.
    func testTwoPairsTwoTabsAndAdd() throws {
        let greek = learnPage.pairTab("ell"), english = learnPage.pairTab("eng"), add = learnPage.pairTabAdd
        XCTAssertTrue(greek.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(greek.label, "Greek · via English", "the name, not the flags")
        XCTAssertTrue(greek.isSelected)
        if learnPage.pairTabMore.exists {
            // A narrow strip does not fit both tabs and "+": English is in
            // the "…" sheet, which ends with "Add a language".
            XCTAssertFalse(add.exists, "no + beside …")
            learnPage.pairTabMore.tap()
            XCTAssertTrue(learnPage.overflowRow("eng").waitForExistence(timeout: TestData.Timeouts.medium), "English")
            learnPage.overflowAdd.tap()
        } else {
            XCTAssertTrue(english.waitForExistence(timeout: TestData.Timeouts.medium))
            XCTAssertTrue(add.exists, "+")
            XCTAssertLessThan(greek.frame.minX, english.frame.minX)
            XCTAssertLessThan(english.frame.minX, add.frame.minX)
            add.tap()
        }
        XCTAssertTrue(learnPage.waitForPicker(), "+ opens the pair picker")
        XCTAssertFalse(learnPage.pickerRow("ell", via: "eng").exists, "Greek is learned")
        XCTAssertFalse(learnPage.pickerRow("eng", via: "eng").exists, "English is learned")
        XCTAssertTrue(learnPage.pickerRow("spa", via: "eng").waitForExistence(timeout: TestData.Timeouts.medium))
        learnPage.pickerRow("spa", via: "eng").tap()
        XCTAssertTrue(learnPage.waitForHome(), "back on the home")
        let spanish = learnPage.pairTab("spa")
        XCTAssertTrue(spanish.waitForExistence(timeout: TestData.Timeouts.medium) || reveal(spanish), "Spanish's tab")
        XCTAssertTrue(spanish.isSelected, "selected")
        // Three pairs may not fit a phone: English may sit behind "…".
        let englishTab = learnPage.pairTab("eng")
        XCTAssertFalse(englishTab.exists && englishTab.isSelected, "English is not selected")
    }

    /// Five learned languages: on an iPhone the last visible item is "…",
    /// not "+"; it opens the sheet with a row for each tab not in the
    /// strip, then "Add a language"; choosing a row selects its tab, which
    /// then shows. On an iPad all five tabs and "+" fit.
    func testFiveTabsOverflow() throws {
        let codes = ["ell", "eng", "spa", "rus", "arb"]
        XCTAssertTrue(learnPage.pairTab("ell").waitForExistence(timeout: TestData.Timeouts.medium))
        // A wide iPad window fits all five and "+" (0131: "usually"); a narrower
        // one, like an iPhone, ends the strip with "…".
        if !learnPage.pairTabMore.exists {
            for code in codes {
                XCTAssertTrue(learnPage.pairTab(code).waitForExistence(timeout: TestData.Timeouts.medium), code)
            }
            XCTAssertTrue(learnPage.pairTabAdd.exists)
            XCTAssertFalse(learnPage.pairTabMore.exists)
            return
        }
        XCTAssertTrue(learnPage.pairTabMore.waitForExistence(timeout: TestData.Timeouts.medium), "…")
        XCTAssertFalse(learnPage.pairTabAdd.exists, "no + beside …")
        let shown = codes.filter { learnPage.pairTab($0).exists }
        let hidden = codes.filter { !learnPage.pairTab($0).exists }
        XCTAssertFalse(shown.isEmpty)
        XCTAssertFalse(hidden.isEmpty, "five pairs do not fit a phone")
        XCTAssertLessThan(learnPage.pairTab(shown[shown.count - 1]).frame.minX, learnPage.pairTabMore.frame.minX,
                          "… is last")

        learnPage.pairTabMore.tap()
        XCTAssertTrue(learnPage.overflow.waitForExistence(timeout: TestData.Timeouts.medium), "the sheet")
        for code in hidden {
            XCTAssertTrue(learnPage.overflowRow(code).exists, "a row for \(code)")
        }
        for code in shown {
            XCTAssertFalse(learnPage.overflowRow(code).exists, "\(code) is in the strip")
        }
        XCTAssertTrue(learnPage.overflowAdd.exists, "Add a language")
        let choice = hidden[hidden.count - 1]
        learnPage.overflowRow(choice).tap()
        XCTAssertTrue(learnPage.overflow.waitForNonExistence(timeout: TestData.Timeouts.medium), "the sheet closes")
        let tab = learnPage.pairTab(choice)
        XCTAssertTrue(tab.waitForExistence(timeout: TestData.Timeouts.medium), "its tab shows in the strip")
        XCTAssertTrue(tab.isSelected, "and is selected")
        XCTAssertLessThan(tab.frame.minX, learnPage.pairTabMore.frame.minX, "before …")
    }

    /// The strip is a tab bar; a tab reads its pair name and is selected
    /// when it is; "…" reads "More languages", "+" "Add a language".
    func testTabsAccessibility() throws {
        XCTAssertTrue(learnPage.pairTabs.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(learnPage.pairTab("ell").label, "Greek · via English")
        XCTAssertTrue(learnPage.pairTab("ell").isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Greek · via English")).count, 1,
                       "the hidden measuring copies are not exposed to VoiceOver")
        if learnPage.pairTabMore.exists {
            XCTAssertEqual(learnPage.pairTabMore.label, "More languages")
        } else {
            XCTAssertEqual(learnPage.pairTabAdd.label, "Add a language")
        }
        // The app's own tab bar still answers to `app.tabBars`: the strip's
        // `isTabBar` trait must not make it the first match.
        XCTAssertTrue(app.tabButton(.learn).exists)
        if !isPad {
            XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 4, "the main tab bar, not the pair strip")
            XCTAssertEqual(app.tabBars.firstMatch.buttons.element(boundBy: 1).label, "Learn")
        }
    }

    // MARK: - Order and Stop learning

    /// English dragged onto Greek's leading half: the strip reads English,
    /// Greek, and a relaunch without `-resetData` keeps it.
    func testDraggedOrderSurvivesRelaunch() throws {
        let greek = learnPage.pairTab("ell"), english = learnPage.pairTab("eng")
        XCTAssertTrue(greek.waitForExistence(timeout: TestData.Timeouts.medium))
        try XCTSkipIf(learnPage.pairTabMore.exists, "a narrow phone hides English behind …: no tab to drag")
        XCTAssertTrue(english.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertLessThan(greek.frame.minX, english.frame.minX)
        // The drag's coordinates differ by simulator architecture (#6): try
        // the leading edge, then a little inside it, until the order changes.
        for dx in [0.1, 0.25, 0.4] {
            let from = english.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = greek.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
            from.press(forDuration: 0.6, thenDragTo: to)
            if learnPage.pairTab("eng").frame.minX < learnPage.pairTab("ell").frame.minX { break }
        }
        XCTAssertLessThan(learnPage.pairTab("eng").frame.minX, learnPage.pairTab("ell").frame.minX,
                          "English first after the drag")

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt"] + UITestHelpers.packArguments()
        app.launch()
        tabBarPage = TabBarPage(app: app)
        learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long))
        XCTAssertTrue(learnPage.pairTab("eng").waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertLessThan(learnPage.pairTab("eng").frame.minX, learnPage.pairTab("ell").frame.minX,
                          "the order is kept")
    }

    /// A long press on English's tab: Stop learning, its alert; the tab goes
    /// and Greek's shows. "+" brings English back, last, with its 2 due
    /// words.
    func testStopLearningFromTheTab() throws {
        let english = learnPage.pairTab("eng")
        learnPage.selectTab("eng")
        XCTAssertTrue(english.waitForExistence(timeout: TestData.Timeouts.medium))
        english.press(forDuration: 1.2)
        let stop = app.buttons[AccessibilityIdentifiers.Learn.pairTabStop].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: TestData.Timeouts.medium), "the menu's Stop learning")
        stop.tap()
        XCTAssertTrue(app.alerts["Stop learning English?"].waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts["Your progress is kept."].exists)
        app.alerts.firstMatch.buttons["learn_pair_tab_stop_confirm"].firstMatch.tap()
        XCTAssertTrue(learnPage.pairTab("eng").waitForNonExistence(timeout: TestData.Timeouts.medium), "no English tab")
        XCTAssertTrue(learnPage.pairTab("ell").isSelected, "Greek's tab is selected")

        learnPage.pairTabAdd.tap()
        XCTAssertTrue(learnPage.waitForPicker())
        XCTAssertTrue(learnPage.pickerRow("eng", via: "eng").waitForExistence(timeout: TestData.Timeouts.medium))
        learnPage.pickerRow("eng", via: "eng").tap()
        XCTAssertTrue(learnPage.waitForHome())
        XCTAssertTrue(learnPage.pairTab("eng").waitForExistence(timeout: TestData.Timeouts.medium), "English is back")
        XCTAssertTrue(learnPage.pairTab("eng").isSelected)
        if learnPage.pairTab("ell").exists {
            XCTAssertLessThan(learnPage.pairTab("ell").frame.minX, learnPage.pairTab("eng").frame.minX, "last")
        }
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"), "its progress is kept")
    }

    // MARK: - Shared goal and streak

    /// `stats`: the goal ring and the streak read the same on both tabs.
    func testGoalAndStreakShared() throws {
        XCTAssertTrue(learnPage.goalRing.waitForExistence(timeout: TestData.Timeouts.medium))
        let ring = learnPage.goalRing.value as? String, streak = learnPage.streak.value as? String
        XCTAssertNotNil(ring)
        XCTAssertNotNil(streak)
        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.goalRing.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(learnPage.goalRing.value as? String, ring, "the same ring on the English tab")
        XCTAssertEqual(learnPage.streak.value as? String, streak, "the same streak")
    }

    // MARK: - One language per tab

    /// Greek's tab has the Grammar section with the topics and Conjugation
    /// right below; English's has neither.
    func testGrammarSectionPerLanguage() throws {
        XCTAssertTrue(app.scrollToElement(learnPage.grammarRow), "Greek: Topics")
        XCTAssertTrue(learnPage.trainerConjugation.exists, "Greek: Conjugation")
        XCTAssertGreaterThan(learnPage.grammarRow.frame.minY, learnPage.trainerMatch.frame.minY, "after the trainers")
        XCTAssertGreaterThan(learnPage.trainerConjugation.frame.minY, learnPage.grammarRow.frame.minY,
                             "Conjugation below Topics")

        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.trainerRecognition.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.grammarRow.exists, "English: no Topics")
        XCTAssertFalse(learnPage.trainerConjugation.exists, "English: no Conjugation")
        XCTAssertFalse(app.staticTexts["Grammar"].exists, "English: no Grammar section")
    }

    /// Greek with nothing to learn: the trainers' footer, and Conjugation
    /// enabled in Grammar.
    func testConjugationWhileTrainersAreOff() throws {
        XCTAssertTrue(learnPage.trainerRecognition.waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertFalse(learnPage.trainerRecognition.isEnabled)
        XCTAssertTrue(app.staticTexts["Learn a few words first"].exists, "the trainers' footer")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "Conjugation")
        XCTAssertTrue(learnPage.trainerConjugation.isEnabled)
    }

    /// On English's tab: My words lists the English words only, All lists
    /// the English section, Statistics its numbers.
    func testListsMyWordsStatisticsPerTab() throws {
        learnPage.selectLanguage(named: "English")
        let myWords = learnPage.tapMyWords()
        XCTAssertTrue(myWords.waitForWord("house"), "house")
        XCTAssertFalse(myWords.containsWord("γράφω"), "no Greek word on English's tab")
        learnPage.popToRoot()

        let lists = learnPage.tapAllLists()
        XCTAssertTrue(lists.row("cefr-eng-a1").waitForExistence(timeout: TestData.Timeouts.medium), "English A1")
        XCTAssertFalse(lists.row("ky-ell-a1").exists, "no Greek list")
        lists.goBack()
        // Statistics follow the tab: StatisticsFlowTests.testStatisticsFollowTheTab.
    }

    /// Scrolls the strip so a tab that is not visible comes into view; false
    /// when it never does.
    private func reveal(_ tab: XCUIElement) -> Bool {
        for _ in 0..<3 where !tab.exists {
            learnPage.pairTabs.swipeLeft()
        }
        return tab.exists
    }
}
