import XCTest

/// 0134, #178: example sentences on the Definition screen, from the Greek
/// pack and the English lists pack, and Tatoeba in Credits.
///
/// - An example is one VoiceOver element (`example_<n>`) whose label reads
///   the sentence, the translation and "From Tatoeba: Zeus and CH"; its
///   lines are not separate elements, so the tests read that label.
/// - The examples are the committed packs' (`Packs/`), as the build chose
///   them: γράφω's first is "Έγραψε ένα γράμμα." by Zeus, translated by CH
///   ("She wrote a letter.") and by odexed ("Она написала письмо.").
/// - Greek is typed through `SearchPage.searchFor`. If "search field should
///   contain typed term" fails, check the simulator's hardware keyboard.
final class ExampleSentencesTests: XCTestCase {

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    private typealias IDs = AccessibilityIdentifiers.Examples

    /// The packs each test installs: the English lists pack alone for the
    /// English word, the Greek pack alone to show that English needs the
    /// lists pack, else every pack.
    private var packs: String {
        if name.contains("testEnglishWordShowsExamples") { return "eng-lists" }
        if name.contains("testEnglishWordWithoutTheListsPackShowsNone") { return "ell" }
        return "all"
    }

    /// The UI language and text size, per test.
    private var extraArguments: [String] {
        if name.contains("testRussianUIShowsRussianTranslation") { return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"] }
        if name.contains("testEnglishWordShowsExamples") { return ["-AppleLanguages", "(es)", "-AppleLocale", "es"] }
        if name.contains("testExamplesFitAtTheLargestTextSize") {
            return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        return []
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A subset of the packs starts from none (`-resetPacks`): an earlier
        // test's packs stay installed otherwise.
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + (packs == "all" ? [] : ["-resetPacks"])
            + UITestHelpers.packArguments(packs) + extraArguments
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
        XCTAssertTrue(app.waitForDictionariesReady(), "Search after launch")
        tabBarPage = TabBarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Tests

    /// γράφω: the Examples section between the definition and the table,
    /// 3 examples, each with its sentence, its English translation and
    /// "From Tatoeba: …"; More shows 5 and reads "Fewer examples", which
    /// hides them again.
    func testGreekWordShowsExamples() throws {
        let page = open("γράφω", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(page.waitForExamples(), "γράφω has examples")
        XCTAssertEqual(page.examplesTitle.label, "Examples")
        XCTAssertEqual(page.shownExamples.count, 3, "3 show")
        XCTAssertEqual(page.example(1).label, "Έγραψε ένα γράμμα. She wrote a letter. From Tatoeba: Zeus and CH")
        for n in 1...3 {
            let label = page.example(n).label
            XCTAssertTrue(label.contains(" From Tatoeba: "), "example \(n) names its authors: \(label)")
            XCTAssertNotNil(label.range(of: "[A-Za-z]{2,}.* From Tatoeba", options: .regularExpression),
                            "example \(n) has an English translation: \(label)")
        }
        let table = app.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.table].firstMatch
        let definition = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionContent].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: TestData.Timeouts.medium), "γράφω has a table")
        XCTAssertLessThanOrEqual(definition.frame.maxY, page.examplesSection.frame.minY + 1, "below the definition")
        XCTAssertLessThanOrEqual(page.examplesSection.frame.maxY, table.frame.minY + 1, "above the table")
        attachScreenshot("γράφω, examples")

        let more = page.examplesMoreButton
        XCTAssertTrue(reveal(more), "More is reachable")
        XCTAssertEqual(more.label, "More examples")
        more.tap()
        XCTAssertTrue(page.example(5).waitForExistence(timeout: TestData.Timeouts.medium), "More shows 5")
        XCTAssertEqual(page.shownExamples.count, 5)
        XCTAssertEqual(page.examplesMoreButton.label, "Fewer examples")
        XCTAssertTrue(reveal(page.example(5)))
        attachScreenshot("γράφω, all examples")
        XCTAssertTrue(reveal(page.examplesMoreButton))
        page.examplesMoreButton.tap()
        XCTAssertTrue(page.example(4).waitForNonExistence(timeout: TestData.Timeouts.medium), "Fewer hides them")
        XCTAssertEqual(page.examplesMoreButton.label, "More examples")
    }

    /// The Russian UI shows γράφω's Russian translation where Tatoeba has
    /// one (the English UI's is Latin, above), with "Из Tatoeba: Zeus и
    /// odexed".
    func testRussianUIShowsRussianTranslation() throws {
        let page = open("γράφω", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(page.waitForExamples(), "γράφω has examples")
        XCTAssertEqual(page.examplesTitle.label, "Примеры")
        XCTAssertEqual(page.example(1).label, "Έγραψε ένα γράμμα. Она написала письмо. Из Tatoeba: Zeus и odexed")
        XCTAssertNotNil(page.example(2).label.range(of: "\\p{Cyrillic}{3,}", options: .regularExpression),
                        "a Russian translation: \(page.example(2).label)")
        XCTAssertTrue(reveal(page.examplesMoreButton))
        XCTAssertEqual(page.examplesMoreButton.label, "Ещё примеры")
        attachScreenshot("γράφω, examples (ru)")
    }

    /// house from WordNet, with the English lists pack only, in a Spanish
    /// UI: the section, the first example translated into Spanish.
    func testEnglishWordShowsExamples() throws {
        let page = open("house", source: TestData.Sources.wordnet)
        XCTAssertTrue(page.waitForExamples(), "house is a word of the English lists")
        XCTAssertEqual(page.examplesTitle.label, "Ejemplos")
        XCTAssertEqual(page.example(1).label,
                       "Who owns this house? ¿Quién es el dueño de esta casa? De Tatoeba: CK y Shishir")
        XCTAssertGreaterThanOrEqual(page.shownExamples.count, 3)
        attachScreenshot("house, examples (es)")
    }

    /// Without the English lists pack, an English word shows no section.
    func testEnglishWordWithoutTheListsPackShowsNone() throws {
        let page = open("house", source: TestData.Sources.wordnet)
        XCTAssertTrue(page.waitForExamples(false, timeout: TestData.Timeouts.short), "no English lists pack: no examples")
        XCTAssertFalse(page.example(1).exists)
    }

    /// A word without examples shows no section and no empty state.
    func testWordWithoutExamplesShowsNoSection() throws {
        let page = open("Αμβέρσα", query: "αμβέρσα", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(page.waitForExamples(false, timeout: TestData.Timeouts.short), "Αμβέρσα has none")
        XCTAssertFalse(page.examplesTitle.exists)
    }

    /// λύπη has exactly 3 examples in the Greek pack: all show, and there
    /// is no More button (hidden with 3 or fewer).
    func testThreeExamplesShowNoMoreButton() throws {
        let page = open("λύπη", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(page.waitForExamples(), "λύπη has examples")
        XCTAssertTrue(reveal(page.example(3)), "the third example")
        XCTAssertEqual(page.shownExamples.count, 3, "all 3 show")
        XCTAssertFalse(page.example(4).exists)
        XCTAssertFalse(page.examplesMoreButton.exists, "no More with 3 examples")
    }

    /// Credits names Tatoeba and its license.
    func testCreditsListTatoeba() throws {
        _ = tabBarPage.tapSettingsTab()
        let link = app.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.creditsLink].firstMatch
        XCTAssertTrue(app.scrollToElement(link), "the Credits row must be reachable in Settings")
        link.tap()
        let line = app.staticTexts[IDs.creditsTatoeba]
        XCTAssertTrue(line.waitForExistence(timeout: TestData.Timeouts.medium) || app.scrollToElement(line),
                      "Credits must list Tatoeba")
        XCTAssertEqual(line.label, "Example sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR. Each example names its authors.")
    }

    /// At the largest accessibility text size every example lies inside the
    /// window's width, wrapping rather than cut, and More stays reachable.
    func testExamplesFitAtTheLargestTextSize() throws {
        let page = open("γράφω", source: TestData.Sources.freedictEllEng)
        XCTAssertTrue(page.waitForExamples(), "γράφω has examples")
        XCTAssertTrue(reveal(page.examplesMoreButton), "More is reachable")
        page.examplesMoreButton.tap()
        XCTAssertTrue(page.example(5).waitForExistence(timeout: TestData.Timeouts.medium))
        let window = app.windows.firstMatch.frame
        for element in [page.examplesTitle] + page.shownExamples {
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(element.identifier) inside the window")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(element.identifier) inside the window")
        }
        XCTAssertTrue(reveal(page.example(1)))
        attachScreenshot("γράφω, examples, largest text size")
        XCTAssertTrue(reveal(page.examplesMoreButton), "Fewer is reachable")
    }

    // MARK: - Helpers

    /// Searches `query` (default: `word`) and opens `word` from `source`.
    private func open(_ word: String, query: String? = nil, source: String) -> DefinitionPage {
        _ = InflectionTablePage.open(word, query: query, source: source, from: tabBarPage.tapSearchTab(), app: app,
                                     expectsTable: false)
        return DefinitionPage(app: app)
    }

    /// Swipes the Definition screen until `element` is in view.
    private func reveal(_ element: XCUIElement) -> Bool {
        InflectionTablePage(app: app).reveal(element)
    }

    /// Keeps a full-screen screenshot in the result bundle for a human check.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
