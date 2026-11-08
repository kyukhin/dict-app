import XCTest

/// 0133, #172: the grammar reader. The Learn home's Grammar row, the Grammar
/// screen (topics by level) and a topic (rule, tables, examples, Watch out,
/// Practise, words, related topics, Reading Mode). English UI with Greek
/// learned via English (`-learningLanguages ell`) unless a test says
/// otherwise; the Greek pack installed from the committed assets;
/// `-resetData` first.
///
/// #174: the Grammar section of a Greek headword's Definition, and Practise
/// on a topic opened from it while Greek is not learned.
final class GrammarFlowTests: XCTestCase {
    private typealias IDs = AccessibilityIdentifiers.Grammar

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!
    var page: GrammarPage!

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testGreekViaRussianReadsRussian") {
            return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru", "-learningLanguages", "ell:rus"]
        }
        if name.contains("testCreditsListsGrammar") || name.contains("testPractiseAsksLearnGreekFirst") { return [] }
        if name.contains("testPractiseOpensTheDrillForThatTense") {
            return ["-learningLanguages", "ell", "-learningLists", "ky-ell-a1", "-drillLength", "3",
                    "-learningSeed", "1", "-learningAnswerHints"]
        }
        return ["-learningLanguages", "ell"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-disableReviewPrompt", "-resetData"] + learningArguments
            + UITestHelpers.packArguments("ell")
        // The pack install and the topics' long texts make the app log
        // heavily; on the iOS 17.5 sim its os_log is then quarantined and
        // XCTAutomationSupport's fault callback segfaults (strcmp on NULL in
        // runtime_issue_os_log_fault_callback), killing the app mid-test.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // iOS 26 "Enable Dictation?" springboard alert on the first search.
        addUIInterruptionMonitor(withDescription: "Enable Dictation alert") { alert in
            for label in ["Not Now", "Cancel", "Don't Enable", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tabBarPage = TabBarPage(app: app)
        page = GrammarPage(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
        page = nil
    }

    // MARK: - Tests

    /// The Learn home's row reads 17 topics; the Grammar screen has one
    /// level, A1, from the alphabet to the imperative, in English with no
    /// note; a row opens its topic.
    func testTopicsByLevel() throws {
        openGrammar()
        XCTAssertFalse(page.englishNote.exists, "Greek via English: no note")
        let header = page.levelHeader("A1")
        XCTAssertTrue(header.waitForExistence(timeout: TestData.Timeouts.medium), "the A1 section")
        XCTAssertFalse(page.levelHeader("A2").exists, "2.0 has A1 only")
        let first = page.topicRow("ell-alphabet")
        XCTAssertTrue(first.waitForExistence(timeout: TestData.Timeouts.medium), "the alphabet's row")
        XCTAssertTrue(first.label.contains("The alphabet"), "titled in English; got '\(first.label)'")
        XCTAssertLessThan(first.frame.minY, page.topicRow("ell-articles").frame.minY, "the alphabet first")
        let last = page.topicRow("ell-imperative")
        XCTAssertTrue(app.scrollToElement(last), "the imperative's row")
        let beforeLast = page.topicRow("ell-na-perfective")
        XCTAssertTrue(beforeLast.exists)
        XCTAssertGreaterThan(last.frame.minY, beforeLast.frame.minY, "the imperative last")
        XCTAssertTrue(page.openTopic("ell-imperative"), "a tap opens the topic")
        XCTAssertTrue(page.topicView.exists)
        XCTAssertEqual(page.title.label, "The imperative")
    }

    /// The aorist topic: rule, a forms table whose first cell is έγραψα,
    /// 3–5 examples, Watch out, Practise for the aorist, its words and
    /// related topics.
    func testTopicStructure() throws {
        openTopic("ell-aorist-regular")
        XCTAssertEqual(page.title.label, "The aorist of regular verbs and the augment")
        XCTAssertEqual(page.level.label, "A1")
        XCTAssertTrue(page.rule.exists, "the rule")
        XCTAssertTrue(page.table(1).exists, "a table")
        let cell = page.cell(1, 0, 0)
        XCTAssertTrue(cell.exists)
        XCTAssertTrue(cell.label.hasSuffix("έγραψα"), "column, row, form; got '\(cell.label)'")
        XCTAssertEqual(cell.label, "γράφω, εγώ, έγραψα")
        let examples = try page.count(withPrefix: "grammar_example_")
        XCTAssertTrue((3...5).contains(examples), "\(examples) examples")
        XCTAssertTrue(page.example(1).label.contains("Yesterday I wrote a letter"),
                      "the Greek sentence, then its translation; got '\(page.example(1).label)'")
        XCTAssertTrue(page.watchOut.exists, "Watch out")
        XCTAssertTrue(page.practiseButton.exists, "Practise")
        XCTAssertEqual(page.practiseButton.label, "Practise · Aorist")
        XCTAssertEqual(page.practiseButton.value as? String, "aorist")
        XCTAssertTrue(page.word("γράφω").exists, "the words")
        XCTAssertTrue(page.related("ell-aorist-irregular").exists, "the related topics")
        XCTAssertFalse(page.englishNote.exists)
        XCTAssertTrue(page.practiseButton.frame.maxY < page.word("γράφω").frame.minY,
                      "Practise above the words")
        XCTAssertTrue(page.word("γράφω").frame.maxY < page.related("ell-aorist-irregular").frame.minY,
                      "the words above the related topics")
        attach("aorist topic")

        // A topic without tenses has no Practise.
        page.goBack()
        XCTAssertTrue(page.openTopic("ell-articles"))
        XCTAssertFalse(page.practiseButton.exists, "no Practise for articles")
    }

    /// A word opens its Definition (El–En · FD), and History records it.
    func testWordLinkOpensDefinition() throws {
        openTopic("ell-aorist-regular")
        let word = page.word("γράφω")
        XCTAssertTrue(word.label.contains("γράφω"))
        XCTAssertTrue(word.label.count > "γράφω".count, "the word with its meaning; got '\(word.label)'")
        page.tapOnTopic(word, "γράφω's row")
        let definition = app.descendants(matching: .any)[AccessibilityIdentifiers.Definition.definitionView].firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: TestData.Timeouts.long), "γράφω's Definition")
        XCTAssertTrue(app.navigationBars["γράφω"].exists, "the Definition of γράφω")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.table].firstMatch
            .waitForExistence(timeout: TestData.Timeouts.medium), "its table: the Greek pack's entry")

        let history = tabBarPage.tapHistoryTab()
        XCTAssertTrue(history.waitForHistoryToLoad())
        XCTAssertTrue(history.verifyHistoryContainsWord("γράφω"), "History records the word")
    }

    /// A related topic opens that topic, which links back.
    func testRelatedTopicOpensTopic() throws {
        openTopic("ell-aorist-regular")
        page.tapOnTopic(page.related("ell-aorist-irregular"), "the irregular aorists link")
        XCTAssertTrue(app.staticTexts.matching(identifier: IDs.title).matching(
            NSPredicate(format: "label == %@", "Irregular aorists")).firstMatch
            .waitForExistence(timeout: TestData.Timeouts.medium), "Irregular aorists opens")
        XCTAssertTrue(page.related("ell-aorist-regular").waitForExistence(timeout: TestData.Timeouts.medium),
                      "it links back")
    }

    /// Greek via Russian (the limited pair) reads the Russian texts in a
    /// Russian UI, with no note; Greek via English reads the same topic in
    /// English.
    func testGreekViaRussianReadsRussian() throws {
        openGrammar(rowValue: "17 тем")
        XCTAssertTrue(app.navigationBars["Грамматика"].exists)
        XCTAssertFalse(page.englishNote.exists, "every topic has a Russian text")
        XCTAssertTrue(page.openTopic("ell-aorist-regular"))
        XCTAssertTrue(Self.isCyrillic(page.title.label), "the title; got '\(page.title.label)'")
        let rule = page.rule.staticTexts.firstMatch
        XCTAssertTrue(Self.isCyrillic(rule.label), "the rule; got '\(rule.label)'")
        let example = page.example(1)
        XCTAssertTrue(example.label.hasPrefix("Χθες"), "the Greek sentence first")
        XCTAssertTrue(Self.isCyrillic(example.label), "its Russian translation; got '\(example.label)'")
        XCTAssertFalse(page.englishNote.exists)
        XCTAssertEqual(page.practiseButton.label, "Тренировать · Аорист", "the UI language")
        attach("aorist topic, Greek via Russian")

        app.terminate()
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-AppleLanguages", "(ru)", "-AppleLocale", "ru",
                               "-learningLanguages", "ell:eng"] + UITestHelpers.packArguments("ell")
        app.launch()
        openTopic("ell-aorist-regular", rowValue: "17 тем")
        XCTAssertEqual(page.title.label, "The aorist of regular verbs and the augment", "Greek via English")
        XCTAssertFalse(Self.isCyrillic(page.rule.staticTexts.firstMatch.label))
        XCTAssertFalse(page.englishNote.exists)
    }

    /// Practise on the aorist topic runs E5's drill of the aorist only, over
    /// Greek A1's verbs, then its summary by tense.
    func testPractiseOpensTheDrillForThatTense() throws {
        openTopic("ell-aorist-regular")
        XCTAssertEqual(page.practiseButton.label, "Practise · Aorist")
        page.tapOnTopic(page.practiseButton, "Practise")
        let drill = ConjugationPage(app: app)
        XCTAssertTrue(drill.run.view.waitForExistence(timeout: TestData.Timeouts.long), "the drill covers the topic")
        var tenses: [String] = []
        while tenses.count < 6, drill.waitForQuestion() {
            tenses.append(drill.promptTense.label)
            XCTAssertEqual(drill.answer(right: true), "right", "question \(tenses.count)")
            drill.run.tapContinue()
        }
        XCTAssertEqual(tenses.count, 3, "-drillLength 3")
        XCTAssertTrue(tenses.allSatisfy { $0.hasPrefix("Aorist") }, "the topic's tense only: \(tenses)")
        XCTAssertTrue(drill.run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertTrue(drill.summaryTense("aorist").exists, "the run by tense: the aorist")
        drill.run.summaryDone.tap()
        XCTAssertTrue(page.title.waitForExistence(timeout: TestData.Timeouts.medium), "back on the topic")
    }

    /// QA (#172, Open question 1): Greek learned with no Greek list checked,
    /// Practise asks first. "Choose lists" opens New words from and starts
    /// nothing; asked again, "Greek A1" starts the drill of the topic's tense.
    func testPractiseWithoutListsAsks() throws {
        openTopic("ell-aorist-regular")
        page.tapOnTopic(page.practiseButton, "Practise")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the question")
        XCTAssertTrue(alert.label.hasPrefix("No Greek list is checked"), "got '\(alert.label)'")
        XCTAssertTrue(alert.buttons["Greek A1"].exists, "Greek A1")
        alert.buttons["Choose lists"].tap()
        let lists = WordListsPage(app: app)
        XCTAssertTrue(lists.waitForNewWordsFrom(), "Choose lists opens New words from")
        XCTAssertFalse(ExercisePage(app: app).view.exists, "nothing starts")

        page.goBack()
        XCTAssertTrue(page.title.waitForExistence(timeout: TestData.Timeouts.medium), "back on the topic")
        page.tapOnTopic(page.practiseButton, "Practise, again")
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "asked again: still no list")
        alert.buttons["Greek A1"].tap()
        let drill = ConjugationPage(app: app)
        XCTAssertTrue(drill.run.view.waitForExistence(timeout: TestData.Timeouts.long), "the drill")
        XCTAssertTrue(drill.waitForQuestion(), "a question")
        XCTAssertTrue(drill.promptTense.label.hasPrefix("Aorist"), "the topic's tense; got '\(drill.promptTense.label)'")
    }

    /// Reading Mode on a topic's toolbar switches on and off.
    func testReadingModeOnTopic() throws {
        openTopic("ell-aorist-regular")
        XCTAssertTrue(page.verifyReadingModeToggleExists(), "the toggle on the topic's toolbar")
        let off = page.readingModeToggle.label
        page.tapReadingModeToggle()
        XCTAssertTrue(page.waitForReadingModeSelected(true), "on")
        XCTAssertNotEqual(page.readingModeToggle.label, off, "its label says so")
        page.tapReadingModeToggle()
        XCTAssertTrue(page.waitForReadingModeSelected(false), "off again")
        XCTAssertEqual(page.readingModeToggle.label, off)
    }

    /// Credits names the grammar notes and their license.
    func testCreditsListsGrammar() throws {
        _ = tabBarPage.tapSettingsTab()
        let link = app.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.creditsLink].firstMatch
        XCTAssertTrue(app.scrollToElement(link), "the Credits row in Settings")
        link.tap()
        let line = app.staticTexts[IDs.creditsGreekGrammar]
        XCTAssertTrue(line.waitForExistence(timeout: TestData.Timeouts.medium) || app.scrollToElement(line),
                      "Credits lists the grammar notes")
        XCTAssertEqual(line.label, "Greek grammar notes: LibreDict (CC BY-SA 4.0)")
    }

    // MARK: - Definition (#174)

    /// γράφω's Definition (El–En · FD) lists its tense topics under the
    /// table and Practise, in topic order; a row opens the topic.
    func testDefinitionLinksOfGrafo() throws {
        openDefinition("γράφω")
        let ids = ["ell-present-1", "ell-aorist-regular", "ell-future", "ell-na-perfective", "ell-imperative"]
        XCTAssertTrue(page.definitionTopic(ids[0]).waitForExistence(timeout: TestData.Timeouts.long),
                      "the Grammar section")
        XCTAssertTrue(page.definitionSection.exists)
        for id in ids {
            XCTAssertTrue(page.definitionTopic(id).exists, id)
        }
        XCTAssertFalse(page.definitionTopic("ell-aorist-irregular").exists, "γράφω is regular")
        XCTAssertFalse(page.definitionTopic("ell-present-2").exists)
        XCTAssertEqual(page.definitionTopic("ell-present-1").label, "Present tense: first conjugation")
        let rows = ids.map { page.definitionTopic($0).frame.minY }
        XCTAssertEqual(rows, rows.sorted(), "topic order")
        let practise = app.buttons[AccessibilityIdentifiers.Conjugation.practiseButton].firstMatch
        XCTAssertTrue(practise.exists, "Practise under the table")
        XCTAssertLessThan(practise.frame.maxY, rows[0], "the section under Practise")

        XCTAssertTrue(page.openDefinitionTopic("ell-aorist-regular"), "a tap opens the topic")
        XCTAssertEqual(page.title.label, "The aorist of regular verbs and the augment")
        XCTAssertTrue(page.practiseButton.exists, "Greek is learned: Practise on the topic")
    }

    /// σπίτι links to articles and noun endings, and to no verb topic.
    func testNounLinksToArticlesAndEndings() throws {
        openDefinition("σπίτι")
        XCTAssertTrue(page.definitionTopic("ell-articles").waitForExistence(timeout: TestData.Timeouts.long),
                      "Articles and gender")
        XCTAssertTrue(page.definitionTopic("ell-noun-endings").exists, "Noun endings")
        XCTAssertFalse(page.definitionTopic("ell-present-1").exists)
        XCTAssertFalse(page.definitionTopic("ell-adjectives").exists)
        XCTAssertTrue(page.openDefinitionTopic("ell-noun-endings"))
        XCTAssertEqual(page.title.label, "Noun endings: nominative and accusative")
    }

    /// QA (#174): a word without a table links by its word alone. El–En ·
    /// FD calls εγώ a noun, yet it gets Personal pronouns only, no noun
    /// topic from that label; the row opens the topic.
    func testWordWithoutATableLinksByWord() throws {
        openDefinition("εγώ", expectsTable: false)
        XCTAssertTrue(page.definitionTopic("ell-pronouns").waitForExistence(timeout: TestData.Timeouts.long),
                      "Personal pronouns")
        XCTAssertTrue(page.definitionSection.exists)
        XCTAssertFalse(InflectionTablePage(app: app).table.exists, "εγώ has no table")
        for id in ["ell-articles", "ell-noun-endings", "ell-possessives", "ell-present-1"] {
            XCTAssertFalse(page.definitionTopic(id).exists, id)
        }
        XCTAssertEqual(page.definitionTopic("ell-pronouns").label, "Personal pronouns, strong and weak")
        XCTAssertTrue(page.openDefinitionTopic("ell-pronouns"), "a tap opens the topic")
        XCTAssertEqual(page.title.label, "Personal pronouns, strong and weak")
        XCTAssertTrue(page.word("εγώ").exists, "the topic lists εγώ")
    }

    /// No learned language: the aorist topic opened from γράφω's Definition
    /// still offers Practise, which asks "Learn Greek via English?" first;
    /// No starts nothing.
    func testPractiseAsksLearnGreekFirst() throws {
        openDefinition("γράφω")
        XCTAssertTrue(page.openDefinitionTopic("ell-aorist-regular"), "the topic from Definition")
        XCTAssertFalse(page.englishNote.exists, "Greek's default pair explains in English")
        page.tapOnTopic(page.practiseButton, "Practise")
        let alert = app.alerts["Learn Greek via English?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert")
        alert.buttons["No"].tap()
        XCTAssertFalse(ExercisePage(app: app).view.waitForExistence(timeout: TestData.Timeouts.short),
                       "No: no drill")
        XCTAssertTrue(page.title.exists, "still on the topic")
    }

    // MARK: - Helpers

    /// Searches `word` and opens its El–En · FD Definition.
    private func openDefinition(_ word: String, expectsTable: Bool = true, file: StaticString = #filePath,
                                line: UInt = #line) {
        let search = tabBarPage.tapSearchTab()
        _ = InflectionTablePage.open(word, source: "freedict-ell-eng", from: search, app: app,
                                     expectsTable: expectsTable, file: file, line: line)
    }

    /// The Learn home's Grammar row, which reads `rowValue`, then the
    /// Grammar screen.
    private func openGrammar(rowValue: String = "17 topics", file: StaticString = #filePath, line: UInt = #line) {
        let learn = tabBarPage.tapLearnTab()
        XCTAssertTrue(learn.waitForHome(timeout: TestData.Timeouts.long), "Greek learned: the home",
                      file: file, line: line)
        XCTAssertTrue(app.scrollToElement(page.learnRow), "the Grammar row", file: file, line: line)
        XCTAssertEqual(page.learnRowValue, rowValue, file: file, line: line)
        XCTAssertTrue(page.openGrammar(), "the Grammar screen", file: file, line: line)
    }

    private func openTopic(_ id: String, rowValue: String = "17 topics",
                           file: StaticString = #filePath, line: UInt = #line) {
        openGrammar(rowValue: rowValue, file: file, line: line)
        XCTAssertTrue(page.openTopic(id), "the topic \(id)", file: file, line: line)
    }

    private static func isCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
