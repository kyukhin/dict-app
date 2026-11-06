import XCTest

/// Issue #144 — inflection tables on the Definition screen of a Greek
/// headword (0136-word-forms.md, "Inflection tables (#144)").
///
/// - Cells are found by id (`AccessibilityIdentifiers.Inflection`); a cell's
///   `label` is its VoiceOver text, "column, row, form".
/// - Each cell id must exist once: `ViewThatFits` shows one rendering only.
/// - Greek is typed through `SearchPage.searchFor`. If "search field should
///   contain typed term" fails, check the simulator's hardware keyboard.
/// - Screenshots of each table are kept in the result bundle for a human check.
final class InflectionTableTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private typealias IDs = AccessibilityIdentifiers.Inflection

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-disableReviewPrompt", "-resetData"]
        // Issue #237: every language pack, installed from the committed assets.
        app.launchArguments += UITestHelpers.packArguments()
        // "All forms" puts hundreds of cells in the AX tree: silence the app's
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
        app.launch()
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Tests

    /// γράφω shows Present, Imperfect, Aorist, Future and the imperative;
    /// "All forms" adds the perfect tenses and the passive, and "Main forms"
    /// hides them again.
    func testVerbMainAndAllForms() throws {
        let page = openGrafo()
        let main: [(String, String)] = [
            (IDs.verbCell(slot: "present", person: "1sg"), "γράφω"),
            (IDs.verbCell(slot: "imperfect", person: "1sg"), "έγραφα"),
            (IDs.verbCell(slot: "aorist", person: "1sg"), "έγραψα"),
            (IDs.verbCell(slot: "future", person: "1sg"), "θα γράψω"),
            (IDs.verbCell(slot: "imperative_continuous", person: "2sg"), "γράφε"),
            (IDs.verbCell(slot: "imperative_simple", person: "2sg"), "γράψε"),
        ]
        for (id, form) in main {
            XCTAssertEqual(page.count(id), 1, "\(id) is shown once")
            XCTAssertTrue(page.cell(id).label.hasSuffix(form), "\(id) reads \(form); got '\(page.cell(id).label)'")
        }
        let passiveAorist = IDs.verbCell(voice: "passive", slot: "aorist", person: "1sg")
        let perfect = IDs.verbCell(slot: "perfect", person: "1sg")
        XCTAssertFalse(page.cell(passiveAorist).exists, "the passive waits for All forms")
        XCTAssertFalse(page.cell(perfect).exists, "the perfect waits for All forms")
        XCTAssertTrue(page.reveal(page.cell(IDs.verbCell(slot: "present", person: "1sg"))))
        attachScreenshot("γράφω, main forms")

        XCTAssertEqual(page.allFormsButton.label, "All forms")
        page.tapAllForms()
        XCTAssertTrue(page.cell(passiveAorist).waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(page.cell(passiveAorist).label, "passive, aorist, εγώ, γράφτηκα / γράφηκα")
        XCTAssertEqual(page.cell(perfect).label, "perfect, εγώ, έχω γράψει")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "future_perfect", person: "1sg")).label,
                       "future perfect, εγώ, θα έχω γράψει")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "subjunctive_simple", person: "1sg")).label,
                       "subjunctive, simple, εγώ, να γράψω")
        XCTAssertEqual(page.cell(IDs.nonfiniteCell(voice: "passive", slot: "past_participle")).label,
                       "passive, past participle, γραμμένος")
        XCTAssertEqual(page.allFormsButton.label, "Main forms")
        XCTAssertTrue(page.reveal(page.cell(IDs.verbCell(slot: "future_continuous", person: "1sg"))))
        attachScreenshot("γράφω, all forms (active)")
        XCTAssertTrue(page.reveal(page.cell(passiveAorist)))
        attachScreenshot("γράφω, all forms (passive)")

        page.tapAllForms()
        XCTAssertTrue(page.cell(passiveAorist).waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "Main forms collapses the table again")
        XCTAssertEqual(page.allFormsButton.label, "All forms")
    }

    /// σπίτι: case × number; καλός: case × gender for the singular and the
    /// plural. Neither has "All forms". FreeDict's καλός is "adjective, noun"
    /// and shows the adjective's table: its labels are tried in their order.
    func testNounAndAdjectiveTables() throws {
        var page = InflectionTablePage.open("σπίτι", source: TestData.Sources.freedictEllEng,
                                            from: tabBarPage.tapSearchTab(), app: app)
        for (grammaticalCase, singular, plural) in [("nominative", "σπίτι", "σπίτια"), ("genitive", "σπιτιού", "σπιτιών"),
                                                    ("accusative", "σπίτι", "σπίτια"), ("vocative", "σπίτι", "σπίτια")] {
            XCTAssertEqual(page.cell(IDs.nominalCell(case: grammaticalCase, number: "singular")).label,
                           "\(grammaticalCase), singular, \(singular)")
            XCTAssertEqual(page.cell(IDs.nominalCell(case: grammaticalCase, number: "plural")).label,
                           "\(grammaticalCase), plural, \(plural)")
        }
        XCTAssertFalse(page.allFormsButton.exists, "a noun shows its whole table")
        XCTAssertTrue(page.reveal(page.table))
        attachScreenshot("σπίτι")
        page.goBack()

        page = InflectionTablePage.open("καλός", source: TestData.Sources.freedictEllEng,
                                        from: SearchPage(app: app), app: app)
        let cells: [(String, String, String, String)] = [
            ("nominative", "singular", "masculine", "καλός"), ("nominative", "singular", "feminine", "καλή"),
            ("nominative", "singular", "neuter", "καλό"), ("genitive", "singular", "masculine", "καλού"),
            ("accusative", "plural", "masculine", "καλούς"), ("vocative", "plural", "neuter", "καλά"),
        ]
        for (grammaticalCase, number, gender, form) in cells {
            let id = IDs.nominalCell(case: grammaticalCase, number: number, gender: gender)
            XCTAssertEqual(page.count(id), 1, "\(id) is shown once")
            XCTAssertEqual(page.cell(id).label, "\(grammaticalCase), \(number), \(gender), \(form)")
        }
        XCTAssertFalse(page.allFormsButton.exists)
        XCTAssertTrue(page.reveal(page.cell(IDs.nominalCell(case: "nominative", number: "singular", gender: "masculine"))))
        attachScreenshot("καλός")
    }

    /// VoiceOver reads a cell as "column, row, form", and each data cell is
    /// one element.
    func testCellLabel() throws {
        let page = openGrafo()
        let aorist = page.cell(IDs.verbCell(slot: "aorist", person: "1sg"))
        XCTAssertEqual(aorist.label, "aorist, εγώ, έγραψα")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "imperfect", person: "3pl")).label,
                       "imperfect, αυτοί, έγραφαν / γράφαν / γράφανε")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "imperative_simple", person: "2pl")).label,
                       "imperative, simple, εσείς, γράψτε / γράφτε")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", "έγραψα")).firstMatch.exists,
                       "the form is no element of its own: VoiceOver reads the whole cell")
    }

    /// WordNet's πάω has no table of its own and shows πηγαίνω's, which the
    /// title names; an adverb (γρήγορα) shows its definition and no table.
    func testLinkedTableAndWordWithoutATable() throws {
        var page = InflectionTablePage.open("πάω", source: TestData.Sources.wordnetEllEng,
                                            from: tabBarPage.tapSearchTab(), app: app)
        let linked = app.descendants(matching: .any)[IDs.linkedLemma].firstMatch
        XCTAssertTrue(linked.exists, "the title names the lemma whose table this is")
        XCTAssertEqual(linked.label, "πηγαίνω")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "present", person: "1sg")).label, "present, εγώ, πηγαίνω / πάω")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "aorist", person: "1sg")).label, "aorist, εγώ, πήγα")
        page.goBack()

        page = InflectionTablePage.open("γρήγορα", source: TestData.Sources.freedictEllEng,
                                        from: SearchPage(app: app), app: app, expectsTable: false)
        XCTAssertFalse(page.table.waitForExistence(timeout: TestData.Timeouts.short), "an adverb has no table")
        XCTAssertFalse(page.allFormsButton.exists)
        XCTAssertFalse(app.descendants(matching: .any)[IDs.linkedLemma].exists)
    }

    /// Kirill, 2026-10-31: Wiktionary has αγαπώ only as an alternative page
    /// of αγαπάω, so WordNet's αγαπώ shows αγαπάω's table, named under the title.
    func testFormPageShowsItsLemmasTable() throws {
        let page = InflectionTablePage.open("αγαπώ", source: TestData.Sources.wordnetEllEng,
                                            from: tabBarPage.tapSearchTab(), app: app)
        let linked = app.descendants(matching: .any)[IDs.linkedLemma].firstMatch
        XCTAssertTrue(linked.exists, "the title names the lemma whose table this is")
        XCTAssertEqual(linked.label, "αγαπάω")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "present", person: "1sg")).label, "present, εγώ, αγαπάω / αγαπώ")
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "aorist", person: "1sg")).label, "aorist, εγώ, αγάπησα")
        XCTAssertTrue(page.allFormsButton.exists, "a verb's table has All forms")
    }

    /// At the largest accessibility text size the tables still fit the
    /// screen: no cell, and not the definition above them, reaches past
    /// either edge, and each cell shows once. Before the fix σπίτι's
    /// "Accusative | σπιτιού" rows widened the screen and cut its headword,
    /// definition and forms on both sides.
    func testTablesFitTheScreenAtTheLargestTextSize() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tabBarPage = TabBarPage(app: app)

        var page = InflectionTablePage.open("σπίτι", source: TestData.Sources.freedictEllEng,
                                            from: tabBarPage.tapSearchTab(), app: app)
        XCTAssertEqual(page.cell(IDs.nominalCell(case: "accusative", number: "singular")).label,
                       "accusative, singular, σπίτι")
        try assertFitsTheWindow(page, "σπίτι", cells: 8)
        XCTAssertTrue(page.reveal(page.cell(IDs.nominalCell(case: "genitive", number: "singular"))))
        attachScreenshot("σπίτι, largest text size")
        page.goBack()

        page = InflectionTablePage.open("γράφω", source: TestData.Sources.freedictEllEng,
                                        from: SearchPage(app: app), app: app)
        page.tapAllForms()
        XCTAssertTrue(page.cell(IDs.verbCell(voice: "passive", slot: "aorist", person: "1sg"))
            .waitForExistence(timeout: TestData.Timeouts.medium))
        XCTAssertEqual(page.cell(IDs.verbCell(slot: "aorist", person: "1sg")).label, "aorist, εγώ, έγραψα")
        try assertFitsTheWindow(page, "γράφω, all forms", cells: 134)
        XCTAssertTrue(page.reveal(page.cell(IDs.verbCell(slot: "present", person: "2sg"))))
        attachScreenshot("γράφω, largest text size")
    }

    /// #136: Credits names the source of the word forms, Wiktionary via
    /// kaikki.org, with its license.
    func testCreditsListsWiktionary() throws {
        _ = tabBarPage.tapSettingsTab()
        let link = app.descendants(matching: .any)[IDs.creditsLink].firstMatch
        XCTAssertTrue(app.scrollToElement(link), "the Credits row must be reachable in Settings")
        link.tap()
        let line = app.staticTexts[IDs.creditsWiktionary]
        XCTAssertTrue(line.waitForExistence(timeout: TestData.Timeouts.medium), "Credits must list Wiktionary")
        XCTAssertEqual(line.label, "Word forms: Wiktionary contributors, via kaikki.org (CC BY-SA 4.0)")
    }

    // MARK: - Helpers

    private func openGrafo() -> InflectionTablePage {
        InflectionTablePage.open("γράφω", source: TestData.Sources.freedictEllEng,
                                 from: tabBarPage.tapSearchTab(), app: app)
    }

    /// Every cell, and the definition text, lies within the window's width;
    /// `cells` cells are on screen, each once.
    private func assertFitsTheWindow(_ page: InflectionTablePage, _ name: String, cells: Int,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let window = app.windows.firstMatch.frame
        let frames = try page.frames(withPrefixes: ["inflection_cell_", AccessibilityIdentifiers.Definition.definitionContent])
        let cellIDs = frames.map(\.id).filter { $0.hasPrefix("inflection_cell_") }
        XCTAssertEqual(cellIDs.count, cells, "\(name): cells on screen", file: file, line: line)
        XCTAssertEqual(Set(cellIDs).count, cellIDs.count, "\(name): each cell once", file: file, line: line)
        XCTAssertTrue(frames.contains { $0.id == AccessibilityIdentifiers.Definition.definitionContent },
                      "\(name): the definition is on screen", file: file, line: line)
        for (id, frame) in frames where frame.minX < window.minX - 0.5 || frame.maxX > window.maxX + 0.5 {
            XCTFail("\(name): \(id) spans x \(Int(frame.minX))…\(Int(frame.maxX)), the window \(Int(window.minX))…\(Int(window.maxX))",
                    file: file, line: line)
        }
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
