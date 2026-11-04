import XCTest

/// 0131, #159: the Recognition and Production trainers, typed answers by
/// answer mode, instant feedback, and meanings in the pair's meanings
/// language. English UI, `-resetData`, `-learningAnswerHints` (the right
/// option's value is `answer`) and a fixed `-learningSeed`. The answer mode
/// is set through the `learning_answer_mode` default until #162's Settings
/// screen can.
final class ExerciseFlowTests: XCTestCase {

    var app: XCUIApplication!
    var learnPage: LearnPage!

    /// `-learningFixture due` through Greek via English: each word's meaning
    /// from El–En · FD, first of the pair in the default Dictionary Order.
    static let greekMeanings = ["γράφω": "write", "σπίτι": "house, home, habitation", "νερό": "water",
                                "καλός": "good", "είμαι": "be, exist", "βιβλίο": "book"]

    /// Launch arguments after `-resetData`, per test.
    private var learningArguments: [String] {
        if name.contains("testRecognitionMeaningsFollowThePair") {
            return ["-learningFixture", "bilingual", "-learningLanguages", "ell,eng:spa"]
        }
        if name.contains("testLimitedPairMeaningsAreEnglish") {
            return ["-learningFixture", "due", "-learningLanguages", "ell:rus"]
        }
        if name.contains("testProductionTrainer") {
            return ["-learningFixture", "due", "-learning_answer_mode", "choice"]
        }
        if name.contains("testTypedStrictAccentIsWrong") {
            return ["-learningFixture", "due", "-learning_answer_mode", "strict"]
        }
        return ["-learningFixture", "due"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Issue #237: no first-launch sheet; the Greek and Spanish packs,
        // which hold the meanings, installed from the committed assets.
        app.launchArguments = ["-disableReviewPrompt", "-resetData", "-learningAnswerHints", "-learningSeed", "159"]
            + learningArguments + UITestHelpers.packArguments()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Sim orientation persists across sessions; landscape breaks swipes.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        learnPage = TabBarPage(app: app).tapLearnTab()
        XCTAssertTrue(learnPage.waitForHome(timeout: TestData.Timeouts.long), "the Learn home")
    }

    override func tearDownWithError() throws {
        app = nil
        learnPage = nil
    }

    // MARK: - Helpers

    /// Waits for a question whose prompt is not `previous`, or the summary;
    /// returns the prompt, nil at the summary.
    private func nextPrompt(_ run: ExercisePage, after previous: String?) -> String? {
        let deadline = Date().addingTimeInterval(TestData.Timeouts.long)
        repeat {
            if run.summary.exists { return nil }
            if run.prompt.exists, !run.feedback.exists, run.prompt.label != previous { return run.prompt.label }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        XCTFail("no next question after \(previous ?? "the start")")
        return nil
    }

    /// Answers every choice question right until the summary; returns the
    /// prompts and each right option's text.
    @discardableResult
    private func answerAllRight(_ run: ExercisePage, limit: Int = 12) -> [(prompt: String, answer: String)] {
        var asked: [(prompt: String, answer: String)] = []
        var previous: String?
        while asked.count < limit, let prompt = nextPrompt(run, after: previous) {
            XCTAssertFalse(run.isTyped, "a choice question")
            guard let answer = run.rightOption?.label else {
                XCTFail("no option marked as the answer for \(prompt)")
                return asked
            }
            run.choose(right: true)
            XCTAssertEqual(run.waitForFeedback(), "right", "\(prompt) answered right")
            asked.append((prompt, answer))
            previous = prompt
            run.tapContinue()
        }
        return asked
    }

    /// `word` without its accents: γράφω → γραφω.
    private func unaccented(_ word: String) -> String {
        word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "el"))
    }

    // MARK: - Tests

    /// Recognition: the five due words, then βιβλίο as practice, each with 4
    /// English meanings; all right gives the summary. The progress bar
    /// reads "Question 1 of 6" to VoiceOver.
    func testRecognitionTrainer() throws {
        let run = learnPage.openTrainer()
        guard let first = nextPrompt(run, after: nil) else { return }
        XCTAssertEqual(run.options.count, 4, "\(first): four meanings")
        XCTAssertEqual(run.progress.label, "Question 1 of 6")
        let asked = answerAllRight(run)
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(asked.count, 6, "5 due cards, then the practice card")
        XCTAssertEqual(Set(asked.map(\.prompt)), Set(Self.greekMeanings.keys))
        XCTAssertEqual(asked.last?.prompt, "βιβλίο", "practice after the due cards")
        for item in asked {
            XCTAssertEqual(item.answer, Self.greekMeanings[item.prompt], "\(item.prompt)'s meaning, in English")
        }
        run.tapDone()
        XCTAssertTrue(learnPage.waitForHome(), "Done closes the run")
    }

    /// Production as Multiple choice: each English meaning with 4 Greek words.
    func testProductionTrainer() throws {
        let run = learnPage.openTrainer(production: true)
        let asked = answerAllRight(run)
        XCTAssertTrue(run.summary.waitForExistence(timeout: TestData.Timeouts.medium), "the summary")
        XCTAssertEqual(asked.count, 6)
        for item in asked {
            XCTAssertEqual(Self.greekMeanings[item.answer], item.prompt, "the prompt is \(item.answer)'s meaning")
        }
    }

    /// Lenient: a familiar production card is typed; the word without its
    /// accents is right, with "Mind the accent".
    func testTypedLenientAccentWarning() throws {
        let run = learnPage.openTrainer(production: true)
        guard let prompt = nextPrompt(run, after: nil) else { return }
        XCTAssertTrue(run.isTyped, "rung 1 or higher: typed")
        let word = try XCTUnwrap(Self.greekMeanings.first { $0.value == prompt }?.key, "the word of \(prompt)")
        run.type(unaccented(word))
        XCTAssertEqual(run.waitForFeedback(), "accent")
        XCTAssertTrue(run.feedbackText.contains("Right!"), run.feedbackText)
        XCTAssertTrue(run.feedbackText.contains("Mind the accent"), run.feedbackText)
        XCTAssertTrue(run.feedbackText.contains(word), run.feedbackText)
    }

    /// Strict: the word without its accents is wrong, with "Mind the accent".
    func testTypedStrictAccentIsWrong() throws {
        let run = learnPage.openTrainer(production: true)
        guard let prompt = nextPrompt(run, after: nil) else { return }
        XCTAssertTrue(run.isTyped)
        let word = try XCTUnwrap(Self.greekMeanings.first { $0.value == prompt }?.key, "the word of \(prompt)")
        run.type(unaccented(word))
        XCTAssertEqual(run.waitForFeedback(), "wrong")
        XCTAssertTrue(run.feedbackText.contains("Mind the accent"), run.feedbackText)
        XCTAssertTrue(run.feedbackText.contains(word), run.feedbackText)
    }

    /// The close button ends a run at any time and the answers given stay:
    /// the card answered right is no longer due, so the next run starts
    /// with another word and asks the first one last, as practice.
    func testCloseKeepsTheAnswersGiven() throws {
        var run = learnPage.openTrainer()
        guard let first = nextPrompt(run, after: nil) else { return }
        run.choose(right: true)
        XCTAssertEqual(run.waitForFeedback(), "right")
        XCTAssertTrue(run.closeButton.exists, "the close button")
        run.closeButton.tap()
        XCTAssertTrue(learnPage.waitForHome(), "closing returns to the Learn home")

        run = learnPage.openTrainer()
        guard let again = nextPrompt(run, after: nil) else { return }
        XCTAssertNotEqual(again, first, "\(first) was answered: not due any more")
        XCTAssertEqual(run.progress.label, "Question 1 of 6", "\(first) comes back as practice")
    }

    /// A wrong choice: the feedback at once, the right option marked
    /// Correct, the tapped one wrong, and "Right answer: …".
    func testWrongChoiceHighlightsTheRightOption() throws {
        let run = learnPage.openTrainer()
        guard let prompt = nextPrompt(run, after: nil) else { return }
        let right = try XCTUnwrap(run.rightOption, "the answer hint")
        let rightID = right.identifier
        let meaning = right.label
        let tapped = try XCTUnwrap(run.options.first { $0.identifier != rightID })
        let tappedID = tapped.identifier
        tapped.tap()
        XCTAssertEqual(run.waitForFeedback(timeout: TestData.Timeouts.short), "wrong", prompt)
        XCTAssertEqual(app.buttons[rightID].value as? String, "Correct")
        XCTAssertEqual(app.buttons[tappedID].value as? String, "Your answer: wrong")
        XCTAssertTrue(run.feedbackText.contains("Right answer:"), run.feedbackText)
        XCTAssertTrue(run.feedbackText.contains(meaning), run.feedbackText)
    }

    /// English via Spanish (`-learningLanguages ell,eng:spa`): house and
    /// water are asked with their Spanish meanings, from En–Es · FD.
    func testRecognitionMeaningsFollowThePair() throws {
        learnPage.selectLanguage(named: "English")
        XCTAssertTrue(learnPage.waitForLabel(of: learnPage.dueCount, toBe: "2 words due"))
        let run = learnPage.openTrainer()
        let asked = answerAllRight(run)
        let spanish = ["house": "casalicio, casa", "water": "agua, aguacha, linfa, wata"]
        XCTAssertEqual(Set(asked.map(\.prompt)), Set(spanish.keys), "only English words")
        for item in asked {
            XCTAssertEqual(item.answer, spanish[item.prompt], "\(item.prompt)'s meaning, in Spanish")
        }
    }

    /// Greek via Russian, limited (`-learningLanguages ell:rus`): the
    /// meanings are English, as via English.
    func testLimitedPairMeaningsAreEnglish() throws {
        let run = learnPage.openTrainer()
        let asked = answerAllRight(run)
        XCTAssertEqual(asked.count, 6)
        for item in asked {
            XCTAssertEqual(item.answer, Self.greekMeanings[item.prompt], "\(item.prompt)'s meaning, in English")
        }
    }
}
