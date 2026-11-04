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
    var languageSwitch: XCUIElement { app.segmentedControls[IDs.languageSwitch].firstMatch }
    var trainerRecognition: XCUIElement { app.buttons[IDs.trainerRecognition].firstMatch }
    var trainerProduction: XCUIElement { app.buttons[IDs.trainerProduction].firstMatch }

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

    /// Pops what the tab has pushed (My words, a Definition) until the home
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

    /// Taps the switch's segment labelled `name` ("English").
    func selectLanguage(named name: String) {
        XCTAssertTrue(languageSwitch.waitForExistence(timeout: TestData.Timeouts.medium), "the language switch")
        languageSwitch.buttons[name].tap()
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

    @discardableResult
    func tapMyWords() -> MyWordsPage {
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
