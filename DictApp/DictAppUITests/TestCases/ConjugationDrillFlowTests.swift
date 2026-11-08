import XCTest

/// 0132, #168: the conjugation drill's screens. The Learn home's
/// Conjugation row (Greek only), the Conjugation screen (the checked Greek
/// lists' verbs, "Tenses up to", the tenses, Start; Choose lists; the Greek
/// download), the run (the question, the passive note, the whole tense
/// after each answer, the summary by tense) and Practise on a Greek verb's
/// Definition, with "Learn Greek via English?" first while Greek is not
/// learned. English UI, `-resetData`, `-learningAnswerHints` (the right
/// option's value is `answer`), a fixed `-learningSeed`, and the Greek pack
/// installed from the committed assets unless a test removes it. Most tests
/// answer a few questions (`-drillLength`); `testSessionOfFifteen` answers
/// the default 15. Rule after an answer opens the grammar topic of the
/// question's tense in a sheet (0133, #174).
final class ConjugationDrillFlowTests: XCTestCase {

    private typealias IDs = AccessibilityIdentifiers.Conjugation

    var app: XCUIApplication!
    var tabBarPage: TabBarPage!

    /// The A1 tenses' titles (Kirill's terms, 0133).
    static let a1Titles = ["Present", "Aorist", "Future: simple form", "Imperative: simple form",
                           "Subjunctive: simple form"]
    static let a1Tenses = ["present", "aorist", "future", "imperativeSimple", "subjunctiveSimple"]

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        let greekA1 = ["-learningLanguages", "ell", "-learningLists", "ky-ell-a1"]
        if name.contains("testA1DrillAsksA1Tenses") { return greekA1 + ["-drillLength", "5"] }
        if name.contains("testNoCheckedListOffersChooseLists") { return ["-learningLanguages", "ell"] }
        if name.contains("testTensesUpToIsRemembered") { return greekA1 + ["-drillLength", "4"] }
        if name.contains("testWholeTenseAfterEachAnswer") { return greekA1 + ["-drillLength", "3"] }
        if name.contains("testSessionOfFifteen") { return greekA1 }
        if name.contains("testPassiveNote") || name.contains("testPractiseFromDefinition") {
            return ["-learningLanguages", "ell", "-drillLength", "3"]
        }
        if name.contains("testPractiseAsksLearnGreekFirst") { return ["-drillLength", "3"] }
        if name.contains("testRuleOpensTheTensesTopic") { return ["-learningLanguages", "ell", "-drillLength", "2"] }
        if name.contains("testNoRuleWithoutATopic") {
            return ["-learningLanguages", "ell", "-learningLists", "ky-ell-b1", "-drillLength", "15"]
        }
        if name.contains("testRowOnlyForGreek") { return ["-learningFixture", "bilingual"] }
        return []
    }

    /// `testNeedsTheGreekPack` starts with no pack and downloads Greek from
    /// the committed assets; the others install it at launch.
    private var packArguments: [String] {
        if name.contains("testNeedsTheGreekPack") {
            return ["-resetPacks", UITestHelpers.skipWelcome, "-learningLanguages", "ell", "-learningLists", "ky-ell-a1"]
                + UITestHelpers.downloadArguments("ok")
        }
        return UITestHelpers.packArguments("ell")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "168"]
            + learningArguments + packArguments
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
    }

    override func tearDownWithError() throws {
        app = nil
        tabBarPage = nil
    }

    // MARK: - Helpers

    /// The Learn home, then the Conjugation screen.
    private func openConjugation() -> ConjugationPage {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        return learnPage.openConjugation()
    }

    /// Answers every question right (or as `right(n)` says, n from 0) until
    /// the summary; returns each question's tense line and verb.
    @discardableResult
    private func answerAll(_ drill: ConjugationPage, limit: Int = 20, right: (Int) -> Bool = { _ in true },
                           each: (Int) -> Void = { _ in }) -> [(tense: String, verb: String)] {
        var asked: [(tense: String, verb: String)] = []
        while asked.count < limit, drill.waitForQuestion() {
            asked.append((drill.promptTense.label, drill.promptVerb.label))
            each(asked.count - 1)
            let isRight = right(asked.count - 1)
            XCTAssertEqual(drill.answer(right: isRight), isRight ? "right" : "wrong", "question \(asked.count)")
            drill.run.tapContinue()
        }
        return asked
    }

    /// Searches `word` and opens its El–En · FD Definition.
    private func openDefinition(_ word: String, expectsTable: Bool = true) -> ConjugationPage {
        let search = tabBarPage.tapSearchTab()
        _ = InflectionTablePage.open(word, source: "freedict-ell-eng", from: search, app: app, expectsTable: expectsTable)
        return ConjugationPage(app: app)
    }

    // MARK: - Tests

    /// Greek A1 checked, `-drillLength 5`: the row reads A1; the screen
    /// names Greek A1, starts at A1 and lists the 5 A1 tenses; every
    /// question's tense is one of them; the summary shows the run by tense.
    func testA1DrillAsksA1Tenses() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "the Conjugation row")
        XCTAssertEqual(learnPage.trainerConjugation.value as? String, "A1")
        let drill = learnPage.openConjugation()
        XCTAssertTrue(drill.lists.waitForExistence(timeout: TestData.Timeouts.long), "the verbs line")
        XCTAssertEqual(drill.lists.label, "Verbs from Greek A1")
        XCTAssertTrue(drill.verbCount.label.hasSuffix(" verbs"), drill.verbCount.label)
        XCTAssertEqual(drill.segmentLabels, ["A1", "A2", "B1", "B2"])
        XCTAssertTrue(drill.segment("A1").isSelected, "Tenses up to: A1")
        for tense in Self.a1Tenses {
            XCTAssertTrue(drill.tense(tense).exists, "\(tense) is listed")
        }
        XCTAssertFalse(drill.tense("imperfect").exists, "the imperfect is B1's")

        drill.start()
        let asked = answerAll(drill)
        XCTAssertEqual(asked.count, 5)
        for item in asked {
            XCTAssertTrue(Self.a1Titles.contains { item.tense.hasPrefix($0 + ",") }, "an A1 tense: \(item.tense)")
        }
        XCTAssertTrue(drill.run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(drill.run.summaryValue(AccessibilityIdentifiers.Exercise.summaryExercises), "5")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityIdentifiers.Exercise.summaryNewWords].exists,
                       "a drill has no new words row")
        let scores = Self.a1Tenses.filter { drill.summaryTense($0).exists }
        XCTAssertFalse(scores.isEmpty, "the run by tense")
        let total = scores.compactMap { (drill.summaryTense($0).value as? String)?.split(separator: "/").last }
            .compactMap { Int($0) }.reduce(0, +)
        XCTAssertEqual(total, 5, "the tenses' questions add up to the run")
        drill.run.tapDone()
        XCTAssertTrue(drill.waitForScreen(), "Done returns to the Conjugation screen")
    }

    /// Greek learned, no list: "Choose Greek lists…" and Choose lists, no
    /// Start; Choose lists opens New words from; Greek A2 checked, the
    /// screen offers Start, from A2.
    func testNoCheckedListOffersChooseLists() throws {
        let drill = openConjugation()
        XCTAssertTrue(drill.noLists.waitForExistence(timeout: TestData.Timeouts.medium), "no Greek list")
        XCTAssertEqual(drill.noLists.label, "Choose Greek lists to practise their verbs.")
        XCTAssertFalse(drill.startButton.exists, "no Start")
        XCTAssertFalse(drill.tensesPicker.exists, "no Tenses up to")
        drill.chooseLists.tap()
        let lists = WordListsPage(app: app)
        XCTAssertTrue(lists.waitForNewWordsFrom(), "Choose lists opens New words from")
        let a2 = lists.newWordsFromRow("ky-ell-a2")
        XCTAssertTrue(app.scrollToElement(a2), "Greek A2 on New words from")
        a2.tap()
        XCTAssertTrue(lists.wait(for: a2, selected: true), "Greek A2 checked")
        lists.goBack()
        XCTAssertTrue(drill.startButton.waitForExistence(timeout: TestData.Timeouts.long), "Start once a list is checked")
        XCTAssertFalse(drill.noLists.exists)
        XCTAssertEqual(drill.lists.label, "Verbs from Greek A2")
        XCTAssertEqual(drill.segmentLabels, ["A2", "B1", "B2"], "levels below the highest checked list are not offered")
        XCTAssertTrue(drill.segment("A2").isSelected)
    }

    /// "Tenses up to" B2 lists the perfect, is remembered across launches,
    /// the Learn home's row reads it, and Start drills at it.
    func testTensesUpToIsRemembered() throws {
        var drill = openConjugation()
        XCTAssertTrue(drill.tensesPicker.waitForExistence(timeout: TestData.Timeouts.long), "Tenses up to")
        XCTAssertFalse(drill.tense("perfect").exists)
        drill.segment("B2").tap()
        XCTAssertTrue(drill.tense("perfect").waitForExistence(timeout: TestData.Timeouts.medium), "B2 lists the perfect")
        XCTAssertTrue(drill.tense("imperfect").exists, "and B1's tenses")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetData" }
        app.launch()
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "the Conjugation row")
        XCTAssertEqual(learnPage.trainerConjugation.value as? String, "B2", "the row reads the level")
        drill = learnPage.openConjugation()
        XCTAssertTrue(drill.tensesPicker.waitForExistence(timeout: TestData.Timeouts.long))
        XCTAssertTrue(drill.segment("B2").isSelected, "remembered")
        XCTAssertTrue(drill.tense("perfect").exists)

        // QA (#168): Start drills at the remembered level, beyond A1's tenses.
        drill.start()
        let asked = answerAll(drill)
        XCTAssertEqual(asked.count, 4)
        XCTAssertTrue(asked.contains { item in
            item.tense.contains(", passive, ") || !Self.a1Titles.contains { item.tense.hasPrefix($0 + ",") }
        }, "a B2 drill asks a tense or voice beyond A1: \(asked.map(\.tense))")
    }

    /// One right and one wrong answer: after each, the whole tense with
    /// the asked person marked, then Continue.
    func testWholeTenseAfterEachAnswer() throws {
        let drill = openConjugation()
        drill.start()
        for (index, right) in [true, false].enumerated() {
            XCTAssertTrue(drill.waitForQuestion(), "question \(index + 1)")
            let asked = try XCTUnwrap(drill.askedPerson, "the person of '\(drill.promptTense.label)'")
            XCTAssertFalse(drill.tenseTable.exists, "the tense waits for the answer")
            XCTAssertEqual(drill.answer(right: right), right ? "right" : "wrong")
            XCTAssertTrue(drill.tenseTable.waitForExistence(timeout: TestData.Timeouts.medium), "the whole tense")
            let row = drill.tenseRow(asked)
            XCTAssertTrue(row.exists, "the asked row \(asked)")
            XCTAssertEqual(row.value as? String, "asked")
            XCTAssertTrue(row.isSelected, "VoiceOver reads the asked row as selected")
            let pronoun = try XCTUnwrap(ConjugationPage.persons.first { $0.value == asked }?.key)
            XCTAssertTrue(row.label.hasPrefix(pronoun + ", "), "a row reads 'pronoun, forms': \(row.label)")
            let others = ConjugationPage.persons.values.filter { $0 != asked && drill.tenseRow($0).exists }
            XCTAssertFalse(others.isEmpty, "the other persons of the tense")
            for person in others {
                XCTAssertNotEqual(drill.tenseRow(person).value as? String, "asked", person)
            }
            // QA (#168): left to right, the pronoun (secondary ink) is left of
            // the forms; Arabic checks the mirror image.
            let columns = try XCTUnwrap(drill.inkColumns(of: drill.tenseRow(others.sorted()[0])), "the row's text")
            XCTAssertGreaterThan(columns.strong.lowerBound - columns.ink.lowerBound, 10,
                                 "the pronoun column left of the forms: \(columns)")
            if !right {
                XCTAssertTrue(drill.run.feedbackText.contains("Right answer:"), drill.run.feedbackText)
            }
            drill.run.tapContinue()
        }
    }

    /// No `-drillLength`: 15 questions, then the summary with the run by tense.
    func testSessionOfFifteen() throws {
        let drill = openConjugation()
        drill.start()
        var last = ""
        let asked = answerAll(drill, each: { _ in last = drill.run.progress.label })
        XCTAssertEqual(asked.count, 15)
        XCTAssertEqual(last, "Question 15 of 15")
        XCTAssertTrue(drill.run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(drill.run.summaryValue(AccessibilityIdentifiers.Exercise.summaryExercises), "15")
        XCTAssertTrue(Self.a1Tenses.contains { drill.summaryTense($0).exists }, "the run by tense")
        XCTAssertFalse(asked.indices.dropFirst().contains { asked[$0].verb == asked[$0 - 1].verb },
                       "the same verb is not asked twice in a row: \(asked.map(\.verb))")
    }

    /// Practise on έρχομαι: every question carries the "passive" note; on
    /// γράφω none does.
    func testPassiveNote() throws {
        var drill = openDefinition("έρχομαι")
        drill.practise()
        let erchomai = answerAll(drill, each: { _ in
            XCTAssertTrue(drill.passiveNote.exists, "the passive note")
            XCTAssertEqual(drill.passiveNote.label, "passive")
        })
        XCTAssertEqual(erchomai.count, 3)
        XCTAssertTrue(erchomai.allSatisfy { $0.verb == "έρχομαι" })
        drill.run.tapDone()

        tabBarPage.tapSearchTab()
        drill = openDefinition("γράφω")
        drill.practise()
        let grafo = answerAll(drill, each: { _ in XCTAssertFalse(drill.passiveNote.exists, "no note") })
        XCTAssertEqual(grafo.count, 3)
    }

    /// Greek learned: Practise under γράφω's table starts its drill at once;
    /// every question asks γράφω, "to write". σπίτι, a noun, has no Practise.
    func testPractiseFromDefinition() throws {
        let drill = openDefinition("γράφω")
        XCTAssertTrue(drill.practiseButton.waitForExistence(timeout: TestData.Timeouts.long), "Practise")
        let table = app.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.table].firstMatch
        XCTAssertGreaterThan(drill.practiseButton.frame.minY, table.frame.minY, "under the table")
        XCTAssertEqual(drill.practiseButton.label, "Practise conjugating \u{2068}γράφω\u{2069}", "the verb isolated (#119)")
        drill.practise()
        XCTAssertTrue(drill.run.view.waitForExistence(timeout: TestData.Timeouts.medium), "the run")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Greek is learned: no alert")
        let asked = answerAll(drill, each: { _ in
            XCTAssertEqual(drill.promptTranslation.label, "write", "El–En · FD's first sense")
        })
        XCTAssertEqual(asked.count, 3)
        XCTAssertTrue(asked.allSatisfy { $0.verb == "γράφω" }, "\(asked.map(\.verb))")
        drill.run.tapDone()
        XCTAssertTrue(drill.practiseButton.waitForExistence(timeout: TestData.Timeouts.medium), "back on Definition")

        tabBarPage.tapSearchTab()
        let spiti = openDefinition("σπίτι")
        XCTAssertFalse(spiti.practiseButton.waitForExistence(timeout: TestData.Timeouts.short), "a noun has no Practise")
    }

    /// No learned language: Practise asks "Learn Greek via English?"; No
    /// stays on Definition; Yes starts the drill; then the Learn tab shows
    /// Greek's home, not the picker.
    func testPractiseAsksLearnGreekFirst() throws {
        let drill = openDefinition("γράφω")
        drill.practise()
        let alert = app.alerts["Learn Greek via English?"]
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert")
        alert.buttons["No"].tap()
        XCTAssertFalse(drill.run.view.waitForExistence(timeout: TestData.Timeouts.short), "No: no drill")
        XCTAssertTrue(drill.practiseButton.exists, "still on Definition")

        drill.practise()
        XCTAssertTrue(alert.waitForExistence(timeout: TestData.Timeouts.medium), "the alert again")
        alert.buttons["Yes"].tap()
        XCTAssertTrue(drill.run.view.waitForExistence(timeout: TestData.Timeouts.medium), "Yes: the drill")
        XCTAssertTrue(drill.waitForQuestion(), "a question")
        XCTAssertEqual(drill.promptVerb.label, "γράφω")
        drill.run.closeButton.tap()
        XCTAssertTrue(drill.practiseButton.waitForExistence(timeout: TestData.Timeouts.medium), "back on Definition")

        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "Greek is learned: its home")
        XCTAssertFalse(learnPage.picker.exists, "not the picker")
    }

    /// `-learningFixture bilingual`: the row with Greek chosen, none with English.
    func testRowOnlyForGreek() throws {
        let learnPage = tabBarPage.tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
        XCTAssertTrue(app.scrollToElement(learnPage.trainerConjugation), "Greek: the Conjugation row")
        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.trainerConjugation.waitForNonExistence(timeout: TestData.Timeouts.medium),
                      "English: no Conjugation row")
        XCTAssertTrue(learnPage.trainerRecognition.exists, "the other trainers stay")
        learnPage.selectLanguage(named: "Greek")
        XCTAssertTrue(learnPage.trainerConjugation.waitForExistence(timeout: TestData.Timeouts.medium),
                      "Greek again: the row")
    }

    /// The topic Rule opens for γράφω, by the tense line's start (English).
    private static let grafoTopics: [(tense: String, id: String, title: String)] = [
        ("Present", "ell-present-1", "Present tense: first conjugation"),
        ("Aorist", "ell-aorist-regular", "The aorist of regular verbs and the augment"),
        ("Future: simple form", "ell-future", "The future with θα"),
        ("Subjunctive: simple form", "ell-na-perfective", "να + the simple form"),
        ("Imperative", "ell-imperative", "The imperative"),
    ]

    /// Practise on γράφω: after the answer, Rule opens the topic of the
    /// question's tense in a sheet, with no Practise; a word there opens its
    /// Definition, also without Practise. Done returns to the same answer's
    /// feedback, and Continue goes on.
    func testRuleOpensTheTensesTopic() throws {
        let drill = openDefinition("γράφω")
        drill.practise()
        XCTAssertTrue(drill.waitForQuestion(), "a question")
        let grammar = GrammarPage(app: app)
        XCTAssertFalse(grammar.ruleButton.exists, "no Rule before the answer")
        let line = drill.promptTense.label
        let topic = try XCTUnwrap(Self.grafoTopics.first { line.hasPrefix($0.tense) }, "a topic for '\(line)'")
        XCTAssertEqual(drill.answer(right: true), "right")
        XCTAssertTrue(grammar.ruleButton.waitForExistence(timeout: TestData.Timeouts.medium), "Rule beside Continue")
        XCTAssertTrue(grammar.ruleButton.label.hasPrefix("Grammar rule: "), grammar.ruleButton.label)
        XCTAssertTrue(drill.run.continueButton.exists)
        grammar.ruleButton.tap()

        // The Definition the run covers stays in the hierarchy: look inside the sheet.
        let sheet = grammar.sheet
        XCTAssertTrue(sheet.waitForExistence(timeout: TestData.Timeouts.medium), "the sheet")
        XCTAssertTrue(grammar.waitForTopic(), "the topic")
        XCTAssertTrue(sheet.descendants(matching: .any)[AccessibilityIdentifiers.Grammar.title].exists, "in the sheet")
        XCTAssertEqual(grammar.title.label, topic.title, "the topic of '\(line)'")
        XCTAssertFalse(grammar.practiseButton.exists, "no Practise in the sheet")
        XCTAssertTrue(grammar.sheetDone.exists, "Done")

        // γράφω's word link, on this topic or on a related one.
        if !grammar.word("γράφω").exists {
            let related = ["ell-aorist-regular", "ell-imperative"].map(grammar.related).first { $0.exists }
            grammar.tapOnTopic(try XCTUnwrap(related, "a related topic with γράφω"), "a related topic")
            XCTAssertTrue(grammar.word("γράφω").waitForExistence(timeout: TestData.Timeouts.medium), "γράφω's row")
            XCTAssertFalse(grammar.practiseButton.exists, "no Practise on a related topic in the sheet")
        }
        grammar.tapOnTopic(grammar.word("γράφω"), "γράφω's row")
        XCTAssertTrue(sheet.descendants(matching: .any)[AccessibilityIdentifiers.Inflection.table].firstMatch
            .waitForExistence(timeout: TestData.Timeouts.long), "γράφω's Definition with its table, in the sheet")
        XCTAssertFalse(sheet.buttons[AccessibilityIdentifiers.Conjugation.practiseButton].firstMatch
            .waitForExistence(timeout: TestData.Timeouts.short), "no Practise on a Definition in the sheet")
        XCTAssertTrue(sheet.descendants(matching: .any)[AccessibilityIdentifiers.Grammar.definitionSection].exists,
                      "its Grammar section still shows")

        // Back to the sheet's root, then Done.
        while !grammar.sheetDone.exists, app.navigationBars.firstMatch.buttons.count > 0 {
            grammar.goBack()
            _ = grammar.sheetDone.waitForExistence(timeout: TestData.Timeouts.short)
        }
        grammar.sheetDone.tap()
        XCTAssertTrue(grammar.sheet.waitForNonExistence(timeout: TestData.Timeouts.medium), "the sheet closes")
        XCTAssertTrue(drill.run.feedback.exists, "the same answer's feedback")
        XCTAssertEqual(drill.run.feedback.value as? String, "right")
        XCTAssertTrue(grammar.ruleButton.exists, "Rule stays")
        drill.run.tapContinue()
        XCTAssertTrue(drill.waitForQuestion(), "Continue goes on")
        XCTAssertFalse(grammar.ruleButton.exists)
    }

    /// Tenses up to B1 (Greek B1 checked): Practise on γράφω asks tenses
    /// with no 2.0 topic (the imperfect, the continuous future and
    /// subjunctive, the passive of γράφω, a verb with both voices), which
    /// have no Rule; the others have it.
    func testNoRuleWithoutATopic() throws {
        let drill = openDefinition("γράφω")
        drill.practise()
        let grammar = GrammarPage(app: app)
        var without: [String] = []
        var with: [String] = []
        while without.isEmpty || with.isEmpty, with.count + without.count < 15, drill.waitForQuestion() {
            let line = drill.promptTense.label
            let hasTopic = !line.contains("passive") && !line.hasPrefix("Imperfect")
                && !line.hasPrefix("Future: continuous") && !line.hasPrefix("Subjunctive: continuous")
            XCTAssertEqual(drill.answer(right: true), "right", line)
            XCTAssertTrue(drill.run.continueButton.waitForExistence(timeout: TestData.Timeouts.medium))
            XCTAssertEqual(grammar.ruleButton.exists, hasTopic, "Rule for '\(line)'")
            if hasTopic { with.append(line) } else { without.append(line) }
            drill.run.tapContinue()
        }
        XCTAssertFalse(without.isEmpty, "a question without a topic; asked \(with)")
        XCTAssertFalse(with.isEmpty, "a question with a topic; asked \(without)")
    }

    /// No Greek pack (`-resetPacks`): "Download Greek to practise
    /// conjugation." and Download, whose install (from the committed
    /// assets) brings Start.
    func testNeedsTheGreekPack() throws {
        let drill = openConjugation()
        XCTAssertTrue(drill.needsGreek.waitForExistence(timeout: TestData.Timeouts.medium), "the download first")
        XCTAssertEqual(drill.needsGreek.label, "Download Greek to practise conjugation.")
        XCTAssertFalse(drill.startButton.exists, "no Start")
        XCTAssertTrue(drill.downloadGreek.exists, "Download")
        XCTAssertTrue(drill.downloadGreek.label.hasPrefix("Download · "), drill.downloadGreek.label)
        drill.downloadGreek.tap()
        XCTAssertTrue(drill.startButton.waitForExistence(timeout: 180), "the Greek pack installed: Start")
        XCTAssertFalse(drill.needsGreek.exists)
        XCTAssertEqual(drill.lists.label, "Verbs from Greek A1")
    }
}
