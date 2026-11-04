// LearnViewModel.swift
// The Learn tab (0131-learning.md, #158): the pair picker, the Learn home
// and the interim My words list. The runs: the trainers (#159), the session
// and mistakes practice (#161).

import Foundation
import SwiftUI

@MainActor
final class LearnViewModel: ObservableObject {
    /// What the Today section shows, for the chosen language.
    enum Today: Equatable {
        /// Words due and new words left today.
        case counts(due: Int, newLeft: Int)
        /// Nothing due and no new word left.
        case allDone
        /// Nothing to learn yet, in a language with built-in lists.
        case chooseLists
        /// Nothing to learn yet, in a language without lists.
        case addWords
    }

    /// The learned languages, in the order chosen. Empty: the picker.
    @Published private(set) var learned: [String] = []
    /// The language of the home; nil while none is learned.
    @Published private(set) var language: String?
    /// The chosen language's pair; nil for Other or while none is learned.
    @Published private(set) var pair: LearningPair?
    /// The picker's rows while no language is learned (`LearningPairs.pickerRows`).
    @Published private(set) var pickerRows: [LearningPair] = []
    /// What each picker row still has to download, in bytes; 0 or absent: nothing.
    @Published private(set) var downloadSizes: [LearningPair: Int64] = [:]
    @Published private(set) var today: Today?
    /// My words that resolve, in every language.
    @Published private(set) var myWordsCount = 0
    /// False until the first load ends, so the picker never flashes before the home.
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock

    init(db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil, clock: LearningClock = LearningClock()) {
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
    }

    /// The languages with built-in lists: the picker's first group.
    var languagesWithLists: Set<String> { languages.packs.languagesWithLists }

    /// The trainers need a word in learning; else "Learn a few words first".
    // ponytail: #161 also enables them for a checked list (E3 #151)
    var canTrain: Bool {
        switch today {
        case .counts?, .allDone?: return true
        case .chooseLists?, .addWords?, nil: return false
        }
    }

    /// Reads the learned languages, then the picker's rows or the home.
    /// `locale` names the languages for the picker's order.
    func load(locale: Locale) async {
        learned = languages.learned
        language = languages.chosen
        do {
            if learned.isEmpty {
                today = nil
                pair = nil
                pickerRows = LearningPairs.pickerRows(offered: try await db.learningPairs().keys,
                                                      withLists: languagesWithLists, learned: learned,
                                                      uiLanguage: languages.uiLanguage(),
                                                      name: { Self.languageName($0, locale: locale) })
                var sizes: [LearningPair: Int64] = [:]
                for row in pickerRows {
                    sizes[row] = await languages.packs.downloadSize(of: row)
                }
                downloadSizes = sizes
            } else {
                try await loadHome()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// The picker: learns `pair`, then shows its language's home.
    func choose(_ pair: LearningPair, locale: Locale) async {
        do {
            try await languages.learn(pair)
        } catch {
            errorMessage = error.localizedDescription
        }
        await load(locale: locale)
    }

    /// The switch: remembers `lang` and shows its numbers.
    func select(_ lang: String) async {
        guard lang != language, learned.contains(lang) else { return }
        languages.chosen = lang
        language = lang
        do {
            try await loadHome()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHome() async throws {
        guard let language else { return }
        let day = clock.today
        pair = try await languages.pair(for: language)
        myWordsCount = try await db.fetchMyWords().count
        // ponytail: #154 also counts the language's checked lists here
        guard try await db.learningWordCount(lang: language) > 0 else {
            today = languagesWithLists.contains(language) ? .chooseLists : .addWords
            return
        }
        let due = Set(try await db.dueCards(lang: language, today: day).map(\.key.word)).count
        let left = settings.learningNewPerDay - (try await db.startedCount(on: day, lang: language))
        // ponytail: #161 adds the checked lists' next words
        let newLeft = try await db.newPool(lang: language, limit: left).count
        today = due == 0 && newLeft == 0 ? .allDone : .counts(due: due, newLeft: newLeft)
    }

    /// A learned language's name in the UI language, as the production
    /// prompt names it (`language.*.name`); `und` is E3's "Other".
    nonisolated static func languageName(_ code: String, locale: Locale) -> String {
        guard code == "und" else { return SettingsViewModel.languageName(iso3: code, locale: locale) }
        return localized("listImport.language.other", locale: locale)
    }

    /// A language's name inside a sentence ("Learn Greek via English?",
    /// "Учить греческий через английский?"): English capitalises it, the
    /// other UI languages write it in lower case (Arabic has no case).
    nonisolated static func languageNameInSentence(_ code: String, locale: Locale) -> String {
        let name = languageName(code, locale: locale)
        return locale.language.languageCode == .english ? name : name.lowercased(with: locale)
    }

    /// A pair's row, "Greek via English" (`learn.pair`).
    nonisolated static func pairName(_ pair: LearningPair, locale: Locale) -> String {
        String(format: localized("learn.pair %@ %@", locale: locale),
               languageName(pair.lang, locale: locale), languageNameInSentence(pair.via, locale: locale))
    }

    /// "Learn Greek via Russian?" (`learn.learnLanguage.title`): Learn on a
    /// word of a language not learned.
    nonisolated static func learnPairQuestion(_ pair: LearningPair, locale: Locale) -> String {
        String(format: localized("learn.learnLanguage.title %@ %@", locale: locale),
               languageNameInSentence(pair.lang, locale: locale), languageNameInSentence(pair.via, locale: locale))
    }

    /// A limited pair's warning, "Words are practised in English."
    /// (`learn.pair.limited`, the meanings language); nil for a full pair.
    nonisolated static func limitedWarning(_ pair: LearningPair, locale: Locale) -> String? {
        guard pair.isLimited else { return nil }
        return String(format: localized("learn.pair.limited %@", locale: locale),
                      languageNameInSentence(pair.meaningsLang, locale: locale))
    }

    /// `key` from the in-app language's table (`locale`), not the device's.
    private nonisolated static func localized(_ key: String, locale: Locale) -> String {
        SettingsViewModel.localizedBundle(for: locale).localizedString(forKey: key, value: key, table: nil)
    }
}

// MARK: - Runs (#159, #161)

/// A graded answer, as the feedback bar shows it.
struct AnswerFeedback: Equatable {
    let outcome: Outcome
    /// The option tapped; nil for a typed answer.
    let chosenIndex: Int?
    /// "Mind the accent: γράφω" instead of "Right answer: γράφω", or under "Right!".
    let mindTheAccent: Bool
    /// The right option's text, or the word.
    let rightAnswer: String
}

/// Runs a plan of questions (0131, "Runs"): builds each question just
/// before showing it, grades the answer at once, writes it at once with
/// `recordAnswer`, so closing early loses nothing, and requeues a wrong
/// card once. Its summary is `ReviewSummary` over the run's log rows.
@MainActor
final class ExerciseRunViewModel: ObservableObject {
    /// What runs. #161 adds the session and mistakes practice.
    enum Run: Hashable {
        /// Recognition or Production: 10 items of its own direction.
        case trainer(CardKind)

        var mode: RunMode {
            switch self {
            case .trainer: return .trainer
            }
        }
    }

    enum Phase: Equatable {
        case loading
        case question
        /// The plan had nothing to ask.
        case empty
        case summary
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var question: Question?
    /// Set the moment an answer is graded; nil while a question waits.
    @Published private(set) var feedback: AnswerFeedback?
    /// The typed answer.
    @Published var typed = ""
    /// The question shown, from 1, and the plan's length.
    @Published private(set) var position = 0
    @Published private(set) var total = 0
    /// Answers so far: the progress bar's value.
    @Published private(set) var answered = 0
    /// The summary's numbers, from this run's log rows; nil until the end.
    @Published private(set) var summary: ReviewSummary?
    @Published var errorMessage: String?

    let run: Run
    /// The chosen language: a run never mixes languages.
    let lang: String
    /// Its pair's meanings language, which every meaning is in (English
    /// for Greek via Russian); nil without a pair (Other).
    let meaningsLang: String?
    /// `-learningAnswerHints`.
    let answerHints: Bool
    /// One per run: its log rows.
    let runID = UUID()

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    private let player: FeedbackPlayer
    private var rng: SplitMix64
    private var plan: [PlannedItem] = []
    private var index = 0
    /// The answer mode the current question was built with.
    private var questionMode = AnswerMode.lenient
    private var shownAt = Date()
    /// The words of `lang` in learning: the questions' words and the first options.
    private var enrolled: [WordChoice] = []
    private var words: [WordKey: WordChoice] = [:]
    /// The pair's dictionaries first (`LearningLanguageService.sourceOrder`).
    private var sourceOrder: [String] = []
    /// The source samples, by source and primary part of speech.
    private var samples: [String: [WordChoice]] = [:]
    private var pendingWrite: Task<Void, Never>?
    private var isStarted = false

    init(run: Run, lang: String, meaningsLang: String?, db: DatabaseService = .shared,
         settings: SettingsService = .shared, languages: LearningLanguageService? = nil,
         clock: LearningClock = LearningClock(), player: FeedbackPlayer? = nil,
         seed: UInt64? = LearningLaunchOptions.seed, answerHints: Bool = LearningLaunchOptions.answerHints) {
        self.run = run
        self.lang = lang
        self.meaningsLang = meaningsLang
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        self.player = player ?? .shared
        self.rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
        self.answerHints = answerHints
    }

    /// Plans the run and shows its first question.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            let today = clock.today
            sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
            enrolled = try await db.wordChoices(lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder)
            words = Dictionary(enrolled.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            switch run {
            case let .trainer(kind):
                let length = SessionPlanner.trainerLength
                // Read whole, then filtered: a word without a meaning in this
                // pair (rule 4) must not take the place of one with a meaning.
                // The planner takes the first 10.
                let due = try await db.dueCards(lang: lang, today: today, kinds: [kind])
                let left = settings.learningNewPerDay - (try await db.startedCount(on: today, lang: lang))
                // ponytail: #161 adds the checked lists' next words
                let newWords = Array(try await db.newPool(lang: lang, limit: .max).filter(hasMeaning)
                    .prefix(max(min(left, length), 0)))
                let practice = try await db.practiceCards(lang: lang, kind: kind, limit: .max)
                plan = SessionPlanner.trainer(kind: kind, due: due.filter(hasMeaning), newWords: newWords,
                                              practice: practice.filter(hasMeaning), today: today)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await show()
    }

    /// Grades the option tapped.
    func choose(_ option: Int) async {
        guard feedback == nil, let question, let right = question.rightIndex,
              question.options.indices.contains(option) else { return }
        await answer(option == right ? .right : .wrong, chosen: option, mindTheAccent: false)
    }

    /// Check: grades the typed answer by the answer mode.
    func check() async {
        guard feedback == nil, let question, question.input == .typed else { return }
        let grade = AnswerChecker.grade(typed, expected: question.word.term, lang: question.word.key.lang,
                                        mode: questionMode)
        await answer(grade.outcome, chosen: nil, mindTheAccent: grade.mindTheAccent)
    }

    /// "Don't know" counts as wrong.
    func dontKnow() async {
        guard feedback == nil, question != nil else { return }
        await answer(.wrong, chosen: nil, mindTheAccent: false)
    }

    /// Continue: the next question, or the summary after the last.
    func next() async {
        guard feedback != nil else { return }
        await pendingWrite?.value
        index += 1
        await show()
    }

    /// The haptic of an answer; nil when Haptics is off.
    func haptic(for outcome: Outcome) -> SensoryFeedback? {
        player.haptic(for: outcome)
    }

    // MARK: Questions

    private func hasMeaning(_ card: CardState) -> Bool {
        !(words[card.key.word]?.meaning.isEmpty ?? true)
    }

    private func hasMeaning(_ word: LearnWord) -> Bool {
        !(words[word.key]?.meaning.isEmpty ?? true)
    }

    /// Builds and shows the question of `plan[index]`, skipping without a
    /// log row the cards that have none; after the last, the summary.
    private func show() async {
        question = nil
        feedback = nil
        typed = ""
        while index < plan.count {
            let card = plan[index].card
            if let word = words[card.key.word], let built = await build(card, word) {
                question = built
                position = index + 1
                total = plan.count
                shownAt = clock.now()
                phase = .question
                return
            }
            plan.remove(at: index)
        }
        question = nil
        total = plan.count
        guard answered > 0 else {
            phase = .empty
            return
        }
        await loadSummary()
        phase = .summary
    }

    /// The summary's numbers from this run's log rows (`reviewRows(run:)`),
    /// as Today's come from the day's.
    private func loadSummary() async {
        do {
            summary = ReviewSummary.of(try await db.reviewRows(run: runID))
        } catch {
            summary = summary ?? ReviewSummary()
            errorMessage = error.localizedDescription
        }
    }

    /// The question of `card`: options from the enrolled words first, then,
    /// if they leave a choice short, from the source sample. Every meaning
    /// is in the pair's meanings language.
    private func build(_ card: CardState, _ word: WordChoice) async -> Question? {
        let mode = settings.learningAnswerMode
        questionMode = mode
        let question = QuestionBuilder.build(card: card, word: word, candidates: enrolled, mode: mode,
                                             meaningsLang: meaningsLang, rng: &rng)
        guard QuestionBuilder.wantsChoice(card, mode: mode),
              (question?.options.count ?? 0) < DistractorPicker.defaultCount + 1 else { return question }
        let sample = await sample(for: word)
        guard !sample.isEmpty else { return question }
        return QuestionBuilder.build(card: card, word: word, candidates: enrolled + sample, mode: mode,
                                     meaningsLang: meaningsLang, rng: &rng)
    }

    /// The source sample for `word`'s part of speech, read once per run and
    /// source: with a pair, from the pair dictionary that gave its meaning,
    /// else the pair's first; without (Other), from its own source.
    private func sample(for word: WordChoice) async -> [WordChoice] {
        let pos = DistractorPicker.primaryPOS(word.partOfSpeech)
        let source = meaningsLang == nil ? word.entry?.source : word.meaningSource
        let key = (source ?? "") + "|" + pos
        if let cached = samples[key] { return cached }
        let sample = (try? await db.distractorSample(lang: lang, meaningsLang: meaningsLang, source: source,
                                                     sourceOrder: sourceOrder, pos: pos,
                                                     near: word.entry?.word ?? word.term, seed: rng.next())) ?? []
        samples[key] = sample
        return sample
    }

    // MARK: Answers

    /// Grades at once (the feedback bar, the sound; the view plays the
    /// haptic), then writes the answer, on the learning day of this moment,
    /// and requeues a wrong card. A run across 4 AM writes each answer on
    /// its own day; its plan stays.
    private func answer(_ outcome: Outcome, chosen: Int?, mindTheAccent: Bool) async {
        guard let question else { return }
        let today = clock.today
        feedback = AnswerFeedback(outcome: outcome, chosenIndex: chosen, mindTheAccent: mindTheAccent,
                                  rightAnswer: question.rightAnswer)
        player.play(outcome)
        let durationMs = min(max(Int(clock.now().timeIntervalSince(shownAt) * 1000), 0), ReviewSummary.durationCapMs)
        answered += 1
        let record = AnswerRecord(card: question.card.key, exercise: question.exercise, mode: run.mode,
                                  runID: runID, outcome: outcome, durationMs: durationMs)
        let at = index
        let write = Task { await self.write(record, today: today, wrongAt: outcome.isRight ? nil : at) }
        pendingWrite = write
        await write.value
    }

    /// Writes the answer with the daily goal in force (E10's `learn_day`),
    /// and requeues a wrong card at the end.
    private func write(_ record: AnswerRecord, today: LearnDay, wrongAt index: Int?) async {
        do {
            let card = try await db.recordAnswer(record, today: today, goal: settings.learningDailyGoal)
            if let index {
                plan = SessionPlanner.requeue(plan, wrongAt: index, card: card)
                total = plan.count
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - My words, interim (#158, until E3 #154)

/// Today's Bookmarks list, moved: My words that resolve, newest first. A
/// key that no longer resolves stays stored and is skipped (#138).
@MainActor
final class MyWordsViewModel: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []
    @Published var errorMessage: String?

    private let db: DatabaseService

    init(db: DatabaseService = .shared) {
        self.db = db
    }

    func load() async {
        do {
            entries = try await db.fetchMyWords()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The swipe is Stop learning: every My words row of the word leaves,
    /// whatever its dictionary, and its cards are paused.
    func stopLearning(_ entry: DictionaryEntry) async {
        do {
            try await db.stopLearning(EntryKey(entry))
            entries = try await db.fetchMyWords()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
