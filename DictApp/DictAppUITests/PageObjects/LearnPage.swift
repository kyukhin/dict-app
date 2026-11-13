import XCTest

/// The Learn tab (0131, #158): "Which language do you want to learn?", a
/// row per pair, while no language is learned (`-resetData` without
/// `-learningLanguages`), else the Learn home.
class LearnPage: BasePage {
    private typealias IDs = AccessibilityIdentifiers.Learn

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    var home: XCUIElement { element(IDs.view) }
    var picker: XCUIElement { element(IDs.languagePicker) }
    var dueCount: XCUIElement { app.staticTexts[IDs.dueCount].firstMatch }
    var newCount: XCUIElement { app.staticTexts[IDs.newCount].firstMatch }
    var allDone: XCUIElement { app.staticTexts[IDs.allDone].firstMatch }
    var importList: XCUIElement { app.buttons[IDs.importList].firstMatch }
    var addWordsHint: XCUIElement { app.staticTexts[IDs.addWordsHint].firstMatch }
    var myWordsRow: XCUIElement { element(IDs.myWordsRow) }
    /// Pair tabs (0131, #293): the strip, a tab by language code, "+", "…" and its sheet.
    var pairTabs: XCUIElement { element(IDs.pairTabs) }
    func pairTab(_ lang: String) -> XCUIElement { app.buttons[IDs.pairTab(lang)].firstMatch }
    var pairTabAdd: XCUIElement { app.buttons[IDs.pairTabAdd].firstMatch }
    var pairTabMore: XCUIElement { app.buttons[IDs.pairTabMore].firstMatch }
    var overflow: XCUIElement { element(IDs.pairOverflow) }
    func overflowRow(_ lang: String) -> XCUIElement { app.buttons[IDs.pairOverflowRow(lang)].firstMatch }
    var overflowAdd: XCUIElement { app.buttons[IDs.pairOverflowAdd].firstMatch }
    var grammarRow: XCUIElement { element(AccessibilityIdentifiers.Grammar.learnRow) }
    var trainerRecognition: XCUIElement { app.buttons[IDs.trainerRecognition].firstMatch }
    var trainerProduction: XCUIElement { app.buttons[IDs.trainerProduction].firstMatch }
    var trainerMatch: XCUIElement { app.buttons[IDs.trainerMatch].firstMatch }
    var startButton: XCUIElement { app.buttons[IDs.startButton].firstMatch }
    var continueButton: XCUIElement { app.buttons[IDs.continueButton].firstMatch }
    var mistakesRow: XCUIElement { app.buttons[IDs.mistakesRow].firstMatch }
    /// 0166, #164: the ring's value is `12/20`, the streak's `5`.
    var goalRing: XCUIElement { app.buttons[IDs.goalRing].firstMatch }
    var streak: XCUIElement { app.buttons[IDs.streak].firstMatch }
    var statisticsRow: XCUIElement { element(IDs.statisticsRow) }
    /// 0237: the chosen pair's install row, its failure and Try again.
    var installRow: XCUIElement { element(IDs.installRow) }
    var installError: XCUIElement { element(IDs.installError) }
    var installRetry: XCUIElement { app.buttons[IDs.installRetry].firstMatch }

    /// 0130, #154: Today's "Choose lists" and the Lists section's rows.
    var chooseLists: XCUIElement { element(IDs.chooseLists) }
    var newWordsFromRow: XCUIElement { element(IDs.newWordsFromRow) }
    var allListsRow: XCUIElement { element(IDs.allListsRow) }

    /// The Lists section's row of the checked list `id`.
    func listRow(_ id: String) -> XCUIElement {
        element(IDs.listRow(id))
    }

    /// The progress bar of the checked list `id` in the Lists section.
    func listProgress(_ id: String) -> XCUIElement {
        element(IDs.listProgress(id))
    }

    /// The picker's row of the pair `lang` via `via`.
    func pickerRow(_ lang: String, via: String) -> XCUIElement {
        app.buttons[IDs.languagePickerRow(lang, via: via)].firstMatch
    }

    /// A limited pair's warning under its row.
    func pickerLimited(_ lang: String, via: String) -> XCUIElement {
        element(IDs.languagePickerLimited(lang, via: via))
    }

    /// The size to download under a row.
    func pickerSize(_ lang: String, via: String) -> XCUIElement {
        element(IDs.languagePickerSize(lang, via: via))
    }

    // MARK: - Actions

    /// Pops what the tab has pushed (lists, a Definition) until the home
    /// or the picker shows: selecting a tab does not pop its stack on most
    /// devices (see `TabBarPage.popDetailToRootIfNeeded`). Taps the leading
    /// nav-bar button, the back button, by index.
    func popToRoot() {
        for _ in 0..<4 {
            if waitForLearnToLoad(timeout: TestData.Timeouts.short) { return }
            let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
            guard back.exists, back.isHittable else { return }
            back.tap()
        }
    }

    /// Chooses the pair `lang` via `via` in the picker and waits for the home.
    @discardableResult
    func choosePair(_ lang: String, via: String) -> Bool {
        let row = pickerRow(lang, via: via)
        guard row.waitForExistence(timeout: TestData.Timeouts.medium) else { return false }
        row.tap()
        return waitForHome()
    }

    /// Taps the pair tab of the language named `name` ("English", "Greek").
    func selectLanguage(named name: String) {
        let codes = ["Greek": "ell", "English": "eng", "Spanish": "spa", "Russian": "rus", "Arabic": "arb"]
        guard let code = codes[name] else { return XCTFail("no tab for \(name)") }
        selectTab(code)
    }

    /// Taps the pair tab `lang` and waits until it is selected. The strip
    /// scrolls with the home (0131), which keeps its scroll back from a
    /// pushed screen: after a row further down (Statistics) the lazy List
    /// has dropped the tabs, so this scrolls back up to them first (#323).
    func selectTab(_ lang: String) {
        revealBelowNavigationBar(pairTabs)
        let tab = pairTab(lang)
        XCTAssertTrue(tab.waitForExistence(timeout: TestData.Timeouts.medium) || pairTabMore.exists, "the \(lang) tab")
        if !tab.exists {
            // Behind "…" (a narrow phone): choose it in the sheet.
            pairTabMore.tap()
            XCTAssertTrue(overflowRow(lang).waitForExistence(timeout: TestData.Timeouts.medium), "\(lang) in the sheet")
            overflowRow(lang).tap()
            XCTAssertTrue(tab.waitForExistence(timeout: TestData.Timeouts.medium), "the \(lang) tab, shown")
        }
        if !tab.isSelected { tab.tap() }
        let selected = NSPredicate(format: "isSelected == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tab)],
                                      timeout: TestData.Timeouts.medium), .completed, "the \(lang) tab is selected")
    }

    /// Opens the Recognition or Production trainer (#159).
    @discardableResult
    func openTrainer(production: Bool = false) -> ExercisePage {
        let row = production ? trainerProduction : trainerRecognition
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the trainer row")
        XCTAssertTrue(row.isEnabled, "the trainer is enabled")
        row.tap()
        let page = ExercisePage(app: app)
        XCTAssertTrue(page.view.waitForExistence(timeout: TestData.Timeouts.medium), "the run")
        return page
    }

    /// Match the pairs (#160).
    @discardableResult
    func openMatch() -> MatchPairsPage {
        XCTAssertTrue(trainerMatch.waitForExistence(timeout: TestData.Timeouts.medium), "the Match the pairs row")
        XCTAssertTrue(trainerMatch.isEnabled, "Match the pairs is enabled")
        trainerMatch.tap()
        let page = MatchPairsPage(app: app)
        XCTAssertTrue(page.view.waitForExistence(timeout: TestData.Timeouts.medium), "match the pairs")
        return page
    }

    /// 0132, #168: the Conjugation row, while Greek is chosen.
    var trainerConjugation: XCUIElement {
        app.descendants(matching: .any)[AccessibilityIdentifiers.Conjugation.trainerRow].firstMatch
    }

    /// Opens the Conjugation screen from its Trainers row.
    @discardableResult
    func openConjugation() -> ConjugationPage {
        let row = trainerConjugation
        app.scrollToElement(row)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Conjugation row")
        row.tap()
        let page = ConjugationPage(app: app)
        XCTAssertTrue(page.waitForScreen(), "the Conjugation screen")
        return page
    }

    /// Start: the daily session (#161).
    @discardableResult
    func startSession() -> ExercisePage {
        open(startButton, "Start")
    }

    /// Continue lesson (#296).
    @discardableResult
    func continueLesson() -> ExercisePage {
        open(continueButton, "Continue lesson")
    }

    /// Practise mistakes (#161).
    @discardableResult
    func openMistakes() -> ExercisePage {
        open(mistakesRow, "the mistakes row")
    }

    private func open(_ row: XCUIElement, _ name: String) -> ExercisePage {
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), name)
        row.tap()
        let page = ExercisePage(app: app)
        XCTAssertTrue(page.view.waitForExistence(timeout: TestData.Timeouts.medium), "the run")
        return page
    }

    /// "All lists": the Lists screen.
    @discardableResult
    func tapAllLists() -> WordListsPage {
        let row = allListsRow
        // Below the goal ring and the trainers (#164): the lazy List builds
        // it only once scrolled to.
        app.scrollToElement(row)
        XCTAssertTrue(row.waitForExistence(timeout: TestData.Timeouts.medium), "the Lists section's All lists")
        row.tap()
        let page = WordListsPage(app: app)
        XCTAssertTrue(page.waitForLists(), "All lists opens the Lists screen")
        return page
    }

    /// "Choose lists": New words from.
    @discardableResult
    func tapChooseLists() -> WordListsPage {
        XCTAssertTrue(chooseLists.waitForExistence(timeout: TestData.Timeouts.medium), "Today offers Choose lists")
        revealBelowNavigationBar(chooseLists)
        chooseLists.tap()
        let page = WordListsPage(app: app)
        XCTAssertTrue(page.waitForNewWordsFrom(), "Choose lists opens New words from")
        return page
    }

    /// Swipes the home down until `row` is on screen below the navigation
    /// bar. Back from a pushed screen, the home keeps its scroll, and Today's
    /// rows can sit under the iOS 26 bar, which floats over the list: the row
    /// exists and is in the window, but a tap lands on the bar (#281, #181).
    private func revealBelowNavigationBar(_ row: XCUIElement) {
        let bar = app.navigationBars.firstMatch
        for _ in 0..<6 {
            if row.exists && (!bar.exists || row.frame.minY >= bar.frame.maxY) { return }
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertGreaterThanOrEqual(row.frame.minY, bar.frame.maxY, "\(row) clear of the navigation bar")
    }

    /// Statistics (#164), from its row at the bottom of the home, or from
    /// `row` (the ring or the streak).
    @discardableResult
    func openStatistics(from row: XCUIElement? = nil) -> StatisticsPage {
        let target = row ?? statisticsRow
        if row == nil {
            // Below the Lists section (#154): the lazy List builds it only
            // once scrolled to.
            app.scrollToElement(target)
        }
        XCTAssertTrue(target.waitForExistence(timeout: TestData.Timeouts.medium), "the way to Statistics")
        target.tap()
        let page = StatisticsPage(app: app)
        XCTAssertTrue(page.waitForScreen(), "Statistics")
        return page
    }

    @discardableResult
    func tapMyWords() -> MyWordsPage {
        app.scrollToElement(myWordsRow)
        XCTAssertTrue(myWordsRow.waitForExistence(timeout: TestData.Timeouts.medium), "the My words row")
        myWordsRow.tap()
        return MyWordsPage(app: app)
    }

    // MARK: - Verification

    /// The picker or the home, whichever the state gives.
    func waitForLearnToLoad(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if home.exists || picker.exists { return true }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return home.exists || picker.exists
    }

    func waitForHome(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        home.waitForExistence(timeout: timeout)
    }

    func waitForPicker(timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        picker.waitForExistence(timeout: timeout)
    }

    /// Waits until `element`'s label equals `label`.
    func waitForLabel(of element: XCUIElement, toBe label: String,
                      timeout: TimeInterval = TestData.Timeouts.medium) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
