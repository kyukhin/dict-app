// LearnViewModel.swift
// The Learn tab (0131-learning.md, #158): the pair picker and the Learn
// home, with E3's Lists section (#154). The runs: the trainers (#159), the
// session and mistakes practice (#161); match the pairs (#160). The daily
// goal and the streak on the home, and the statistics screen (0166, #164).

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
    /// The chosen pair's packs, in install order (0237): the home shows the
    /// first one on its way, with its progress, or failed, with Try again.
    @Published private(set) var pairPacks: [PackID] = []
    @Published private(set) var today: Today?
    /// Words of the chosen language with a card in mistakes practice: wrong
    /// in the last 7 days and not right since. 0 hides the row.
    @Published private(set) var mistakeCount = 0
    /// My words that resolve, in every language.
    @Published private(set) var myWordsCount = 0
    /// Match the pairs has its 5 words (#160); else "Learn 5 words first".
    @Published private(set) var canMatch = false
    /// The Lists section (0130, #154): the chosen language's checked lists,
    /// in the Lists screen's order.
    @Published private(set) var checkedLists: [WordList] = []
    /// The checked lists' progress in the chosen language (0166).
    @Published private(set) var listProgress: [WordListID: ListProgress] = [:]
    /// The chosen language has lists, built-in or imported: the Lists
    /// section offers New words from.
    @Published private(set) var hasLists = false
    /// False until the first load ends, so the picker never flashes before the home.
    @Published private(set) var isLoaded = false
    /// Today's exercises in every language and the daily goal (0166, #164).
    @Published private(set) var goal: GoalProgress?
    /// The streak, every language (0166, #164).
    @Published private(set) var streak: StreakState?
    /// A failed choice or load, shown in an alert until dismissed; a reload
    /// does not clear it.
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

    /// The trainers need a word in learning or a checked list of the
    /// language; else "Learn a few words first".
    var canTrain: Bool {
        switch today {
        case .counts?, .allDone?: return true
        case .chooseLists?, .addWords?, nil: return false
        }
    }

    /// My words as a list, for its row (E3's list screen, #154).
    var myWordsList: WordList {
        WordList(id: .myWords, kind: .myWords, lang: WordList.myWordsLanguage, level: "", title: "", count: myWordsCount)
    }

    /// The Lists section's "New words from" row: once a list is checked or a
    /// word is in learning, while Today no longer offers "Choose lists".
    var showsNewWordsFrom: Bool { hasLists && today != .chooseLists }

    /// Reads the learned languages, then the picker's rows or the home.
    /// `locale` names the languages for the picker's order.
    func load(locale: Locale) async {
        learned = languages.learned
        language = languages.chosen
        do {
            if learned.isEmpty {
                today = nil
                pair = nil
                canMatch = false
                pickerRows = LearningPairs.pickerRows(offered: try await db.learningPairs().keys,
                                                      withLists: languagesWithLists, learned: learned,
                                                      uiLanguage: languages.uiLanguage(),
                                                      name: { Self.languageName($0, locale: locale) })
                var sizes: [LearningPair: Int64] = [:]
                for row in pickerRows {
                    sizes[row] = await languages.packs.downloadSize(of: row)
                }
                downloadSizes = sizes
                pairPacks = []
            } else {
                try await loadHome()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// Try again on the home's install row: the chosen pair's missing packs.
    func retryInstall() {
        guard let pair else { return }
        languages.install(pair)
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

    /// Today's counts, as Start's session would ask them: the words due,
    /// and the new words left (`NewWordPicker`: My words first, then the
    /// checked lists, those with a meaning in the pair); and the mistakes.
    /// Due and mistake words count only with a meaning in the pair, as the
    /// runs ask them, so Start and the mistakes row never open an empty
    /// run. Nothing to learn yet (no word in learning, no list of the
    /// language checked): the empty state, "Choose lists" when the language
    /// has lists, built-in or imported.
    private func loadHome() async throws {
        guard let language else { return }
        let day = clock.today
        try await loadGoal(today: day)
        pair = try await languages.pair(for: language)
        if let pair {
            pairPacks = await languages.packs.packs(of: pair)
        } else {
            pairPacks = []
        }
        // As the My words screen counts: one per word, those waiting for a
        // pack too (#245).
        myWordsCount = try await db.myWordsEntries().count
        // The language's lists in the Lists screen's order; a built-in list
        // whose pack is missing is not among them (0237).
        let lists = WordListsViewModel.sections(try await db.wordLists(), learned: [language], uiLanguage: "")
            .flatMap(\.lists)
            .filter { $0.kind != .myWords }
        let checked = settings.learningListIDs
        checkedLists = lists.filter { checked.contains($0.id) }
        hasLists = languagesWithLists.contains(language) || !lists.isEmpty
        listProgress = try await WordListsViewModel.progress(of: checkedLists, myWordsLanguage: language, db: db)
        let hasWordsInLearning = try await db.learningWordCount(lang: language) > 0
        guard hasWordsInLearning || !checkedLists.isEmpty else {
            today = hasLists ? .chooseLists : .addWords
            mistakeCount = 0
            canMatch = false
            return
        }
        let meaningsLang = pair?.meaningsLang
        let sourceOrder = try await languages.sourceOrder(lang: language, meaningsLang: meaningsLang)
        let dueWords = Set(try await db.dueCards(lang: language, today: day).map(\.key.word))
        let mistakeWords = Set(try await db.mistakeCards(since: SessionPlanner.mistakesSince(today: day), lang: language)
            .map(\.key.word))
        let asked = try await db.wordsWithMeaning(dueWords.union(mistakeWords), lang: language,
                                                  meaningsLang: meaningsLang, sourceOrder: sourceOrder)
        let due = dueWords.intersection(asked).count
        let newWords = try await NewWordPicker(db: db, settings: settings)
            .pick(lang: language, meaningsLang: meaningsLang, sourceOrder: sourceOrder, today: day)
        let newLeft = newWords.count
        today = due == 0 && newLeft == 0 ? .allDone : .counts(due: due, newLeft: newLeft)
        mistakeCount = mistakeWords.intersection(asked).count
        canMatch = try await MatchWordPicker(db: db).pick(lang: language, meaningsLang: meaningsLang,
                                                          sourceOrder: sourceOrder, newWords: newWords) != nil
    }

    /// The ring and the flame (0166): today's exercises of every language
    /// against the current goal, and the streak over every day's count.
    private func loadGoal(today: LearnDay) async throws {
        async let counts = db.dayCounts()
        async let goals = db.learnDayGoals()
        let exercises = try await counts.mapValues(\.exercises)
        let current = settings.learningDailyGoal
        goal = GoalProgress(answered: exercises[today] ?? 0, goal: current)
        streak = Streak.compute(counts: exercises, goals: try await goals, currentGoal: current, today: today)
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

/// The daily goal after a run: exercises answered today in every language,
/// and the goal (E10, #163).
struct GoalProgress: Equatable {
    let answered: Int
    let goal: Int

    /// Today's goal is met: the ring closes and the flame lights up.
    var isMet: Bool { answered >= goal }
}

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
    /// What runs, in the chosen language.
    enum Run: Hashable {
        /// Recognition or Production: 10 items of its own direction.
        case trainer(CardKind)
        /// Start, the daily session (#161): due cards, then new words.
        case session
        /// Practise mistakes (#161): the cards wrong in the last 7 days and
        /// not right since.
        case mistakes

        var mode: RunMode {
            switch self {
            case .trainer: return .trainer
            case .session: return .session
            case .mistakes: return .mistakes
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
    /// The daily goal at the end of the run; nil until then.
    @Published private(set) var goalProgress: GoalProgress?
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
    /// The answer that reaches today's goal cancels today's reminder (#162).
    private let reminder: LearningReminder?
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
         clock: LearningClock = LearningClock(), player: FeedbackPlayer? = nil, reminder: LearningReminder? = nil,
         seed: UInt64? = LearningLaunchOptions.seed, answerHints: Bool = LearningLaunchOptions.answerHints) {
        self.run = run
        self.lang = lang
        self.meaningsLang = meaningsLang
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        self.player = player ?? .shared
        // The app's reminder works on the app's settings; a test's own
        // settings get none unless it brings one.
        self.reminder = reminder ?? (settings === SettingsService.shared ? .shared : nil)
        self.rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
        self.answerHints = answerHints
    }

    /// Plans the run and shows its first question. Cards are read whole,
    /// then filtered: a word without a meaning in this pair (rule 4) must
    /// not take the place of one with a meaning.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            let today = clock.today
            sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
            try await loadWords()
            switch run {
            case let .trainer(kind):
                // The planner takes the first 10; new words only fill the room the due cards leave.
                let due = try await db.dueCards(lang: lang, today: today, kinds: [kind]).filter(hasMeaning)
                let newWords = try await startNewWords(today: today, limit: SessionPlanner.trainerLength - due.count)
                let practice = try await db.practiceCards(lang: lang, kind: kind, limit: .max).filter(hasMeaning)
                plan = SessionPlanner.trainer(kind: kind, due: due, newWords: newWords, practice: practice, today: today)
            case .session:
                let due = try await db.dueCards(lang: lang, today: today).filter(hasMeaning)
                let newWords = try await startNewWords(today: today)
                plan = SessionPlanner.session(due: due, newWords: newWords, today: today)
            case .mistakes:
                let cards = try await db.mistakeCards(since: SessionPlanner.mistakesSince(today: today), lang: lang)
                plan = SessionPlanner.mistakes(cards: cards.filter(hasMeaning))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await show()
    }

    /// The words of `lang` in learning with their meanings in the pair: the
    /// questions' words and their first options.
    private func loadWords() async throws {
        enrolled = try await db.wordChoices(lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder)
        words = Dictionary(enrolled.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The new words this run starts, at most `limit` within the daily limit
    /// (`NewWordPicker`). The checked lists' words picked get their rows and
    /// two new cards now (`introduce`), so they are asked like the others;
    /// if the run is closed before they are answered, they come first next
    /// time.
    private func startNewWords(today: LearnDay, limit: Int = .max) async throws -> [LearnWord] {
        let pick = try await NewWordPicker(db: db, settings: settings)
            .pick(lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder, today: today, limit: limit)
        guard !pick.lists.isEmpty else { return pick.pool }
        try await db.introduce(pick.lists, sourceOrder: sourceOrder, today: today)
        try await loadWords()
        let pool = Dictionary(try await db.newPool(lang: lang, limit: .max).map { ($0.key, $0) },
                              uniquingKeysWith: { a, _ in a })
        return pick.pool + pick.lists.compactMap { pool[$0.key] }
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
            // Skipped: the cards around it may now be of one word.
            plan.remove(at: index)
            plan = SessionPlanner.separatingWords(plan, from: index)
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
    /// as Today's come from the day's, and the daily goal.
    private func loadSummary() async {
        do {
            summary = ReviewSummary.of(try await db.reviewRows(run: runID))
            goalProgress = GoalProgress(answered: try await db.answeredCount(on: clock.today),
                                        goal: settings.learningDailyGoal)
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
    /// and requeues a wrong card at the end, apart from its word's other card.
    private func write(_ record: AnswerRecord, today: LearnDay, wrongAt index: Int?) async {
        do {
            let card = try await db.recordAnswer(record, today: today, goal: settings.learningDailyGoal)
            await reminder?.answerRecorded(today: today)
            if let index {
                plan = SessionPlanner.separatingWords(SessionPlanner.requeue(plan, wrongAt: index, card: card),
                                                      from: index + 1)
                total = plan.count
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Match the pairs (#160)

/// The words of a round of match the pairs in one language (0131, "Match
/// the pairs"): the words on the Learning stage, then new words within the
/// daily limit (`NewWordPicker`'s pick), then the lowest rungs; each with a
/// meaning in the pair, no two alike (`MatchRound.pick`). Paused words
/// never. It only reads: a round introduces the list words it takes. The
/// Learn home asks it whether the trainer is enabled.
@MainActor
struct MatchWordPicker {
    struct Pick: Equatable {
        /// The round's words.
        let words: [WordChoice]
        /// The checked lists' words among them, not in learning yet.
        let lists: [WordListItem]
    }

    let db: DatabaseService

    /// nil with fewer than 5 such words.
    func pick(lang: String, meaningsLang: String?, sourceOrder: [String],
              newWords: NewWordPicker.Pick) async throws -> Pick? {
        let enrolled = try await db.wordChoices(lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder)
        let byKey = Dictionary(enrolled.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        // The started words' recognition cards, not paused, the lowest rung
        // first: rung 0 is the Learning stage.
        let started = try await db.practiceCards(lang: lang, kind: .recognition, limit: .max)
        let learning = started.filter { $0.step == 0 }.compactMap { byKey[$0.key.word] }
        let rungs = started.filter { $0.step > 0 }.compactMap { byKey[$0.key.word] }
        let pool = newWords.pool.compactMap { byKey[$0.key] }
        let lists = newWords.lists.compactMap { item in
            newWords.listMeanings[item.key].map {
                WordChoice(key: item.key, term: item.term, endings: item.endings, meaning: $0,
                           partOfSpeech: item.partOfSpeech, listID: item.listID.rawValue, isEnrolled: false)
            }
        }
        guard let words = MatchRound.pick(learning + pool + lists + rungs) else { return nil }
        let keys = Set(words.map(\.key))
        return Pick(words: words, lists: newWords.lists.filter { keys.contains($0.key) })
    }
}

/// A graded pair: the haptic, the sound and the VoiceOver announcement.
/// `id` tells two pairs with the same outcome apart.
struct PairFeedback: Equatable {
    let id: Int
    /// `right` for a matched pair, `wrong` for a wrong one.
    let outcome: Outcome
}

/// Match the pairs (0131, #160): rounds of five words of the chosen
/// language and their meanings, with a timer. Each word is one recognition
/// answer, written the moment its pair is matched, through the trainers'
/// path (`recordAnswer` with the daily goal, then the reminder's
/// `answerRecorded`): right if matched at the first try, wrong if it was in
/// a wrong pair before. A round is 5 items toward the daily goal.
@MainActor
final class MatchPairsViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case playing
        /// All pairs matched: the round's time and mistakes.
        case finished
        /// Fewer than 5 words: "Learn 5 words first".
        case unavailable
    }

    /// How long a wrong pair flashes red.
    static let flashDuration: Duration = .milliseconds(600)

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var round: MatchRound?
    /// The tiles of the wrong pair flashing red.
    @Published private(set) var flashing: Set<MatchRound.Tile> = []
    @Published private(set) var feedback: PairFeedback?
    /// When the round showed.
    @Published private(set) var startedAt = Date()
    /// When its last pair was matched; nil while it runs.
    @Published private(set) var finishedAt: Date?
    @Published var errorMessage: String?

    /// The chosen language: a round never mixes languages.
    let lang: String
    /// Its pair's meanings language; nil without a pair (Other).
    let meaningsLang: String?
    /// `-learningAnswerHints`.
    let answerHints: Bool
    /// One per round: its log rows.
    private(set) var runID = UUID()

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    private let player: FeedbackPlayer
    /// The answer that reaches today's goal cancels today's reminder (#162).
    private let reminder: LearningReminder?
    private var rng: SplitMix64
    /// The pair's dictionaries first (`LearningLanguageService.sourceOrder`).
    private var sourceOrder: [String] = []
    /// The round's start, then the last match: an answer's time runs from it.
    private var lastMatchAt = Date()
    /// The answers' writes, one after another.
    private var writes: Task<Void, Never>?
    private var feedbackCount = 0
    private var isStarted = false

    init(lang: String, meaningsLang: String?, db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil, clock: LearningClock = LearningClock(),
         player: FeedbackPlayer? = nil, reminder: LearningReminder? = nil,
         seed: UInt64? = LearningLaunchOptions.seed, answerHints: Bool = LearningLaunchOptions.answerHints) {
        self.lang = lang
        self.meaningsLang = meaningsLang
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        self.player = player ?? .shared
        // As in `ExerciseRunViewModel`: the app's reminder on the app's settings.
        self.reminder = reminder ?? (settings === SettingsService.shared ? .shared : nil)
        self.rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
        self.answerHints = answerHints
    }

    /// The round's time, m:ss on screen: from its start to its last match,
    /// or to `now` while it runs.
    func elapsed(at now: Date) -> Duration {
        .seconds(max(0, Int((finishedAt ?? now).timeIntervalSince(startedAt))))
    }

    /// The first round.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
        } catch {
            errorMessage = error.localizedDescription
        }
        await newRound()
    }

    /// Next round: five words picked again, once the answers are written.
    func nextRound() async {
        guard phase == .finished else { return }
        await newRound()
    }

    /// The haptic of a pair; nil when Haptics is off.
    func haptic(for outcome: Outcome) -> SensoryFeedback? {
        player.haptic(for: outcome)
    }

    /// A tap on a tile. A right pair is matched, with the success haptic and
    /// sound, and its word's answer written at once; a wrong pair flashes
    /// red, with the error haptic and sound, and is charged to its word.
    func tap(_ tile: MatchRound.Tile) async {
        guard phase == .playing, var round else { return }
        let result = round.tap(tile)
        self.round = round
        switch result {
        case .ignored:
            return
        case .selected:
            flashing = []
        case let .mismatched(word, meaning):
            flashing = Set([round.tiles(of: word)?.word, round.tiles(of: meaning)?.meaning].compactMap { $0 })
            give(.wrong)
            let id = feedbackCount
            Task {
                try? await Task.sleep(for: Self.flashDuration)
                if self.feedbackCount == id { self.flashing = [] }
            }
        case let .matched(word):
            flashing = []
            give(.right)
            let now = clock.now()
            let durationMs = min(max(Int(now.timeIntervalSince(lastMatchAt) * 1000), 0), ReviewSummary.durationCapMs)
            lastMatchAt = now
            let record = AnswerRecord(card: CardKey(word: round.words[word].key, kind: .recognition), exercise: .match,
                                      mode: .trainer, runID: runID, outcome: round.outcome(of: word),
                                      durationMs: durationMs)
            let today = clock.today
            let previous = writes
            let write = Task { await previous?.value; await self.write(record, today: today) }
            writes = write
            if round.isComplete {
                finishedAt = now
                phase = .finished
            }
            await write.value
        }
    }

    /// Picks the round's words and introduces the list words among them,
    /// after the answers so far are written (they count toward the daily
    /// limit and move the cards).
    private func newRound() async {
        // Loading before the wait, so a second "Next round" meanwhile finds
        // no finished round to replace (#268).
        phase = .loading
        await writes?.value
        round = nil
        flashing = []
        finishedAt = nil
        do {
            let today = clock.today
            let newWords = try await NewWordPicker(db: db, settings: settings)
                .pick(lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder, today: today)
            guard let pick = try await MatchWordPicker(db: db).pick(lang: lang, meaningsLang: meaningsLang,
                                                                    sourceOrder: sourceOrder, newWords: newWords) else {
                phase = .unavailable
                return
            }
            if !pick.lists.isEmpty {
                try await db.introduce(pick.lists, sourceOrder: sourceOrder, today: today)
            }
            round = MatchRound(words: pick.words, rng: &rng)
            runID = UUID()
            startedAt = clock.now()
            lastMatchAt = startedAt
            errorMessage = nil
            phase = .playing
        } catch {
            errorMessage = error.localizedDescription
            phase = .unavailable
        }
    }

    private func give(_ outcome: Outcome) {
        feedbackCount += 1
        feedback = PairFeedback(id: feedbackCount, outcome: outcome)
        player.play(outcome)
    }

    /// Writes the answer with the daily goal in force (E10's `learn_day`),
    /// then lets the reminder cancel today's when the goal is reached.
    private func write(_ record: AnswerRecord, today: LearnDay) async {
        do {
            try await db.recordAnswer(record, today: today, goal: settings.learningDailyGoal)
            await reminder?.answerRecorded(today: today)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - The goal and the streak on the Learn home (0166, #164)

extension LearnViewModel {
    /// The ring, as VoiceOver reads it: "Daily goal: 12 of 20 exercises".
    nonisolated static func goalLabel(_ goal: GoalProgress, locale: Locale) -> String {
        String(localized: "learn.goal.a11y \(goal.answered) \(goal.goal)",
               bundle: SettingsViewModel.localizedBundle(for: locale), locale: locale)
    }

    /// The flame and the snowflake, as VoiceOver reads them: "5-day streak,
    /// 2 freezes".
    nonisolated static func streakLabel(_ streak: StreakState, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        let freezes = String(localized: "learn.streak.freezes \(streak.freezes)", bundle: bundle, locale: locale)
        return String(localized: "learn.streak.a11y \(streak.current) \(freezes)", bundle: bundle, locale: locale)
    }
}

// MARK: - Statistics (0166, #164)

/// The statistics screen (0166, "Statistics screen"). One `load()` reads
/// every block with `async let`, on `LearningClock.today` and the language
/// chosen on the Learn home (`learning_language`). The goal, the streak and
/// the 30-day chart count every language; the other blocks count the chosen
/// one, and the switch reloads only them. Every number comes from #163's
/// queries and aggregates.
@MainActor
final class StatisticsViewModel: ObservableObject {
    /// A list of the Lists block.
    struct ListRow: Identifiable, Equatable {
        let list: WordList
        let progress: ListProgress
        /// nil for an empty list: no forecast.
        let forecast: Forecast?
        var id: WordListID { list.id }
    }

    /// A row of the hardest words or verbs.
    struct WordRow: Identifiable, Equatable {
        let word: HardWord
        /// In the pair's meanings language (0131, "Meanings"); "" when none.
        let meaning: String
        /// The Definition it opens; nil when its entry does not resolve.
        let entry: DictionaryEntry?
        var id: WordKey { word.key }
    }

    /// A tense of the Conjugation block.
    struct TenseRow: Identifiable, Equatable {
        /// `ConjugationTense.rawValue`.
        let tense: String
        let tally: Tally
        var id: String { tense }
    }

    /// The chosen language's blocks.
    struct LanguageBlocks: Equatable {
        /// Today's answers of the language (`ReviewSummary`).
        var today = ReviewSummary()
        var lists: [ListRow] = []
        var accuracy = DirectionAccuracy()
        var hardestWords: [WordRow] = []
        /// In the tables' order; empty without drill answers: no block.
        var tenses: [TenseRow] = []
        var hardestVerbs: [WordRow] = []
    }

    /// The learned languages: the switch shows with two or more.
    @Published private(set) var learned: [String] = []
    /// The chosen language; nil while none is learned.
    @Published private(set) var language: String?
    @Published private(set) var isLoaded = false
    /// No answer yet in any language: "Your statistics appear after your
    /// first exercise."
    @Published private(set) var isEmpty = true
    /// The day the numbers are for.
    @Published private(set) var today: LearnDay
    /// Today's exercises in every language and the current goal.
    @Published private(set) var goal = GoalProgress(answered: 0, goal: 0)
    /// Every language.
    @Published private(set) var streak = StreakState()
    /// The 30-day chart, every language: oldest first, today last.
    @Published private(set) var series: [DayPoint] = []
    @Published private(set) var blocks = LanguageBlocks()
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
        today = clock.today
    }

    /// Every block.
    func load() async {
        learned = languages.learned
        language = languages.chosen
        let day = clock.today
        today = day
        do {
            async let counts = db.dayCounts()
            async let goals = db.learnDayGoals()
            async let perLanguage = languageBlocks(language, today: day)
            let exercises = try await counts.mapValues(\.exercises)
            let current = settings.learningDailyGoal
            goal = GoalProgress(answered: exercises[day] ?? 0, goal: current)
            streak = Streak.compute(counts: exercises, goals: try await goals, currentGoal: current, today: day)
            series = DailySeries.last30(exercises, today: day)
            blocks = try await perLanguage
            isEmpty = language == nil || exercises.values.allSatisfy { $0 == 0 }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// The switch: remembers `lang`, as the Learn home's does, and reloads
    /// the chosen language's blocks.
    func select(_ lang: String) async {
        guard lang != language, learned.contains(lang) else { return }
        languages.chosen = lang
        language = lang
        do {
            let loaded = try await languageBlocks(lang, today: today)
            // A later switch won meanwhile: its blocks, not these (#271).
            guard language == lang else { return }
            blocks = loaded
            errorMessage = nil
        } catch {
            guard language == lang else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Today, the lists, the accuracy, the hardest words and the Conjugation
    /// block of `lang`: the last 30 days are today and the 29 days before.
    private func languageBlocks(_ lang: String?, today: LearnDay) async throws -> LanguageBlocks {
        guard let lang else { return LanguageBlocks() }
        let since = DailySeries.start(today: today)
        async let rows = db.reviewRows(day: today, lang: lang)
        async let accuracy = db.directionAccuracy(since: since, lang: lang)
        async let words = db.hardestWords(since: since, lang: lang)
        async let tenses = db.tenseAccuracy(since: since, lang: lang)
        async let verbs = db.hardestVerbs(since: since, lang: lang)
        async let lists = listRows(lang: lang, today: today)
        var blocks = LanguageBlocks()
        blocks.today = ReviewSummary.of(try await rows)
        blocks.accuracy = try await accuracy
        blocks.tenses = ConjugationTense.ordered(try await tenses).map { TenseRow(tense: $0.tense, tally: $0.tally) }
        let hardWords = try await words
        let shown = try await wordRows(hardWords + (try await verbs), lang: lang)
        blocks.hardestWords = Array(shown.prefix(hardWords.count))
        blocks.hardestVerbs = Array(shown.dropFirst(hardWords.count))
        blocks.lists = try await lists
        return blocks
    }

    /// The checked lists of `lang` and every list of it with a started word,
    /// My words included with its words of `lang`, each with its forecast.
    private func listRows(lang: String, today: LearnDay) async throws -> [ListRow] {
        let checked = settings.learningListIDs
        let states = try await db.wordStates(lang: lang)
        let reader = ListProgressReader(db: db)
        var rows: [ListRow] = []
        for list in try await db.wordLists() where list.lang == lang || list.kind == .myWords {
            let progress = try await reader.progress(of: list.id, lang: lang, states: states)
            guard checked.contains(list.id) || !progress.startedDays.isEmpty else { continue }
            rows.append(ListRow(list: list, progress: progress,
                                forecast: Forecast.days(progress: progress, states: states, today: today)))
        }
        return rows
    }

    /// Each word with its meaning in the pair's meanings language (English
    /// for Greek via Russian), as the exercises show it, and its entry. The
    /// via changes only these meanings, never a number.
    private func wordRows(_ words: [HardWord], lang: String) async throws -> [WordRow] {
        guard !words.isEmpty else { return [] }
        let meaningsLang = try await languages.pair(for: lang)?.meaningsLang
        let sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
        let queries = words.map {
            MeaningQuery(key: $0.key, lookup: $0.entry?.word ?? $0.term, translation: $0.translation,
                         translationLang: $0.translationLang, entry: $0.entry)
        }
        let meanings = try await db.meanings(of: queries, lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder)
        var entries: [EntryKey: DictionaryEntry] = [:]
        for key in Set(words.compactMap(\.entry)) {
            entries[key] = try await db.entry(for: key)
        }
        return words.map { word in
            WordRow(word: word, meaning: meanings[word.key] ?? "", entry: word.entry.flatMap { entries[$0] })
        }
    }

    /// A list's forecast (0166, "Lists"): "All learned in ~129 days", over
    /// 365 days "All learned in over a year", "Start learning to see a
    /// forecast" or "All learned".
    nonisolated static func forecastText(_ forecast: Forecast, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        switch forecast {
        case let .days(days) where days > 365:
            return String(localized: "stats.forecast.overYear", bundle: bundle, locale: locale)
        case let .days(days):
            return String(localized: "stats.forecast.days \(days)", bundle: bundle, locale: locale)
        case .noPace:
            return String(localized: "stats.forecast.noPace", bundle: bundle, locale: locale)
        case .done:
            return String(localized: "stats.forecast.done", bundle: bundle, locale: locale)
        }
    }
}
