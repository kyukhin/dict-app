// LearnViewModel.swift
// The Learn tab (0131-learning.md, #158): the pair picker and the Learn
// home, with E3's Lists section (#154). The runs: the trainers (#159), the
// session and mistakes practice (#161); match the pairs (#160). The daily
// goal and the streak on the home, and the statistics screen (0166, #164).
// The conjugation drill's screen and run (0132, #168). The Grammar screen
// and a grammar topic (0133, #172).

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
    /// The pair tabs (#293), one per learned language in the stored order.
    @Published private(set) var tabs: [PairTab] = []
    /// The language of the home, the selected tab's; nil while none is learned.
    @Published private(set) var language: String?
    /// The chosen language's pair; nil for Other or while none is learned.
    @Published private(set) var pair: LearningPair?
    /// The picker's rows while no language is learned, and "+"'s (#293) without
    /// the learned ones (`LearningPairs.pickerRows`).
    @Published private(set) var pickerRows: [LearningPair] = []
    /// What each picker row still has to download, in bytes; 0 or absent: nothing.
    @Published private(set) var downloadSizes: [LearningPair: Int64] = [:]
    /// The chosen pair's packs, in install order (0237): the home shows the
    /// first one on its way, with its progress, or failed, with Try again.
    @Published private(set) var pairPacks: [PackID] = []
    @Published private(set) var today: Today?
    /// The items left of the chosen language's lesson closed early (#296):
    /// "Continue lesson · 7 left" replaces Start. nil: none to continue.
    @Published private(set) var lessonLeft: Int?
    /// Words of the chosen language with a card in mistakes practice: wrong
    /// in the last 7 days and not right since. 0 hides the row.
    @Published private(set) var mistakeCount = 0
    /// My words that resolve, in the tab's language (`WordKey.lang`, #295).
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
    /// The chosen language's grammar topics (0133, #172): the Grammar
    /// section's row, hidden at 0 (no topics, or no pack).
    @Published private(set) var grammarTopicCount = 0
    /// False until the first load ends, so the picker never flashes before the home.
    @Published private(set) var isLoaded = false
    /// Today's exercises in every language and the daily goal (0166, #164).
    @Published private(set) var goal: GoalProgress?
    /// The Conjugation row's tense level (0132, #168): shown while Greek is
    /// the chosen language, nil otherwise.
    @Published private(set) var drillLevel: DrillLevel?
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

    /// The Lists section's "Learning from" row: once a list is checked or a
    /// word is in learning, while Today no longer offers "Choose lists".
    var showsNewWordsFrom: Bool { hasLists && today != .chooseLists }

    /// Reads the learned languages, then the picker's rows or the home.
    /// `locale` names the languages for the picker's order.
    func load(locale: Locale) async {
        // Set on every way out, an early return for a newer load included.
        defer { isLoaded = true }
        fullLoad += 1
        let fullTicket = fullLoad
        homeLoad += 1
        let ticket = homeLoad
        learned = languages.learned
        language = languages.chosen
        do {
            let tabs = try await loadTabs()
            // The tabs belong to the latest full load; the home, to the latest
            // load or tab selection, which then loads its own.
            guard fullTicket == fullLoad else { return }
            // In the current order: a drag while they loaded (`move`) has
            // reordered `learned` since `loadTabs` read it.
            self.tabs = learned.compactMap { lang in tabs.first { $0.lang == lang } }
            guard ticket == homeLoad else { return }
            if learned.isEmpty {
                today = nil
                lessonLeft = nil
                pair = nil
                canMatch = false
                drillLevel = nil
                grammarTopicCount = 0
                let rows = LearningPairs.pickerRows(offered: try await db.learningPairs().keys,
                                                    withLists: languagesWithLists, learned: learned,
                                                    uiLanguage: languages.uiLanguage(),
                                                    name: { Self.languageName($0, locale: locale) })
                var sizes: [LearningPair: Int64] = [:]
                for row in rows {
                    sizes[row] = await languages.packs.downloadSize(of: row)
                }
                guard ticket == homeLoad else { return }
                pickerRows = rows
                downloadSizes = sizes
                pairPacks = []
            } else {
                try await loadHome()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// A tab for each learned language, with its pair.
    private func loadTabs() async throws -> [PairTab] {
        var tabs: [PairTab] = []
        for lang in learned {
            tabs.append(PairTab(lang: lang, pair: try await languages.pair(for: lang)))
        }
        return tabs
    }

    /// "+" (#293): the pairs of the languages not learned, with their
    /// download sizes, for the picker it pushes.
    func loadAddRows(locale: Locale) async {
        do {
            pickerRows = LearningPairs.pickerRows(offered: try await db.learningPairs().keys,
                                                  withLists: languagesWithLists, learned: languages.learned,
                                                  uiLanguage: languages.uiLanguage(),
                                                  name: { Self.languageName($0, locale: locale) })
            var sizes: [LearningPair: Int64] = [:]
            for row in pickerRows {
                sizes[row] = await languages.packs.downloadSize(of: row)
            }
            downloadSizes = sizes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A tab: remembers `lang` and shows its home.
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

    /// A drag, or VoiceOver's "Move earlier" and "Move later" (#293): `lang`
    /// takes place `index` among the tabs. The selection stays.
    func move(_ lang: String, to index: Int) {
        let order = PairTabOrder.moving(lang, to: index, in: learned)
        guard order != learned else { return }
        languages.reorder(order)
        learned = languages.learned
        tabs = learned.compactMap { lang in tabs.first { $0.lang == lang } }
    }

    /// Stop learning `lang`, after its alert (#293): its tab goes, its
    /// progress stays, and the first tab shows (the picker with none left).
    func stop(_ lang: String, locale: Locale) async {
        languages.stop(lang)
        languages.chosen = languages.learned.first
        await load(locale: locale)
    }

    /// Today's counts, as Start's session would ask them: the words due,
    /// and the new words left (`NewWordPicker`: My words first, then the
    /// checked lists, those with a meaning in the pair); and the mistakes.
    /// Due and mistake words count only with a meaning in the pair, as the
    /// runs ask them, so Start and the mistakes row never open an empty
    /// run. Nothing to learn yet (no word in learning, no list of the
    /// language checked): the empty state, "Choose lists" when the language
    /// has lists, built-in or imported.
    /// Bumped by every home load. A load stages its results and commits them
    /// only while it is still the latest for the selected tab, so a slow load
    /// of a tab left behind never overwrites the one shown (#293).
    private var homeLoad = 0
    /// Bumped by every full load (`load(locale:)`), which alone reads the tabs.
    private var fullLoad = 0

    private func loadHome() async throws {
        guard let language else { return }
        homeLoad += 1
        let ticket = homeLoad
        // E5's row needs no word in learning (0132, #168).
        let drillLevel = language == ConjugationPlanner.lang
            ? DrillScope.tenseLevel(checked: settings.learningListIDs, stored: settings.learningDrillTenses)
            : nil
        let day = clock.today
        try await loadGoal(today: day)
        let lessonLeft = try await db.keptLesson(lang: language, today: day)?.items.count
        let pair = try await languages.pair(for: language)
        var pairPacks: [PackID] = []
        if let pair { pairPacks = await languages.packs.packs(of: pair) }
        // As the My words screen counts: one per word of the tab's language,
        // those waiting for a pack too (#245).
        let myWordsCount = try await db.myWordsEntries().filter { $0.item.key.lang == language }.count
        // The language's lists in the Lists screen's order; a built-in list
        // whose pack is missing is not among them (0237).
        let lists = WordListsViewModel.sections(try await db.wordLists(), learned: [language], uiLanguage: "")
            .flatMap(\.lists)
            .filter { $0.kind != .myWords }
        let checked = settings.learningListIDs
        let checkedLists = lists.filter { checked.contains($0.id) }
        let hasLists = languagesWithLists.contains(language) || !lists.isEmpty
        let listProgress = try await WordListsViewModel.progress(of: checkedLists, myWordsLanguage: language, db: db)
        // 0133, #172: the topics explained in the pair's via.
        let grammarTopicCount = try await db.grammarTopics(lang: language, explainLang: pair?.via ?? "eng").count
        let hasWordsInLearning = try await db.learningWordCount(lang: language) > 0
        var today: Today
        var mistakeCount = 0
        var canMatch = false
        if hasWordsInLearning || !checkedLists.isEmpty {
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
        } else {
            today = hasLists ? .chooseLists : .addWords
        }
        // A later load, or another tab, owns the screen now.
        guard ticket == homeLoad, self.language == language else { return }
        self.drillLevel = drillLevel
        self.lessonLeft = lessonLeft
        self.pair = pair
        self.pairPacks = pairPacks
        self.myWordsCount = myWordsCount
        self.checkedLists = checkedLists
        self.hasLists = hasLists
        self.listProgress = listProgress
        self.grammarTopicCount = grammarTopicCount
        self.today = today
        self.mistakeCount = mistakeCount
        self.canMatch = canMatch
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

    /// A pair tab's name, "Greek · via Russian" (#293): the language's name
    /// and `learn.viaLanguage`, joined by " · " (not translated); "Other" for
    /// a tab without a pair. In Arabic it starts with U+200F (#119).
    nonisolated static func pairTabName(_ tab: PairTab, locale: Locale) -> String {
        let name = languageName(tab.lang, locale: locale)
        guard let pair = tab.pair else { return name }
        let via = String(format: localized("learn.viaLanguage %@", locale: locale),
                         languageNameInSentence(pair.via, locale: locale))
        let text = name + " · " + via
        return (locale.language.characterDirection == .rightToLeft ? "\u{200F}" : "") + text
    }

    /// The small caption under the strip: the selected tab's full name; nil
    /// when no tab is selected (#293).
    nonisolated static func pairCaption(_ tabs: [PairTab], selected: String?, locale: Locale) -> String? {
        tabs.first { $0.lang == selected }.map { pairTabName($0, locale: locale) }
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
    /// What a wrong choice means (#299); nil for a right answer, a typed
    /// answer and "Don't know".
    var chosen: ChosenOption?
}

/// The option a wrong answer chose and what it stands for (#299).
struct ChosenOption: Equatable {
    /// The option's text.
    let text: String
    /// A meaning's word, or a word's meaning. Empty for a drill's form.
    let counterpart: String
    /// A drill form's cell, whose tense and person the line shows instead.
    var slot: ConjugationQuestion.Slot?
    /// The drill's "passive" note for `slot`.
    var showsVoice = false
}

/// What the example sheet shows (0134, #178): the result line, the word and
/// its examples. Kept as it was opened, so a closing sheet does not change
/// while the next question comes.
struct ExampleSheetContent: Equatable {
    let feedback: AnswerFeedback
    let word: WordChoice
    let examples: [ShownExample]
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
    /// 0134, #178: up to 3 examples of the question's word, each with its
    /// translation in the via (in a limited pair, else the meanings
    /// language); empty for a word without examples. Read before the
    /// question shows, so the bar never changes after it appears.
    @Published private(set) var sheetExamples: [ShownExample] = []
    /// The example sheet is up: after the first answer to a new word, or
    /// from the bar's Example button. A swipe down only clears it.
    @Published var showsExampleSheet = false
    /// What the sheet shows, kept until it opens again.
    @Published private(set) var exampleSheet: ExampleSheetContent?

    let run: Run
    /// The chosen language: a run never mixes languages.
    let lang: String
    /// Its pair's meanings language, which every meaning is in (English
    /// for Greek via Russian); nil without a pair (Other).
    let meaningsLang: String?
    /// `-learningAnswerHints`.
    let answerHints: Bool
    /// One per run: its log rows. A continued lesson (#296) takes its own,
    /// once, at start.
    private(set) var runID = UUID()

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    private let player: FeedbackPlayer
    /// The answers a continued lesson had before this sitting: the plan
    /// holds only its items left (#296).
    private var base = 0
    /// The session's lesson: the learning day it started (kept across 4 AM).
    private var lessonDay: LearnDay?
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
    /// Today's answers when the run started (#300: the end sound).
    private var answeredBefore = 0
    /// The pair's via, the language of the examples' translations; nil
    /// without a pair (Other).
    private var via: String?
    /// The examples of the run's words, read once per word.
    private var examples: [WordKey: [ExampleSentence]] = [:]
    /// The words whose first question of this run was new: only the first
    /// opens the sheet.
    private var introducedWords: Set<WordKey> = []

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
        answeredBefore = (try? await db.answeredCount(on: clock.today)) ?? 0
        do {
            let today = clock.today
            sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
            via = (try? await languages.pair(for: lang))?.via ?? meaningsLang
            try await loadWords()
            switch run {
            case let .trainer(kind):
                // The planner takes the first 10; new words only fill the room the due cards leave.
                let due = try await db.dueCards(lang: lang, today: today, kinds: [kind]).filter(hasMeaning)
                let newWords = try await startNewWords(today: today, limit: SessionPlanner.trainerLength - due.count)
                let practice = try await db.practiceCards(lang: lang, kind: kind, limit: .max).filter(hasMeaning)
                plan = SessionPlanner.trainer(kind: kind, due: due, newWords: newWords, practice: practice, today: today)
            case .session:
                lessonDay = today
                if let kept = try await db.keptLesson(lang: lang, today: today) {
                    try await resume(kept)
                } else {
                    let due = try await db.dueCards(lang: lang, today: today).filter(hasMeaning)
                    let newWords = try await startNewWords(today: today)
                    plan = SessionPlanner.session(due: due, newWords: newWords, today: today)
                    try await saveLesson()
                }
            case .mistakes:
                let cards = try await db.mistakeCards(since: SessionPlanner.mistakesSince(today: today), lang: lang)
                plan = SessionPlanner.mistakes(cards: cards.filter(hasMeaning))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await show()
    }

    /// Continue lesson (#296): the kept run, its answers and its items with
    /// their current states; a card that is gone or paused is dropped, as a
    /// skipped question is. The states are read first: if that fails, the
    /// run takes nothing of the lesson, so it shows the error, not a summary.
    private func resume(_ kept: KeptLesson) async throws {
        let states = try await db.cardStates(kept.items.map(\.card))
        runID = kept.runID
        base = kept.answered
        answered = kept.answered
        plan = kept.items.compactMap { item in
            guard let card = states[item.card], !card.isSuspended else { return nil }
            return PlannedItem(card: card, isRetry: item.isRetry)
        }
        if plan.count != kept.items.count { try await saveLesson() }
    }

    /// The plan's items as the lesson to keep; nil outside the session.
    private func lesson(items: ArraySlice<PlannedItem>, answered: Int) -> KeptLesson? {
        guard run == .session, let lessonDay else { return nil }
        return KeptLesson(lang: lang, day: lessonDay, runID: runID, answered: answered,
                          items: items.map { LessonItem(card: $0.card.key, isRetry: $0.isRetry) })
    }

    /// Start, or a skipped question: the items left, as they are.
    private func saveLesson() async throws {
        guard let lesson = lesson(items: plan[index...], answered: answered) else { return }
        try await db.saveLesson(lesson)
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

    /// Continue, on the bar or the example sheet: the next question, or the
    /// summary after the last.
    func next() async {
        guard feedback != nil else { return }
        showsExampleSheet = false
        await pendingWrite?.value
        index += 1
        await show()
    }

    /// The haptic of an answer; nil when Haptics is off.
    func haptic(for outcome: Outcome) -> SensoryFeedback? {
        player.haptic(for: outcome)
    }

    /// The bar's Example button (0134, #178): the sheet with the question's
    /// examples, once it is answered. Nothing for a word without examples.
    func showExamples() {
        guard let feedback, let question, !sheetExamples.isEmpty else { return }
        exampleSheet = ExampleSheetContent(feedback: feedback, word: question.word, examples: sheetExamples)
        showsExampleSheet = true
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
        showsExampleSheet = false
        typed = ""
        while index < plan.count {
            let card = plan[index].card
            if let word = words[card.key.word], let built = await build(card, word) {
                sheetExamples = await shownExamples(of: built.word.key)
                question = built
                position = base + index + 1
                total = base + plan.count
                shownAt = clock.now()
                phase = .question
                return
            }
            // Skipped: the cards around it may now be of one word.
            plan.remove(at: index)
            plan = SessionPlanner.separatingWords(plan, from: index)
            do { try await saveLesson() } catch { errorMessage = error.localizedDescription }
        }
        question = nil
        total = base + plan.count
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
            let progress = GoalProgress(answered: try await db.answeredCount(on: clock.today),
                                        goal: settings.learningDailyGoal)
            goalProgress = progress
            var isLesson = false
            if case .session = run { isLesson = true }
            player.playRunEnd(answeredBefore: answeredBefore, answeredAfter: progress.answered,
                              goal: progress.goal, isDailyLesson: isLesson)
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

    /// 0134, #178: the sheet's examples of `key`, read once per run and
    /// word: up to 3, those with a translation in the via first, each with
    /// its learning translation. None without a via or examples, or when
    /// the read fails: examples are extra.
    private func shownExamples(of key: WordKey) async -> [ShownExample] {
        guard let via else { return [] }
        let all: [ExampleSentence]
        if let cached = examples[key] {
            all = cached
        } else {
            all = (try? await db.examples(for: key, limit: 5)) ?? []
            examples[key] = all
        }
        return ExampleText.forLearning(all, via: via, limit: 3).map {
            ShownExample(sentence: $0, translation: ExampleText.learningTranslation(for: $0, via: via,
                                                                                    meanings: meaningsLang))
        }
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
        var chosenOption: ChosenOption?
        if !outcome.isRight, let chosen, question.options.indices.contains(chosen) {
            let option = question.options[chosen]
            chosenOption = ChosenOption(text: option.text, counterpart: option.counterpart)
        }
        feedback = AnswerFeedback(outcome: outcome, chosenIndex: chosen, mindTheAccent: mindTheAccent,
                                  rightAnswer: question.rightAnswer, chosen: chosenOption)
        player.play(outcome)
        // 0134, #178: a new word's first question opens its examples.
        if question.isNew, introducedWords.insert(question.word.key).inserted {
            showExamples()
        }
        let durationMs = min(max(Int(clock.now().timeIntervalSince(shownAt) * 1000), 0), ReviewSummary.durationCapMs)
        answered += 1
        let record = AnswerRecord(card: question.card.key, exercise: question.exercise, mode: run.mode,
                                  runID: runID, outcome: outcome, durationMs: durationMs)
        let at = index
        // #296: the items left after this answer, as the plan will hold them.
        var left = plan
        if !outcome.isRight {
            let next = FixedLadder().next(question.card, outcome: outcome, today: today)
            left = SessionPlanner.separatingWords(SessionPlanner.requeue(plan, wrongAt: at, card: next), from: at + 1)
        }
        let kept = lesson(items: left[(at + 1)...], answered: answered)
        let write = Task { await self.write(record, today: today, wrongAt: outcome.isRight ? nil : at, lesson: kept) }
        pendingWrite = write
        await write.value
    }

    /// Writes the answer with the daily goal in force (E10's `learn_day`),
    /// and requeues a wrong card at the end, apart from its word's other card.
    private func write(_ record: AnswerRecord, today: LearnDay, wrongAt index: Int?, lesson: KeptLesson?) async {
        do {
            let card = try await db.recordAnswer(record, today: today, goal: settings.learningDailyGoal, lesson: lesson)
            await reminder?.answerRecorded(today: today)
            if let index {
                plan = SessionPlanner.separatingWords(SessionPlanner.requeue(plan, wrongAt: index, card: card),
                                                      from: index + 1)
                total = base + plan.count
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Conjugation drill (0132, #168)

/// The Conjugation screen (0132, "Screens"): the checked Greek lists' verbs,
/// "Tenses up to", the tenses of that level with their accuracy over the
/// last 30 days, and Start. Without a usable Greek pack it offers the
/// download; without a checked Greek list, "Choose lists". The pool is read
/// once per set of checked lists while the screen is open; "Tenses up to"
/// recounts the same pool.
@MainActor
final class ConjugationDrillViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// No usable Greek pack (0237): "Download Greek to practise conjugation."
        case needsGreek
        /// No built-in Greek list checked: "Choose lists".
        case noLists
        case ready
    }

    @Published private(set) var state = State.loading
    /// The checked built-in Greek lists, in level order.
    @Published private(set) var lists: [WordListID] = []
    /// The pool's verbs with a question at the tense level.
    @Published private(set) var verbCount = 0
    /// "Tenses up to": the stored value, never below the highest checked list.
    @Published private(set) var level = DrillLevel.a1
    /// The segments: the highest checked list's level up to B2.
    @Published private(set) var offeredLevels: [DrillLevel] = []
    /// The last 30 days, both voices of a tense together.
    @Published private(set) var accuracy: [ConjugationTense: Tally] = [:]
    @Published var errorMessage: String?

    /// The checked lists' verbs, in pool order (list, then frequency).
    private(set) var pool: [DrillVerb] = []
    /// The meanings language of Greek's pair: the verbs' translations.
    private(set) var meaningsLang = "eng"
    /// The lists `pool` was read for (with `meaningsLang`).
    private var poolLists: [WordListID]?

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    private let isGreekUsable: () async -> Bool
    private let installGreek: () async throws -> Void

    /// `isGreekUsable` and `installGreek`: 0237's `PackService.installedPacks()`
    /// and `install(.ell)` unless a test passes its own.
    init(db: DatabaseService = .shared, settings: SettingsService = .shared, languages: LearningLanguageService? = nil,
         clock: LearningClock = LearningClock(), isGreekUsable: (() async -> Bool)? = nil,
         installGreek: (() async throws -> Void)? = nil) {
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        self.isGreekUsable = isGreekUsable ?? {
            await PackService.shared.installedPacks().contains { $0.id == .ell && $0.usable }
        }
        self.installGreek = installGreek ?? { try await PackService.shared.install(.ell) }
    }

    /// The tenses of the level, in the tables' order.
    var tenses: [ConjugationTense] { level.tenses }

    /// Reads the pack, the checked lists (again on every appearance, so a
    /// list checked on New words from shows at once), the pool when they or
    /// the meanings language changed, the level and the accuracy.
    func load() async {
        do {
            guard await isGreekUsable() else {
                state = .needsGreek
                pool = []
                poolLists = nil
                return
            }
            let checked = settings.learningListIDs
            let greek = DrillScope.greekLists(checked: checked)
            lists = greek
            guard !greek.isEmpty else {
                state = .noLists
                return
            }
            // The verbs' translations are in the meanings language of
            // Greek's pair, which Settings can change while the screen is open.
            let lang = try await languages.pair(for: ConjugationPlanner.lang)?.meaningsLang ?? "eng"
            if poolLists != greek || lang != meaningsLang {
                // The language is kept only once the read succeeded, so a failed
                // read is tried again on the next load.
                pool = try await db.drillVerbs(lists: greek, meaningsLang: lang)
                meaningsLang = lang
                poolLists = greek
            }
            offeredLevels = DrillScope.offeredLevels(checked: checked)
            level = DrillScope.tenseLevel(checked: checked, stored: settings.learningDrillTenses)
            recount()
            let since = DailySeries.start(today: clock.today)
            accuracy = Self.byTense(try await db.tenseAccuracy(since: since, lang: ConjugationPlanner.lang))
            state = .ready
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "Tenses up to": remembered (`learning_drill_tenses`), and the same
    /// pool recounted.
    func setLevel(_ level: DrillLevel) {
        guard offeredLevels.contains(level), level != self.level else { return }
        settings.learningDrillTenses = level
        self.level = level
        recount()
    }

    /// Download: installs the Greek pack (0237), whose progress
    /// `PackStatusModel` shows, then reads the screen again.
    func download() async {
        do {
            try await installGreek()
        } catch {
            // The pack's row state shows why (`PackState.failed`).
        }
        await load()
    }

    private func recount() {
        verbCount = pool.filter { ConjugationQuestionBuilder.hasQuestion(verb: $0, level: level) }.count
    }

    /// E10's tallies by tense raw value, by `ConjugationTense`.
    nonisolated static func byTense(_ tallies: [String: Tally]) -> [ConjugationTense: Tally] {
        var result: [ConjugationTense: Tally] = [:]
        for (tense, tally) in tallies {
            if let tense = ConjugationTense(rawValue: tense) { result[tense] = tally }
        }
        return result
    }
}

/// Runs a conjugation drill (0132, "Screens"): the session of the checked
/// lists' verbs, or Practise on one verb. It plans with `ConjugationPlanner`
/// over Greek's conjugation cards and E10's tense accuracy, builds each
/// question just before it shows with the run's generator, writes each
/// answer at once with `recordAnswer` (so closing keeps what was answered)
/// and applies the retry with the run's real length. Its summary is E4's
/// over the run's log rows, with the run by tense.
@MainActor
final class ConjugationRunViewModel: ObservableObject {
    enum Mode {
        /// The drill: the checked lists' verbs at the tense level.
        case session(pool: [DrillVerb], level: DrillLevel)
        /// Practise on one verb, from `level` up to its first level with a question.
        case verb(DrillVerb, level: DrillLevel)
        /// Practise on a grammar topic (0133, #172): the drill of `pool` at
        /// `level`, asking only `tenses`, each in the verb's main voice.
        case tenses(Set<ConjugationTense>, pool: [DrillVerb], level: DrillLevel)
    }

    typealias Phase = ExerciseRunViewModel.Phase

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var question: ConjugationQuestion?
    /// Set the moment an answer is graded; nil while a question waits.
    @Published private(set) var feedback: AnswerFeedback?
    /// The question shown, from 1, and the plan's length.
    @Published private(set) var position = 0
    @Published private(set) var total = 0
    /// Answers so far: the progress bar's value.
    @Published private(set) var answered = 0
    /// The summary's numbers, from this run's log rows; nil until the end.
    @Published private(set) var summary: ReviewSummary?
    /// This run by tense, in the tables' order: "Aorist · 4 of 5".
    @Published private(set) var tenseScores: [(tense: String, tally: Tally)] = []
    /// The daily goal at the end of the run; nil until then.
    @Published private(set) var goalProgress: GoalProgress?
    /// 0133, #174: the grammar topic of the question's tense for its verb,
    /// which Rule opens after the answer; nil for a tense without a topic.
    /// A passive facet has one only for a verb with passive forms only.
    @Published private(set) var ruleTopic: GrammarTopicSummary?
    @Published var errorMessage: String?

    let mode: Mode
    /// The meanings language of Greek's pair: the translation's voice.
    let meaningsLang: String
    /// Questions in the run: 15, or `-drillLength`.
    let length: Int
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
    private(set) var plan: [DrillItem] = []
    private var index = 0
    private var shownAt = Date()
    private var pendingWrite: Task<Void, Never>?
    private var isStarted = false
    private var answeredBefore = 0
    /// Greek's grammar topics and links, read once per run (#174).
    private var grammarTopics: [GrammarTopicSummary] = []
    private var grammarLinks: [GrammarLink] = []

    init(mode: Mode, meaningsLang: String = "eng", db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil, clock: LearningClock = LearningClock(),
         player: FeedbackPlayer? = nil, reminder: LearningReminder? = nil,
         seed: UInt64? = LearningLaunchOptions.seed, answerHints: Bool = LearningLaunchOptions.answerHints,
         length: Int? = LearningLaunchOptions.drillLength) {
        self.mode = mode
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
        self.length = max(length ?? ConjugationPlanner.length, 1)
    }

    /// Plans the run and shows its first question.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        answeredBefore = (try? await db.answeredCount(on: clock.today)) ?? 0
        do {
            let today = clock.today
            let cards = try await db.cards(lang: ConjugationPlanner.lang, kinds: [.conjugation])
            let accuracy = ConjugationDrillViewModel.byTense(
                try await db.tenseAccuracy(since: DailySeries.start(today: today), lang: ConjugationPlanner.lang))
            switch mode {
            case let .session(pool, level):
                plan = ConjugationPlanner.session(pool: pool, level: level, cards: cards, accuracy: accuracy,
                                                  today: today, length: length, rng: &rng)
            case let .verb(verb, level):
                plan = ConjugationPlanner.verbRun(verb: verb, level: level, cards: cards, accuracy: accuracy,
                                                  today: today, length: length, rng: &rng)
            case let .tenses(tenses, pool, level):
                plan = ConjugationPlanner.session(pool: pool, level: level, tenses: tenses, cards: cards,
                                                  accuracy: accuracy, today: today, length: length, rng: &rng)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadGrammar()
        await show()
    }

    /// Greek's grammar links and topics, titled in its explanation
    /// language, for each question's Rule (0133, #174). Grammar is extra: a
    /// failed read, or no Greek pack, leaves the run without Rule.
    private func loadGrammar() async {
        let lang = ConjugationPlanner.lang
        do {
            let links = try await db.grammarLinks(lang: lang)
            guard !links.isEmpty else { return }
            grammarTopics = try await db.grammarTopics(lang: lang,
                                                       explainLang: try await languages.explanationLanguage(of: lang))
            grammarLinks = links
        } catch {
            grammarTopics = []
            grammarLinks = []
        }
    }

    /// Grades the option tapped at once (the feedback bar, the sound; the
    /// view plays the haptic), then writes the answer on the learning day of
    /// this moment. A wrong answer comes back once (`afterWrong`, with this
    /// run's length): in a full run in place of a later new or practice
    /// item, in a shorter one at the end.
    func choose(_ option: Int) async {
        guard feedback == nil, let question, question.options.indices.contains(option),
              plan.indices.contains(index) else { return }
        let outcome: Outcome = option == question.rightIndex ? .right : .wrong
        let today = clock.today
        var chosenOption: ChosenOption?
        if !outcome.isRight, question.optionSlots.indices.contains(option) {
            let slot = question.optionSlots[option]
            chosenOption = ChosenOption(text: question.options[option], counterpart: "", slot: slot,
                                        showsVoice: question.showsVoice(of: slot))
        }
        feedback = AnswerFeedback(outcome: outcome, chosenIndex: option, mindTheAccent: false,
                                  rightAnswer: question.options[question.rightIndex], chosen: chosenOption)
        player.play(outcome)
        answered += 1
        let seconds = min(max(clock.now().timeIntervalSince(shownAt), 0), 3_600)
        let record = plan[index].answer(outcome, runID: runID, durationMs: Int(seconds * 1000))
        if !outcome.isRight {
            plan = ConjugationPlanner.afterWrong(plan, at: index, length: length, rng: &rng)
            total = plan.count
        }
        let write = Task { await self.write(record, today: today) }
        pendingWrite = write
        await write.value
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

    /// Builds and shows the question of `plan[index]`, skipping an item that
    /// builds none (not expected: the planner only plans questions); after
    /// the last, the summary.
    private func show() async {
        question = nil
        feedback = nil
        ruleTopic = nil
        while index < plan.count {
            if let built = plan[index].question(rng: &rng) {
                question = built
                ruleTopic = GrammarLinks.ruleTopic(verb: built.verb, facet: built.facet, topics: grammarTopics,
                                                   links: grammarLinks)
                position = index + 1
                total = plan.count
                shownAt = clock.now()
                phase = .question
                return
            }
            plan.remove(at: index)
        }
        total = plan.count
        guard answered > 0 else {
            phase = .empty
            return
        }
        await loadSummary()
        phase = .summary
    }

    /// E4's summary from this run's log rows, the run by tense
    /// (`Accuracy.byTense`) and the daily goal.
    private func loadSummary() async {
        do {
            let rows = try await db.reviewRows(run: runID)
            summary = ReviewSummary.of(rows)
            tenseScores = ConjugationTense.ordered(Accuracy.byTense(Accuracy.byFacet(rows)))
            let progress = GoalProgress(answered: try await db.answeredCount(on: clock.today),
                                        goal: settings.learningDailyGoal)
            goalProgress = progress
            player.playRunEnd(answeredBefore: answeredBefore, answeredAfter: progress.answered,
                              goal: progress.goal, isDailyLesson: false)
        } catch {
            summary = summary ?? ReviewSummary()
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the answer with the daily goal in force (E10's `learn_day`),
    /// then lets the reminder cancel today's when the goal is reached.
    private func write(_ record: AnswerRecord, today: LearnDay) async {
        do {
            try await db.recordAnswer(record, today: today, goal: settings.learningDailyGoal)
            await reminder?.answerRecorded(today: today)
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
    /// The words of the last wrong pair, by index into the round's words,
    /// until the next tap (#299).
    @Published private(set) var mismatch: (word: Int, meaning: Int)?
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
    private var answeredBefore = 0

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

    /// The two words of the last wrong pair with their own meanings: the
    /// word tapped in the word column, then the word whose meaning was
    /// tapped (#299).
    var mismatchPairs: [(term: String, meaning: String)] {
        guard let round, let mismatch else { return [] }
        return [mismatch.word, mismatch.meaning].map { (round.words[$0].term, round.words[$0].meaning) }
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
            mismatch = nil
        case let .mismatched(word, meaning):
            flashing = Set([round.tiles(of: word)?.word, round.tiles(of: meaning)?.meaning].compactMap { $0 })
            mismatch = (word, meaning)
            give(.wrong)
            let id = feedbackCount
            Task {
                try? await Task.sleep(for: Self.flashDuration)
                if self.feedbackCount == id { self.flashing = [] }
            }
        case let .matched(word):
            flashing = []
            mismatch = nil
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
            if round.isComplete, let after = try? await db.answeredCount(on: today) {
                player.playRunEnd(answeredBefore: answeredBefore, answeredAfter: after,
                                  goal: settings.learningDailyGoal, isDailyLesson: false)
            }
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
        mismatch = nil
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
            answeredBefore = (try? await db.answeredCount(on: today)) ?? 0
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
        player.play(outcome.isRight ? .pairRight : .pairWrong)
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

    /// The tab's language, whose numbers the screen shows (#295); nil while
    /// none is learned.
    let language: String?
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

    init(lang: String?, db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil, clock: LearningClock = LearningClock()) {
        language = lang
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        today = clock.today
    }

    /// Every block.
    func load() async {
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

// MARK: - Grammar (0133, #172)

extension LearningLanguageService {
    /// The language `lang`'s topics are explained in: the via of its pair,
    /// its stored via or else its default (0131), whatever the UI language;
    /// English for a language without a pair.
    func explanationLanguage(of lang: String) async throws -> String {
        try await pair(for: lang)?.via ?? "eng"
    }
}

/// The Grammar screen (0133, "Grammar screen"): `lang`'s topics by level,
/// lowest first, each titled in the explanation language, with the note
/// "Topics are explained in English." when a topic has no text in it.
@MainActor
final class GrammarTopicsViewModel: ObservableObject {
    /// One section: a level's topics in their order.
    struct Level: Identifiable, Equatable {
        let level: String
        let topics: [GrammarTopicSummary]
        var id: String { level }
    }

    /// How the screen lays the levels out (0133, #297).
    struct Layout: Equatable {
        /// A header per level: two or more levels have topics.
        let headers: Bool
        let count: Int
        /// The subtitle's level ("17 topics · A1"): only while one level has topics.
        let level: String?
        /// The next level, for the "A2 · Coming soon" row: only while one
        /// level has topics, and never after C2.
        let comingSoon: String?
    }

    /// While only one level has topics (A1 in 2.0): no headers, the level in
    /// the subtitle and the next level as "Coming soon". With two or more:
    /// a header per level, the count alone, no "Coming soon".
    nonisolated static func layout(levels: [Level]) -> Layout {
        let count = levels.reduce(0) { $0 + $1.topics.count }
        guard levels.count == 1, let only = levels.first?.level else {
            return Layout(headers: levels.count > 1, count: count, level: nil, comingSoon: nil)
        }
        let all = WordListsViewModel.cefrLevels
        let next = all.firstIndex(of: only).flatMap { $0 + 1 < all.count ? all[$0 + 1] : nil }
        return Layout(headers: false, count: count, level: only, comingSoon: next)
    }

    /// "17 topics · A1", or "40 topics" (#297).
    nonisolated static func subtitle(_ layout: Layout, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        let count = String(localized: "grammar.topicCount \(layout.count)", bundle: bundle, locale: locale)
        guard let level = layout.level else { return count }
        return count + " · " + WordListsViewModel.levelName(level, locale: locale)
    }

    /// The "A2 · Coming soon" row's text (#297).
    nonisolated static func comingSoonText(_ level: String, locale: Locale) -> String {
        WordListsViewModel.levelName(level, locale: locale) + " · "
            + WordListsViewModel.localized("grammar.comingSoon", locale: locale)
    }

    /// The same row as VoiceOver reads it: "A2, Coming soon".
    nonisolated static func comingSoonLabel(_ level: String, locale: Locale) -> String {
        WordListsViewModel.levelName(level, locale: locale) + ", "
            + WordListsViewModel.localized("grammar.comingSoon", locale: locale)
    }

    @Published private(set) var levels: [Level] = []
    /// A topic's title fell back from the explanation language to English.
    @Published private(set) var showsEnglishNote = false
    /// The language the titles were asked in.
    @Published private(set) var explainLang = "eng"
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?

    let lang: String
    private let db: DatabaseService
    private let languages: LearningLanguageService

    init(lang: String, db: DatabaseService = .shared, languages: LearningLanguageService? = nil) {
        self.lang = lang
        self.db = db
        self.languages = languages ?? .shared
    }

    func load() async {
        do {
            explainLang = try await languages.explanationLanguage(of: lang)
            let topics = try await db.grammarTopics(lang: lang, explainLang: explainLang)
            var levels: [Level] = []
            for topic in topics {
                if let last = levels.last, last.level == topic.level {
                    levels[levels.count - 1] = Level(level: last.level, topics: last.topics + [topic])
                } else {
                    levels.append(Level(level: topic.level, topics: [topic]))
                }
            }
            self.levels = levels
            showsEnglishNote = topics.contains { $0.explainLang != explainLang }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }
}

/// A grammar topic (0133, "Topic screen"): its text in the explanation
/// language (the English note above the title when it fell back to English,
/// however the topic opens), its blocks, its words with their meanings in
/// the meanings language of the pair, its related topics, and Practise for
/// a topic about verb tenses.
@MainActor
final class GrammarTopicViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// The topic is gone, its pack removed: `grammar.unavailable`.
        case unavailable
        case ready
    }

    /// A Words row: the word, its short meaning ("" when none), and the
    /// entry it opens (nil when no dictionary of the language has it).
    struct WordRow: Identifiable, Equatable {
        let word: String
        let meaning: String
        let entry: DictionaryEntry?
        var id: String { word }
    }

    /// A drill of the topic's tenses, presented as E5's run
    /// (`ConjugationRunViewModel.Mode.tenses`): the pool of the checked
    /// Greek lists (or Greek A1), its level, and the meanings language of
    /// Greek's pair (the verbs' translations).
    struct PractiseRun: Identifiable {
        let id = UUID()
        let tenses: Set<ConjugationTense>
        let lists: [WordListID]
        let pool: [DrillVerb]
        let level: DrillLevel
        let meaningsLang: String
    }

    @Published private(set) var state = State.loading
    @Published private(set) var topic: GrammarTopic?
    @Published private(set) var blocks: [GrammarBlock] = []
    /// The text fell back from the explanation language to English.
    @Published private(set) var showsEnglishNote = false
    @Published private(set) var words: [WordRow] = []
    /// The meanings language of the pair: the Words rows' meanings, read in
    /// its voice.
    @Published private(set) var meaningsLang: String?
    /// The tenses Practise drills and names, in the topic's order: those
    /// with a question at the run's level. Empty: no Practise.
    @Published private(set) var practiseTenses: [ConjugationTense] = []
    /// "Learn Greek via English?" (Greek's pair), asked by Practise while
    /// Greek is not learned; nil when not shown.
    @Published var practiseQuestion: LearningPair?
    /// "No Greek list is checked. Practise the verbs of Greek A1, or choose
    /// lists?" (0133, Open question 1).
    @Published var asksForLists = false
    /// "Choose lists": New words from is pushed.
    @Published var showsNewWordsFrom = false
    /// The drill to present; nil when none.
    @Published var practiseRun: PractiseRun?
    @Published var errorMessage: String?
    /// False in the drill's Rule sheet (`\.allowsPractise`, #174): the topic
    /// has no Practise.
    var allowsPractise = true

    let id: String
    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService

    init(id: String, db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil) {
        self.id = id
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
    }

    /// The taught language, from the id (`ell-aorist-regular`).
    var lang: String { String(id.prefix { $0 != "-" }) }

    /// The title, its Greek in the Greek voice.
    var title: AttributedString {
        GrammarDocument.taggingGreek(AttributedString(topic?.summary.title ?? ""))
    }

    /// Reads the topic in the explanation language, then its words.
    func load() async {
        do {
            let pair = try await languages.pair(for: lang)
            let explainLang = pair?.via ?? "eng"
            guard let topic = try await db.grammarTopic(id: id, explainLang: explainLang) else {
                state = .unavailable
                return
            }
            self.topic = topic
            blocks = GrammarDocument.parse(body: topic.body)
            showsEnglishNote = topic.summary.explainLang != explainLang
            practiseTenses = allowsPractise ? DrillScope.askedTenses(topic.tenses, level: practiseLevel(topic)) : []
            state = .ready
            meaningsLang = pair?.meaningsLang
            words = try await wordRows(topic.words, meaningsLang: pair?.meaningsLang)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Each word with its short meaning in `meaningsLang` and its entry in
    /// the language's dictionaries, Dictionary Order first, enabled first,
    /// as a list word opens (E3).
    private func wordRows(_ words: [String], meaningsLang: String?) async throws -> [WordRow] {
        guard !words.isEmpty else { return [] }
        let sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
        let queries = words.map { MeaningQuery(key: WordKey(lang: lang, word: $0), lookup: $0) }
        let meanings = try await db.meanings(of: queries, lang: lang, meaningsLang: meaningsLang,
                                             sourceOrder: sourceOrder)
        var rows: [WordRow] = []
        for query in queries {
            let entry = try await db.entry(headword: query.lookup, lang: lang, sourceOrder: sourceOrder)
            rows.append(WordRow(word: query.lookup, meaning: meanings[query.key] ?? "", entry: entry))
        }
        return rows
    }

    /// "Tenses up to" (or the checked lists' floor), raised to the first
    /// level with one of the topic's tenses.
    private func practiseLevel(_ topic: GrammarTopic) -> DrillLevel {
        let stored = DrillScope.tenseLevel(checked: settings.learningListIDs, stored: settings.learningDrillTenses)
        return DrillScope.tenseRunLevel(Set(topic.tenses), from: stored)
    }

    // MARK: Practise

    /// Practise: E4's "Learn Greek via English?" first while Greek is not
    /// learned; then, with no built-in Greek list checked, the Greek A1
    /// question; then the drill of the topic's tenses.
    func practise() async {
        guard allowsPractise, !practiseTenses.isEmpty else { return }
        guard languages.isLearned(ConjugationPlanner.lang) else {
            do {
                practiseQuestion = try await languages.pair(for: ConjugationPlanner.lang)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        await startOrAskForLists()
    }

    /// The answer to `practiseQuestion`: Yes learns Greek through that pair,
    /// then goes on; No cancels, and nothing changes.
    func answerPractise(yes: Bool) async {
        practiseQuestion = nil
        guard yes else { return }
        do {
            try await languages.learn(language: ConjugationPlanner.lang)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await startOrAskForLists()
    }

    /// "Greek A1": the drill on Greek A1's verbs; the checked lists stay as
    /// they are.
    func practiseGreekA1() async {
        asksForLists = false
        await start(lists: [DrillScope.greekA1])
    }

    /// "Choose lists": opens New words from and starts nothing.
    func chooseLists() {
        asksForLists = false
        showsNewWordsFrom = true
    }

    private func startOrAskForLists() async {
        let lists = DrillScope.greekLists(checked: settings.learningListIDs)
        guard !lists.isEmpty else {
            asksForLists = true
            return
        }
        await start(lists: lists)
    }

    /// The run of the topic's tenses over the lists' verbs. Nothing is
    /// stored here: the run writes E5's cards and log rows.
    private func start(lists: [WordListID]) async {
        guard let topic else { return }
        let level = practiseLevel(topic)
        let tenses = Set(DrillScope.askedTenses(topic.tenses, level: level))
        guard !tenses.isEmpty else { return }
        do {
            let meaningsLang = try await languages.pair(for: ConjugationPlanner.lang)?.meaningsLang ?? "eng"
            let pool = try await db.drillVerbs(lists: lists, meaningsLang: meaningsLang)
            practiseRun = PractiseRun(tenses: tenses, lists: lists, pool: pool, level: level,
                                      meaningsLang: meaningsLang)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Texts

    /// "Practise · Aorist": E5's `drill.practise` and the tense terms,
    /// joined with " · " (not translated); right to left in Arabic.
    nonisolated static func practiseTitle(_ tenses: [ConjugationTense], locale: Locale) -> String {
        let parts = [SettingsViewModel.localizedString("drill.practise", locale: locale)]
            + tenses.map { $0.title(locale: locale) }
        let mark = locale.language.characterDirection == .rightToLeft ? "\u{200F}" : ""
        return mark + parts.joined(separator: " · ")
    }

    /// "No Greek list is checked. …", with the list's name "Greek A1".
    nonisolated static func greekA1Title(locale: Locale) -> String {
        let list = WordList(id: DrillScope.greekA1, kind: .builtIn, lang: ConjugationPlanner.lang, level: "A1",
                            title: "", count: 0)
        return WordListsViewModel.title(of: list, locale: locale)
    }
}
