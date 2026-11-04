// Learning.swift
// Learning words with spaced repetition (0131-learning.md): the pure models.
// Days, cards, the fixed ladder, word stages, the learned languages and
// their pairs (#157). SQL stays in `DatabaseService`.

import Foundation

// MARK: - Days

/// A learning day, `YYYY-MM-DD` in the Gregorian calendar, so days compare as
/// text. A day starts at 4 AM local time (`LearningClock`); a log row keeps
/// the day it was written in.
struct LearnDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    let rawValue: String

    /// Days are computed in UTC, where every day has 24 hours.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(year: Int, month: Int, day: Int) {
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// A stored day; nil when `rawValue` is no `YYYY-MM-DD` date.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3,
              let date = Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let day = LearnDay(date: date, calendar: Self.calendar)
        guard day.rawValue == rawValue else { return nil }
        self = day
    }

    /// The local day of `date` in `calendar`, midnight to midnight.
    init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    func adding(days: Int) -> LearnDay {
        let parts = rawValue.split(separator: "-").map { Int($0)! }
        let date = Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        return LearnDay(date: Self.calendar.date(byAdding: .day, value: days, to: date)!, calendar: Self.calendar)
    }

    static func < (lhs: LearnDay, rhs: LearnDay) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }
}

// MARK: - Cards

/// A card's direction. Every word has a recognition and a production card;
/// E5 adds conjugation cards.
enum CardKind: String, CaseIterable, Sendable {
    case recognition, production, conjugation

    /// The two cards of a word, which E4's planners pick.
    static let wordKinds: [CardKind] = [.recognition, .production]
}

struct CardKey: Hashable, Sendable {
    let word: WordKey
    let kind: CardKind
    /// `""` for word cards; E5: `<tense>.<voice>`.
    var facet = ""
}

/// One `learn_card` row.
struct CardState: Hashable, Sendable {
    let key: CardKey
    /// 0 learning, 1…6 the ladder's rungs (`FixedLadder.intervals`).
    var step: Int
    var dueDay: LearnDay
    /// The day of its last answer; nil = never answered (new).
    var lastDay: LearnDay?
    /// Paused by Stop learning, with its progress.
    var isSuspended = false

    var isNew: Bool { lastDay == nil }
}

/// How an answer was graded. `accent` (lenient mode) counts as right.
enum Outcome: String, CaseIterable, Sendable {
    case right, accent, wrong

    var isRight: Bool { self != .wrong }
}

/// The exercise an answer came from (`learn_review.exercise`).
enum ExerciseKind: String, CaseIterable, Sendable {
    case recognition
    case productionChoice = "production_choice"
    case productionTyped = "production_typed"
    case match
    case conjugation
}

/// The run an answer came from (`learn_review.mode`).
enum RunMode: String, CaseIterable, Sendable {
    case session, trainer, mistakes, drill
}

/// One answer, as `DatabaseService.recordAnswer` logs it.
struct AnswerRecord: Hashable, Sendable {
    let card: CardKey
    let exercise: ExerciseKind
    let mode: RunMode
    /// One per run: the summary's rows.
    let runID: UUID
    let outcome: Outcome
    /// Question shown → answer.
    var durationMs = 0
    /// Per exercise; E5: the person asked.
    var detail: String?
}

/// Typed answers (`learning_answer_mode`): strict accents, lenient, or
/// multiple choice only.
enum AnswerMode: String, CaseIterable, Sendable {
    case strict, lenient, choice
}

// MARK: - Words

/// One `learn_word` row: a word in learning and what its questions show.
struct LearnWord: Hashable, Sendable {
    let key: WordKey
    /// Shown and expected: the list's term, or the headword.
    let term: String
    let endings: String
    let partOfSpeech: String
    /// The list's; `""` = the meaning comes from the pair's dictionary.
    let translation: String
    /// The language of `translation` (ISO 639-3, `eng` for Kirill's lists);
    /// `""` = an import's, shown in every pair.
    let translationLang: String
    /// nil for a list word without a dictionary entry.
    let entry: EntryKey?
    /// The E3 list it was picked from (a `WordListID` raw value); nil for My words.
    let listID: String?
    /// The local day of its first answer; nil = not started.
    let introducedDay: LearnDay?
}

/// A word in learning with every card of its key, paused ones included.
struct WordLearningState: Hashable, Sendable {
    let word: LearnWord
    let cards: [CardState]

    /// Its recognition and production cards.
    var wordCards: [CardState] { cards.filter { CardKind.wordKinds.contains($0.key.kind) } }

    /// Stop learning paused it: every word card is suspended.
    var isPaused: Bool { !wordCards.isEmpty && wordCards.allSatisfy(\.isSuspended) }
}

// MARK: - Scheduling

/// Schedules a card from its answers. `FixedLadder` is the only one; FSRS
/// could replace it later.
protocol Scheduler: Sendable {
    func next(_ card: CardState, outcome: Outcome, today: LearnDay) -> CardState
    func isLearned(_ card: CardState) -> Bool
}

/// Fixed intervals of 1, 3, 7, 14, 30 and 90 days.
struct FixedLadder: Scheduler {
    /// The interval of rung `step`, from 1.
    static let intervals = [1, 3, 7, 14, 30, 90]
    /// A card is learned from this interval on.
    static let learnedInterval = 30
    static var topStep: Int { intervals.count }

    /// The interval of `step` in days; nil for 0 (learning).
    static func interval(ofStep step: Int) -> Int? {
        (1...topStep).contains(step) ? intervals[step - 1] : nil
    }

    /// Wrong, due or not: back to learning, due today. Right or accent on a
    /// card that is due, learning or new: one rung up. Right on a card not
    /// due: unchanged. Every answer sets `lastDay`.
    func next(_ card: CardState, outcome: Outcome, today: LearnDay) -> CardState {
        var next = card
        next.lastDay = today
        if !outcome.isRight {
            next.step = 0
            next.dueDay = today
        } else if card.step == 0 || card.dueDay <= today {
            next.step = min(card.step + 1, Self.topStep)
            next.dueDay = today.adding(days: Self.intervals[next.step - 1])
        }
        return next
    }

    func isLearned(_ card: CardState) -> Bool {
        (Self.interval(ofStep: card.step) ?? 0) >= Self.learnedInterval
    }
}

/// What a card shows: New, Learning, Every 1 / 3 / 7 / 14 days, Learned.
enum CardStage: Hashable, Sendable {
    case new, learning, every(days: Int), learned
}

/// The stage of each word card and of the word, for My words, the Learn
/// button and E10.
struct WordStatus: Hashable, Sendable {
    enum Stage: Hashable, Sendable {
        /// No word card answered yet.
        case new
        case learning
        /// Both word cards at 30 days or more.
        case learned
    }

    let cards: [CardKind: CardStage]
    let stage: Stage
    let isPaused: Bool

    init(_ state: WordLearningState) {
        let ladder = FixedLadder()
        let wordCards = state.wordCards
        cards = Dictionary(wordCards.map { ($0.key.kind, Self.stage(of: $0)) }, uniquingKeysWith: { a, _ in a })
        if wordCards.allSatisfy(\.isNew) {
            stage = .new
        } else if Set(wordCards.map(\.key.kind)) == Set(CardKind.wordKinds), wordCards.allSatisfy(ladder.isLearned) {
            stage = .learned
        } else {
            stage = .learning
        }
        isPaused = state.isPaused
    }

    static func stage(of card: CardState) -> CardStage {
        if card.isNew { return .new }
        if FixedLadder().isLearned(card) { return .learned }
        guard let days = FixedLadder.interval(ofStep: card.step) else { return .learning }
        return .every(days: days)
    }
}

// MARK: - Languages and pairs

/// The learned languages (`learning_languages`).
enum LearningLanguages {
    /// The language the Learn home shows: the stored one when learned, else
    /// the first learned, nil when none.
    static func chosen(stored: String?, learned: [String]) -> String? {
        if let stored, learned.contains(stored) { return stored }
        return learned.first
    }
}

/// A language learned through another one, its via (0131, "Languages and
/// pairs"): Greek via English is (`ell`, `eng`). A pair exists when a
/// dictionary goes from `lang` into `via`, or it is limited. Cards belong to
/// `lang` alone; the pair decides what is shown and downloaded.
struct LearningPair: Hashable, Sendable {
    let lang: String
    /// The language of explanations (grammar, tips).
    let via: String
    /// The language of meanings and list translations: `via`, except in a
    /// limited pair.
    let meaningsLang: String

    init(lang: String, via: String, meaningsLang: String? = nil) {
        self.lang = lang
        self.via = via
        self.meaningsLang = meaningsLang ?? via
    }

    /// Offered without a dictionary from `lang` into `via` (Kirill,
    /// 2026-11-04): explanations in `via`, meanings in `meaningsLang`. The
    /// picker warns about it.
    var isLimited: Bool { meaningsLang != via }
}

/// The pairs the data offers and the via of each learned language
/// (`learning_via`). Pure: the offered pairs come from the dictionaries
/// (`DatabaseService.learningPairs`). A `uiLanguage` is the in-app
/// language's code, `en` or `el`.
enum LearningPairs {
    /// The limited pairs (Kirill, 2026-11-04). Greek via Russian has no
    /// Greek–Russian dictionary: its meanings are English. Each is offered
    /// while its meanings pair is, with that pair's dictionaries, until a
    /// dictionary makes it a full pair.
    static let limitedPairs = [LearningPair(lang: "ell", via: "rus", meaningsLang: "eng")]

    /// The pairs `dictionaries` give, each with its sources in the order
    /// given: every distinct (`from`, `to`) with both languages known, `und`
    /// left out; then the limited pairs.
    static func offered(_ dictionaries: [(source: String, from: String?, to: String?)]) -> [LearningPair: [String]] {
        var pairs: [LearningPair: [String]] = [:]
        for dictionary in dictionaries {
            guard let from = dictionary.from, let to = dictionary.to,
                  ![from, to].contains(where: { $0.isEmpty || $0 == "und" }) else { continue }
            let pair = LearningPair(lang: from, via: to)
            if pairs[pair]?.contains(dictionary.source) != true {
                pairs[pair, default: []].append(dictionary.source)
            }
        }
        for limited in limitedPairs where pairs[LearningPair(lang: limited.lang, via: limited.via)] == nil {
            pairs[limited] = pairs[LearningPair(lang: limited.lang, via: limited.meaningsLang)]
        }
        return pairs
    }

    /// The UI language's ISO 639-3 code as the dictionaries write it:
    /// `el` is `ell`, `ar` is `arb`.
    static func code(ofUILanguage uiLanguage: String) -> String {
        let base = uiLanguage.split(separator: "-").first.map(String.init) ?? uiLanguage
        return uiLanguageCodes[base] ?? base
    }

    private static let uiLanguageCodes = ["en": "eng", "el": "ell", "es": "spa", "ru": "rus", "ar": "arb"]

    /// The via a language gets when it is chosen: the UI language when that
    /// pair is offered, limited or not (a Russian UI learns Greek via
    /// Russian, Kirill 2026-11-04), else English when offered, else the
    /// first via by code; nil when the language has no pair.
    static func defaultVia(for lang: String, offered: some Collection<LearningPair>, uiLanguage: String) -> String? {
        let vias = Set(offered.filter { $0.lang == lang }.map(\.via))
        let ui = code(ofUILanguage: uiLanguage)
        if vias.contains(ui) { return ui }
        if vias.contains("eng") { return "eng" }
        return vias.min()
    }

    /// The pair of a learned language: its stored via's while offered, else
    /// its default via's; nil when the language has no pair. With no via
    /// stored, the pair "Learn %@ via %@?" offers.
    static func pair(for lang: String, stored: [String: String], offered: some Collection<LearningPair>,
                     uiLanguage: String) -> LearningPair? {
        func pair(via: String?) -> LearningPair? { offered.first { $0.lang == lang && $0.via == via } }
        return pair(via: stored[lang]) ?? pair(via: defaultVia(for: lang, offered: offered, uiLanguage: uiLanguage))
    }

    /// The vias offered for `lang`, as the Settings menu lists them: the
    /// default first, then the others by `name`.
    static func vias(for lang: String, offered: some Collection<LearningPair>, uiLanguage: String,
                     name: (String) -> String = { $0 }) -> [String] {
        guard let first = defaultVia(for: lang, offered: offered, uiLanguage: uiLanguage) else { return [] }
        let others = Set(offered.filter { $0.lang == lang && $0.via != first }.map(\.via))
        return [first] + byName(others, name)
    }

    /// The picker's rows: the pairs of the languages not learned. Languages
    /// with built-in lists first, then the others, each group by `name`;
    /// within a language, its vias as `vias(for:)` orders them.
    static func pickerRows(offered: some Collection<LearningPair>, withLists: Set<String>, learned: [String],
                           uiLanguage: String, name: (String) -> String = { $0 }) -> [LearningPair] {
        let languages = Set(offered.map(\.lang)).subtracting(learned)
        let ordered = byName(languages.intersection(withLists), name) + byName(languages.subtracting(withLists), name)
        return ordered.flatMap { lang in
            vias(for: lang, offered: offered, uiLanguage: uiLanguage, name: name).compactMap { via in
                offered.first { $0.lang == lang && $0.via == via }
            }
        }
    }

    /// Where a word's entry and meaning are looked up: the pair's
    /// dictionaries in Dictionary Order, then the rest of Dictionary Order,
    /// enabled sources first in each part (`enabled` nil: all enabled). A
    /// pair dictionary missing from the order follows the pair's others.
    static func sourceOrder(pair: LearningPair, pairSources: [LearningPair: [String]], dictionaryOrder: [String],
                            enabled: Set<String>? = nil) -> [String] {
        let own = pairSources[pair] ?? []
        let order = dictionaryOrder + own.filter { !dictionaryOrder.contains($0) }
        let isOwn = Set(own)
        func isOn(_ source: String) -> Bool { enabled?.contains(source) ?? true }
        return [true, false].flatMap { own in
            [true, false].flatMap { on in order.filter { isOwn.contains($0) == own && isOn($0) == on } }
        }
    }

    /// `codes` by `name`, alike names by code.
    private static func byName(_ codes: Set<String>, _ name: (String) -> String) -> [String] {
        codes.map { (code: $0, name: name($0)) }
            .sorted {
                switch $0.name.localizedStandardCompare($1.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return $0.code < $1.code
                }
            }
            .map(\.code)
    }
}

// MARK: - Statistics (0166, #163)
//
// The numbers of 0166, "The numbers, defined": pure, over the answer log's
// rows or the store's grouped counts, and tested without a database. SQL
// stays in `DatabaseService` ("Learning statistics").

extension LearnDay {
    /// Midnight UTC of the day: days are counted in UTC, where every day has
    /// 24 hours.
    private var utcDate: Date {
        let parts = rawValue.split(separator: "-").map { Int($0)! }
        return Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    /// Whole days from `self` to `other`: positive when `other` is later.
    func days(to other: LearnDay) -> Int {
        Self.calendar.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// Monday, the first day of an ISO week, whatever the locale's first
    /// weekday: the Gregorian weekday numbers do not depend on the locale.
    var isMonday: Bool { Self.calendar.component(.weekday, from: utcDate) == 2 }

    /// The days from `start` through `end`, oldest first; empty when `end`
    /// is earlier.
    static func range(_ start: LearnDay, through end: LearnDay) -> [LearnDay] {
        guard start <= end else { return [] }
        var days: [LearnDay] = []
        days.reserveCapacity(start.days(to: end) + 1)
        var date = start.utcDate
        let last = end.utcDate
        while date <= last {
            days.append(LearnDay(date: date, calendar: calendar))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return days
    }
}

/// One answer of the log, as the statistics read it (`learn_review`).
struct ReviewRow: Hashable, Sendable {
    let word: WordKey
    let kind: CardKind
    let outcome: Outcome
    /// The answer that started its word (`introduced = 1`).
    var introduced = false
    var durationMs = 0
}

/// Answers and right answers (right or accent) of a group.
struct Tally: Hashable, Sendable {
    var answers = 0
    var right = 0

    var wrong: Int { answers - right }
    /// Right ÷ all; nil without answers.
    var accuracy: Double? { answers > 0 ? Double(right) / Double(answers) : nil }

    static func + (lhs: Tally, rhs: Tally) -> Tally {
        Tally(answers: lhs.answers + rhs.answers, right: lhs.right + rhs.right)
    }

    static func += (lhs: inout Tally, rhs: Tally) { lhs = lhs + rhs }
}

/// The numbers of a set of answers: a day of one language (Today), a run
/// (0131's summary) or a day of the chart. Today and a summary use this one
/// function, so they always agree.
struct ReviewSummary: Hashable, Sendable {
    /// An answer counts for at most 60 s of time.
    static let durationCapMs = 60_000

    /// Rows of every kind.
    var exercises = 0
    /// Right and accent rows.
    var right = 0
    /// Rows with `introduced = 1`: a word counts on the day of its first
    /// answer, once.
    var newWords = 0
    /// Distinct words with a recognition or production row,
    /// `introduced = 0`, and no `introduced = 1` row among the same rows: a
    /// word started today is new, never also reviewed (PM, 2026-11-04).
    var reviewedWords = 0
    /// The sum of `duration_ms`, each capped at 60 s.
    var timeMs = 0

    /// Right ÷ all; nil without answers.
    var accuracy: Double? { Tally(answers: exercises, right: right).accuracy }

    static func of(_ rows: [ReviewRow]) -> ReviewSummary {
        var summary = ReviewSummary()
        var reviewed = Set<WordKey>(), started = Set<WordKey>()
        for row in rows {
            summary.exercises += 1
            if row.outcome.isRight { summary.right += 1 }
            if row.introduced {
                summary.newWords += 1
                started.insert(row.word)
            } else if CardKind.wordKinds.contains(row.kind) {
                reviewed.insert(row.word)
            }
            summary.timeMs += min(max(row.durationMs, 0), durationCapMs)
        }
        summary.reviewedWords = reviewed.subtracting(started).count
        return summary
    }
}

/// One active day of the log, every language (`DatabaseService.dayCounts`).
struct DayCount: Hashable, Sendable {
    var exercises = 0
    var right = 0
    /// Capped at 60 s per answer, as `ReviewSummary.timeMs`.
    var timeMs = 0
    var newWords = 0
}

/// A day of the 30-day chart.
struct DayPoint: Hashable, Sendable {
    let day: LearnDay
    let exercises: Int
}

/// The last 30 days: today and the 29 days before. The chart, the accuracy,
/// the hardest words and the forecast's pace use this window.
enum DailySeries {
    static let length = 30

    /// The window's first day.
    static func start(today: LearnDay) -> LearnDay { today.adding(days: -(length - 1)) }

    /// Exercises per day, oldest first, today last; days without answers
    /// are 0.
    static func last30(_ counts: [LearnDay: Int], today: LearnDay) -> [DayPoint] {
        LearnDay.range(start(today: today), through: today).map { DayPoint(day: $0, exercises: counts[$0] ?? 0) }
    }
}

// MARK: Streak

/// A day of the streak calendar.
enum DayMark: String, Sendable {
    /// The day's goal was met.
    case met
    /// Missed, saved by a freeze: the streak stayed.
    case frozen
    /// Missed: the streak went to 0, or stayed at 0.
    case missed
    /// Today, goal not met yet: not a miss before the day ends.
    case open
    /// Before the first answer, or after today.
    case none
}

/// The streak as of today (`Streak.compute`).
struct StreakState: Hashable, Sendable {
    var current = 0
    var best = 0
    /// Freezes in stock today, 0 to 3.
    var freezes = 0
    /// Every day from the first day with answers through today.
    var marks: [LearnDay: DayMark] = [:]

    func mark(on day: LearnDay) -> DayMark { marks[day] ?? DayMark.none }
}

/// The daily goal's streak (Kirill, 2026-10-22 and 2026-11-03). Weeks run
/// Monday to Sunday:
/// - a day whose goal is met adds 1;
/// - a missed day spends a freeze when one is in stock and the streak is
///   above 0: the streak stays;
/// - a missed day with no freeze, or with a streak of 0: the streak is 0;
/// - every Monday adds a freeze, up to 3 in stock; a first week that starts
///   after Monday has none;
/// - today counts once its goal is met and is no miss before it ends.
enum Streak {
    static let maxFreezes = 3

    /// - Parameters:
    ///   - counts: exercises per day, every language (`dayCounts`).
    ///   - goals: the goal in force when each past day ended (`learn_day`);
    ///     a day without one uses `currentGoal`.
    ///   - currentGoal: today's goal, the current setting.
    static func compute(counts: [LearnDay: Int], goals: [LearnDay: Int], currentGoal: Int,
                        today: LearnDay) -> StreakState {
        var state = StreakState()
        guard let first = counts.filter({ $0.value > 0 }).keys.min() else { return state }
        for day in LearnDay.range(first, through: today) {
            if day.isMonday {
                state.freezes = min(state.freezes + 1, maxFreezes)
            }
            let goal = day == today ? currentGoal : (goals[day] ?? currentGoal)
            let mark: DayMark
            if (counts[day] ?? 0) >= goal {
                state.current += 1
                mark = .met
            } else if day == today {
                mark = .open
            } else if state.current > 0 && state.freezes > 0 {
                state.freezes -= 1
                mark = .frozen
            } else {
                state.current = 0
                mark = .missed
            }
            state.marks[day] = mark
            state.best = max(state.best, state.current)
        }
        return state
    }
}

// MARK: Accuracy

/// Accuracy by direction over the last 30 days.
struct DirectionAccuracy: Hashable, Sendable {
    /// Match the pairs included: its rows are recognition rows.
    var recognition = Tally()
    var production = Tally()
}

enum Accuracy {
    /// Recognition and production from tallies grouped by card kind;
    /// conjugation rows are left out.
    static func byDirection(_ tallies: [CardKind: Tally]) -> DirectionAccuracy {
        DirectionAccuracy(recognition: tallies[.recognition] ?? Tally(), production: tallies[.production] ?? Tally())
    }

    /// The tense of an E5 facet `<tense>.<voice>`: the part before the dot,
    /// or the whole facet without one.
    static func tense(ofFacet facet: String) -> String {
        facet.firstIndex(of: ".").map { String(facet[..<$0]) } ?? facet
    }

    /// Conjugation tallies by facet, merged by tense: both voices of a tense
    /// are one group. E5 orders and names the tenses.
    static func byTense(_ facets: [String: Tally]) -> [String: Tally] {
        var tenses: [String: Tally] = [:]
        for (facet, tally) in facets { tenses[tense(ofFacet: facet), default: Tally()] += tally }
        return tenses
    }
}

// MARK: Hardest words

/// A word or a verb with its answers in the window, for the hardest words
/// and the hardest verbs.
struct HardWord: Hashable, Sendable {
    let key: WordKey
    /// Shown: the stored term, else the key's word.
    let term: String
    /// The list's translation; `""` = the entry's meaning.
    let translation: String
    /// The language of `translation`, as `LearnWord.translationLang`: #164
    /// picks the meaning in the pair's meanings language with it.
    let translationLang: String
    /// Opens the Definition; nil for a word without an entry.
    let entry: EntryKey?
    let tally: Tally
    /// The log id of its latest wrong answer: a larger id is later.
    let latestMistake: Int64
}

enum HardestWords {
    static let wordLimit = 20
    static let verbLimit = 10

    /// The words with at least one mistake: most wrong first, then lower
    /// accuracy, then the latest mistake; at most `limit`.
    static func rank(_ words: [HardWord], limit: Int) -> [HardWord] {
        let ranked = words.filter { $0.tally.wrong > 0 }.sorted { a, b in
            if a.tally.wrong != b.tally.wrong { return a.tally.wrong > b.tally.wrong }
            // a.right / a.answers < b.right / b.answers, without division.
            let lhs = a.tally.right * b.tally.answers, rhs = b.tally.right * a.tally.answers
            if lhs != rhs { return lhs < rhs }
            if a.latestMistake != b.latestMistake { return a.latestMistake > b.latestMistake }
            return (a.key.lang, a.key.word) < (b.key.lang, b.key.word)
        }
        return Array(ranked.prefix(max(limit, 0)))
    }
}

// MARK: List progress and forecast

/// A list's progress over its distinct words (0166): E3's list keys and the
/// language's word states (`DatabaseService.wordStates(lang:)`).
struct ListProgress: Hashable, Sendable {
    enum Stage: Hashable, Sendable {
        /// No cards, paused, or no word card answered yet, as `WordStatus`
        /// (PM, 2026-11-04).
        case new
        /// Unpaused, a word card answered, not learned.
        case learning
        /// Both word cards at 30 days or more.
        case learned
    }

    /// The list's distinct words, in list order.
    let words: [WordKey]
    let new: Int
    let learning: Int
    let learned: Int
    /// The day each started word was started on (`introduced_day`), oldest
    /// first.
    let startedDays: [LearnDay]

    var total: Int { words.count }

    /// Words started from `since` through `today`.
    func startedCount(since: LearnDay, through today: LearnDay) -> Int {
        startedDays.filter { $0 >= since && $0 <= today }.count
    }

    static func stage(of state: WordLearningState?) -> Stage {
        guard let state, !state.wordCards.isEmpty, !state.isPaused,
              !state.wordCards.allSatisfy(\.isNew) else { return .new }
        let ladder = FixedLadder()
        let cards = state.wordCards
        if Set(cards.map(\.key.kind)) == Set(CardKind.wordKinds), cards.allSatisfy(ladder.isLearned) {
            return .learned
        }
        return .learning
    }

    /// `items` may repeat a word: it counts once.
    static func of(items: [WordKey], states: [WordKey: WordLearningState]) -> ListProgress {
        var seen = Set<WordKey>()
        let words = items.filter { seen.insert($0).inserted }
        var counts: [Stage: Int] = [:]
        var startedDays: [LearnDay] = []
        for word in words {
            counts[stage(of: states[word]), default: 0] += 1
            if let day = states[word]?.word.introducedDay { startedDays.append(day) }
        }
        return ListProgress(words: words, new: counts[.new] ?? 0, learning: counts[.learning] ?? 0,
                            learned: counts[.learned] ?? 0, startedDays: startedDays.sorted())
    }
}

/// When a list is all learned, both cards at 30 days (Kirill, 2026-11-03).
/// An empty list has none (`days` returns nil): the forecast is hidden.
enum Forecast: Hashable, Sendable {
    /// All learned in about this many days, 1 or more: "~1 day", never
    /// "~0 days" (PM, 2026-11-04).
    case days(Int)
    /// New words left and none started in the window: "Start learning to
    /// see a forecast".
    case noPace
    /// "All learned".
    case done

    /// Days from a new card's first right answer to learned: 1 + 3 + 7 + 14.
    static var newWordDays: Int { daysToLearned(step: 0) }

    /// The intervals from the rung above `step` up to the last rung below
    /// learned (14 days): 25 on rung 0, 0 on rung 4.
    private static func daysToLearned(step: Int) -> Int {
        let learningRungs = FixedLadder.intervals.prefix { $0 < FixedLadder.learnedInterval }
        return learningRungs.dropFirst(max(step, 0)).reduce(0, +)
    }

    /// A card's days until learned: its days until due plus the rungs left
    /// below learned; 0 once learned.
    static func daysToLearned(_ card: CardState, today: LearnDay) -> Int {
        guard !FixedLadder().isLearned(card) else { return 0 }
        return max(0, today.days(to: card.dueDay)) + daysToLearned(step: card.step)
    }

    /// - an empty list: nil, no forecast (PM, 2026-11-04);
    /// - pace: words of the list started in the last 30 days ÷ 30, or ÷ the
    ///   days since its first started word, today included, when fewer;
    /// - a learning word needs the larger of its cards' `daysToLearned`;
    /// - no new words: the learning words' largest, at least 1, or `.done`;
    /// - new words and no pace: `.noPace`;
    /// - else the larger of `ceil(new ÷ pace) + 25` and the learning words'
    ///   largest.
    static func days(progress: ListProgress, states: [WordKey: WordLearningState], today: LearnDay) -> Forecast? {
        guard progress.total > 0 else { return nil }
        let learning = progress.words.compactMap { word -> Int? in
            guard let state = states[word], ListProgress.stage(of: state) == .learning else { return nil }
            return state.wordCards.map { daysToLearned($0, today: today) }.max()
        }.max()
        guard progress.new > 0 else { return learning.map { .days(max($0, 1)) } ?? .done }
        let started = progress.startedCount(since: DailySeries.start(today: today), through: today)
        guard started > 0, let first = progress.startedDays.first else { return .noPace }
        let window = min(DailySeries.length, max(first.days(to: today) + 1, 1))
        // ceil(new ÷ (started ÷ window)), in integers.
        let newDays = (progress.new * window + started - 1) / started + newWordDays
        return .days(max(newDays, learning ?? 0))
    }
}

// MARK: - Conjugation drill: tenses and levels (0132, #167)
//
// 0132-conjugation-drill.md, "Tenses and levels", "Verbs" and "Questions and
// options". Every form the drill asks or offers is a form of #144's tables
// (`ParadigmLayout.VoiceForms`), except the θα / να + present fallback of a
// verb without a dependent stem (Kirill, 2026-11-04).

/// A tense of the drill, in the tables' order (#144). The raw values are
/// ASCII without a dot: they are the first part of a card's facet, which
/// E10 groups on.
enum ConjugationTense: String, CaseIterable, Sendable {
    case present, imperfect, aorist, future
    case imperativeContinuous, imperativeSimple
    case futureContinuous, perfect, pluperfect, futurePerfect
    case subjunctiveContinuous, subjunctiveSimple

    typealias Person = ParadigmLayout.Person

    /// "Aorist"; a mood with its aspect: "Subjunctive · simple". Built from
    /// #144's labels, so no key of its own. The separator is not translated.
    func title(locale: Locale) -> String {
        let (head, aspect) = labels
        guard let aspect else { return head.title(locale: locale) }
        return head.title(locale: locale) + " · " + aspect.text(locale: locale)
    }

    private var labels: (FormLabel, FormLabel?) {
        switch self {
        case .present: return (.present, nil)
        case .imperfect: return (.imperfect, nil)
        case .aorist: return (.aorist, nil)
        case .future: return (.future, nil)
        case .imperativeContinuous: return (.imperative, .continuous)
        case .imperativeSimple: return (.imperative, .simple)
        case .futureContinuous: return (.futureContinuous, nil)
        case .perfect: return (.perfect, nil)
        case .pluperfect: return (.pluperfect, nil)
        case .futurePerfect: return (.futurePerfect, nil)
        case .subjunctiveContinuous: return (.subjunctive, .continuous)
        case .subjunctiveSimple: return (.subjunctive, .simple)
        }
    }

    /// The persons the tense has: εσύ and εσείς for the imperatives.
    var persons: [Person] {
        switch self {
        case .imperativeContinuous, .imperativeSimple: return [.secondSingular, .secondPlural]
        default: return Person.allCases
        }
    }

    /// The forms of `person` in this tense of `voice`, in table order. The
    /// simple tenses are the cells; the others are #144's generated forms.
    /// A voice with a present and no dependent form (είμαι, έχω) takes θα and
    /// να + the present as its Future and simple Subjunctive, and has no
    /// continuous ones of its own (Kirill, 2026-11-04).
    func forms(_ voice: ParadigmLayout.VoiceForms, _ person: Person) -> [String] {
        forms(voice, person, lacksDependent: Self.lacksDependent(voice))
    }

    /// `forms(_:_:)` with `lacksDependent(voice)` given, for a whole table.
    func forms(_ voice: ParadigmLayout.VoiceForms, _ person: Person, lacksDependent: Bool) -> [String] {
        switch self {
        case .present: return voice.forms(.present, person)
        case .imperfect: return voice.forms(.imperfect, person)
        case .aorist: return voice.forms(.aorist, person)
        case .imperativeContinuous: return voice.forms(.imperativeContinuous, person)
        case .imperativeSimple: return voice.forms(.imperativeSimple, person)
        case .future: return lacksDependent ? voice.futureContinuous(person) : voice.future(person)
        case .subjunctiveSimple: return lacksDependent ? voice.subjunctiveContinuous(person) : voice.subjunctiveSimple(person)
        case .futureContinuous: return lacksDependent ? [] : voice.futureContinuous(person)
        case .subjunctiveContinuous: return lacksDependent ? [] : voice.subjunctiveContinuous(person)
        case .perfect: return voice.perfect(person)
        case .pluperfect: return voice.pluperfect(person)
        case .futurePerfect: return voice.futurePerfect(person)
        }
    }

    /// A voice with present forms and no dependent form.
    static func lacksDependent(_ voice: ParadigmLayout.VoiceForms) -> Bool {
        func has(_ slot: ParadigmLayout.FiniteSlot) -> Bool {
            Person.allCases.contains { !voice.forms(slot, $0).isEmpty }
        }
        return has(.present) && !has(.dependent)
    }
}

/// A tense in a voice: one drill card per verb (0131, "For E5"), a
/// `CardKind.conjugation` card whose `CardKey.facet` is `rawValue`.
struct ConjugationFacet: Hashable, Sendable {
    let tense: ConjugationTense
    let voice: ParadigmLayout.Voice

    init(_ tense: ConjugationTense, _ voice: ParadigmLayout.Voice) {
        self.tense = tense
        self.voice = voice
    }

    /// `<tense>.<voice>`: `aorist.active`, `present.passive`.
    var rawValue: String { "\(tense.rawValue).\(voice.rawValue)" }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let tense = ConjugationTense(rawValue: String(parts[0])),
              let voice = ParadigmLayout.Voice(rawValue: String(parts[1])) else { return nil }
        self.init(tense, voice)
    }
}

/// A tense level after the ΚΕΓ syllabus: each level adds tenses, and the
/// drill asks every tense up to its level. It never selects verbs.
enum DrillLevel: String, CaseIterable, Comparable, Sendable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2"

    static func < (lhs: DrillLevel, rhs: DrillLevel) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The facets of a verb up to this level, its main voice first, each
    /// voice in the tables' order ("Levels"):
    /// - main voice active: A1 present, aorist, future, simple subjunctive
    ///   and imperative; B1 the imperfect and the continuous ones; B2 the
    ///   perfect tenses;
    /// - main voice passive (passive forms only): nothing at A1, then the
    ///   same tenses a level later for the A1 set (A1 is active only);
    /// - the passive of a verb with both voices (`hasPassive`): the present
    ///   at A2, the continuous future and subjunctive at B1, the rest at B2.
    func facets(mainVoice: ParadigmLayout.Voice, hasPassive: Bool) -> [ConjugationFacet] {
        var result = ConjugationTense.allCases
            .filter { Self.mainLevel(of: $0, voice: mainVoice) <= self }
            .map { ConjugationFacet($0, mainVoice) }
        if mainVoice == .active && hasPassive {
            result += ConjugationTense.allCases
                .filter { Self.passiveLevel(of: $0) <= self }
                .map { ConjugationFacet($0, .passive) }
        }
        return result
    }

    /// The level that adds `tense` in the main voice.
    static func mainLevel(of tense: ConjugationTense, voice: ParadigmLayout.Voice) -> DrillLevel {
        let level: DrillLevel
        switch tense {
        case .present, .aorist, .future, .subjunctiveSimple, .imperativeSimple: level = .a1
        case .imperfect, .futureContinuous, .subjunctiveContinuous, .imperativeContinuous: level = .b1
        case .perfect, .pluperfect, .futurePerfect: level = .b2
        }
        // A1 is active only: a verb with passive forms only starts at A2.
        return voice == .passive ? max(level, .a2) : level
    }

    /// The level that adds `tense` in the passive of a verb with both voices.
    static func passiveLevel(of tense: ConjugationTense) -> DrillLevel {
        switch tense {
        case .present: return .a2
        case .futureContinuous, .subjunctiveContinuous: return .b1
        default: return .b2
        }
    }
}

/// What the drill asks, from the preferences (0132, "Tenses and levels"):
/// the checked built-in Greek lists choose the verbs, the highest of them
/// (or "Tenses up to", which only raises it) the tenses.
enum DrillScope {
    /// Kirill's Greek series (0130). There is no B2 list: B2 is a tense level only.
    static let series = "ky-ell"

    /// The series' lists by level, in level order.
    static let lists: [(id: WordListID, level: DrillLevel)] = [
        ("ky-ell-a1", .a1), ("ky-ell-a2", .a2), ("ky-ell-b1", .b1),
    ]

    /// The built-in Greek lists among `checked`, in level order. Imported
    /// lists never feed the drill.
    static func greekLists(checked: Set<WordListID>) -> [WordListID] {
        lists.map(\.id).filter(checked.contains)
    }

    /// The highest checked list's level, or A1 when none is checked.
    static func floor(checked: Set<WordListID>) -> DrillLevel {
        lists.filter { checked.contains($0.id) }.map(\.level).max() ?? .a1
    }

    /// The tense level: the stored "Tenses up to", which only raises the floor.
    static func tenseLevel(checked: Set<WordListID>, stored: DrillLevel?) -> DrillLevel {
        let floor = Self.floor(checked: checked)
        return max(stored ?? floor, floor)
    }

    /// The segments of "Tenses up to": the floor up to B2.
    static func offeredLevels(checked: Set<WordListID>) -> [DrillLevel] {
        let floor = Self.floor(checked: checked)
        return DrillLevel.allCases.filter { $0 >= floor }
    }
}

// MARK: - Conjugation drill: verbs (0132, #167)

/// A verb the drill asks, with the voices it drills.
struct DrillVerb: Equatable, Sendable {
    typealias Voice = ParadigmLayout.Voice
    typealias Person = ParadigmLayout.Person

    /// The card's word (NFC): the lemma, or a list word that is the passive
    /// of another verb's table (ντύνομαι in ντύνω's).
    let word: String
    /// The word the prompt shows: the main voice's present εγώ (γράφω,
    /// έρχομαι, πηγαίνω), αυτός for an impersonal verb (πρέπει), else `word`.
    let citation: String
    /// In the meanings language of Greek's pair (0131). From a list
    /// (`DatabaseService.drillVerbs(lists:meaningsLang:)`): the list's
    /// translation when it is in that language, else empty.
    let translation: String
    /// The list it came from, 1 … 3 (A1 … B1); nil from the Definition screen.
    let listLevel: Int?
    let rank: Int?
    let seq: Int
    /// Active, or the passive for a verb with passive forms only: its
    /// questions carry the "passive" note.
    let mainVoice: Voice
    /// Only the voices drilled.
    let voices: [Voice: ParadigmLayout.VoiceForms]
    /// Every finite form of the main voice is in the third person: only
    /// αυτός is asked.
    let isImpersonal: Bool
    /// Every non-empty cell of the drilled voices, generated forms included
    /// (`ConjugationTense.forms`), with its forms folded: computed once, so
    /// building questions folds nothing.
    let cells: [ConjugationFacet: [Person: Cell]]

    struct Cell: Equatable, Sendable {
        /// In table order; the first is the one offered.
        let forms: [String]
        /// Each form folded (`ConjugationQuestionBuilder.fold`).
        let keys: [String]
    }

    init(word: String, citation: String, translation: String, listLevel: Int?, rank: Int?, seq: Int,
         mainVoice: Voice, voices: [Voice: ParadigmLayout.VoiceForms], isImpersonal: Bool) {
        self.word = word
        self.citation = citation
        self.translation = translation
        self.listLevel = listLevel
        self.rank = rank
        self.seq = seq
        self.mainVoice = mainVoice
        self.voices = voices
        self.isImpersonal = isImpersonal
        var cells: [ConjugationFacet: [Person: Cell]] = [:]
        for (voice, voiceForms) in voices {
            let lacksDependent = ConjugationTense.lacksDependent(voiceForms)
            for tense in ConjugationTense.allCases {
                for person in tense.persons {
                    let forms = tense.forms(voiceForms, person, lacksDependent: lacksDependent)
                    guard !forms.isEmpty else { continue }
                    let keys = forms.map(ConjugationQuestionBuilder.fold)
                    cells[ConjugationFacet(tense, voice), default: [:]][person] = Cell(forms: forms, keys: keys)
                }
            }
        }
        self.cells = cells
    }

    /// A verb whose main voice is active and that also drills its passive.
    var hasPassive: Bool { mainVoice == .active && voices[.passive] != nil }

    /// One cell; nil when it has no form.
    func cell(_ facet: ConjugationFacet, _ person: Person) -> Cell? {
        cells[facet]?[person]
    }

    /// The forms of one cell, generated forms included.
    func forms(_ facet: ConjugationFacet, _ person: Person) -> [String] {
        cell(facet, person)?.forms ?? []
    }

    /// The drill verb of `word` and the table the Definition rule gives it
    /// (#144); nil when no level has a question for it.
    /// - Own table: the lemma, in its main voice, plus the passive when the
    ///   main voice is active and the passive has a present.
    /// - Linked table (the word is a form or an alternative of the table's
    ///   verb): the voices in which the word is a finite cell. Passive only
    ///   (ντύνομαι in ντύνω's): the word itself, passive as its main voice.
    ///   Active (πάω in πηγαίνω's): the table's lemma, as if it was given.
    ///   Neither (a participle listed as a verb): no verb.
    static func make(word: String, paradigm: LemmaParadigm, translation: String,
                     listLevel: Int? = nil, rank: Int? = nil, seq: Int = 0) -> DrillVerb? {
        guard paradigm.pos == "verb" else { return nil }
        let word = word.precomposedStringWithCanonicalMapping
        let all = ParadigmLayout.voiceForms(paradigm.cells)
        // The voices in which a linked word is a finite cell of the table.
        let linkedVoices = Set(paradigm.cells.compactMap { cell -> Voice? in
            guard paradigm.isLinked, cell.form == word, let match = ParadigmLayout.verbSlot(of: cell.tags),
                  case .finite = match.slot else { return nil }
            return match.voice
        })
        let key: String
        let main: Voice
        var voices: [Voice: ParadigmLayout.VoiceForms] = [:]
        if !paradigm.isLinked || linkedVoices.contains(.active) {
            key = paradigm.word
            main = ParadigmLayout.mainVoice(all)
            voices[main] = all[main]
            let passivePresent = Person.allCases.contains { !(all[.passive]?.forms(.present, $0).isEmpty ?? true) }
            if main == .active && passivePresent { voices[.passive] = all[.passive] }
        } else if linkedVoices.contains(.passive) {
            key = word
            main = .passive
            voices[.passive] = all[.passive]
        } else {
            return nil
        }
        let persons = voices[main]?.persons ?? []
        let isImpersonal = !persons.isEmpty && persons.isSubset(of: [.thirdSingular, .thirdPlural])
        let cited = voices[main]?.forms(.present, isImpersonal ? .thirdSingular : .firstSingular).first
        let verb = DrillVerb(word: key, citation: cited ?? key, translation: translation, listLevel: listLevel,
                             rank: rank, seq: seq, mainVoice: main, voices: voices, isImpersonal: isImpersonal)
        // Levels add up, so B2 has every question a lower level has.
        return ConjugationQuestionBuilder.hasQuestion(verb: verb, level: .b2) ? verb : nil
    }
}

// MARK: - Conjugation drill: questions and options (0132, #167)

/// One question: "γράφω · Aorist · εγώ" and four options.
struct ConjugationQuestion: Sendable {
    typealias Person = ParadigmLayout.Person

    let verb: DrillVerb
    let facet: ConjugationFacet
    let person: Person
    /// Four options: the right one and three distractors, shuffled.
    let options: [String]
    let rightIndex: Int
    /// Every form of the asked cell; each one is right (γράφτηκα / γράφηκα).
    let rightForms: [String]
    /// The whole tense by person, every form, for the feedback.
    let tenseRows: [(person: Person, forms: [String])]

    /// A verb with passive forms only: the "passive" note next to the tense.
    var showsPassiveNote: Bool { verb.mainVoice == .passive }
    /// The passive of a verb with both voices: "passive" in the tense line.
    var showsVoice: Bool { facet.voice == .passive && verb.mainVoice == .active }
}

/// Builds the drill's questions (0132, "Questions and options"). Pure.
enum ConjugationQuestionBuilder {
    typealias Person = ParadigmLayout.Person
    typealias Voice = ParadigmLayout.Voice

    static let distractorCount = 3

    /// The question of one cell at tense level `level`, or nil when the cell
    /// is empty or has fewer than 3 distractors:
    /// 1. the right option is the cell's first form; its other forms are right too;
    /// 2. candidates, each a cell's first form: A, the same person in another
    ///    facet of the level; B, the same facet in another person; C, another
    ///    facet of the level in another person; D, the asked voice's other
    ///    tenses outside the level, any person;
    /// 3. a candidate that folds like a right form or a taken option is dropped;
    /// 4. one from A, one from B, the third from A ∪ B; gaps from C, then D;
    /// 5. the options are shuffled with `rng`.
    static func build<G: RandomNumberGenerator>(verb: DrillVerb, facet: ConjugationFacet, person: Person,
                                                level: DrillLevel, rng: inout G) -> ConjugationQuestion? {
        guard let asked = verb.cell(facet, person), let right = asked.forms.first else { return nil }
        let rightForms = asked.forms
        let levelFacets = facets(of: verb, level: level)
        let persons = Person.allCases
        typealias Candidate = (form: String, key: String)
        func first(_ facet: ConjugationFacet, _ person: Person) -> Candidate? {
            verb.cell(facet, person).map { ($0.forms[0], $0.keys[0]) }
        }
        let otherFacets = levelFacets.filter { $0 != facet }
        let otherPersons = persons.filter { $0 != person }
        let groupA = otherFacets.compactMap { first($0, person) }
        let groupB = otherPersons.compactMap { first(facet, $0) }
        // A ∪ B, then C and D, which are read only when A and B run short.
        let fills: [() -> [Candidate]] = [
            { groupA + groupB },
            { otherFacets.flatMap { other in otherPersons.compactMap { first(other, $0) } } },
            { outside(levelFacets, voice: facet.voice).flatMap { other in persons.compactMap { first(other, $0) } } },
        ]

        var taken = Set(asked.keys)
        var picked: [String] = []
        /// Picks one candidate of `group` at random, if any is left.
        func pick(_ group: [Candidate]) -> Bool {
            var keys = Set<String>()
            let left = group.filter { !taken.contains($0.key) && keys.insert($0.key).inserted }
            guard !left.isEmpty else { return false }
            let candidate = left[randomIndex(left.count, using: &rng)]
            picked.append(candidate.form)
            taken.insert(candidate.key)
            return true
        }
        _ = pick(groupA)
        _ = pick(groupB)
        for fill in fills where picked.count < distractorCount {
            let candidates = fill()
            while picked.count < distractorCount, pick(candidates) {}
        }
        guard picked.count == distractorCount else { return nil }

        var options = [right] + picked
        shuffle(&options, using: &rng)
        let tenseRows: [(person: Person, forms: [String])] = facet.tense.persons.compactMap { row in
            let forms = verb.forms(facet, row)
            return forms.isEmpty ? nil : (row, forms)
        }
        return ConjugationQuestion(verb: verb, facet: facet, person: person, options: options,
                                   rightIndex: options.firstIndex(of: right) ?? 0, rightForms: rightForms,
                                   tenseRows: tenseRows)
    }

    /// The level's facets of `verb` with the persons that build a question:
    /// a form, three distractors, never the cited cell (the main voice's
    /// present εγώ, or αυτός for an impersonal verb), and only αυτός for an
    /// impersonal verb. The planner, the verb count and Practise use it.
    static func questions(verb: DrillVerb, level: DrillLevel) -> [(facet: ConjugationFacet, persons: [Person])] {
        var rule = AskRule(verb: verb, level: level)
        let levelFacets = rule.levelFacets
        return levelFacets.compactMap { facet in
            let persons = facet.tense.persons.filter { rule.builds(facet, $0) }
            return persons.isEmpty ? nil : (facet, persons)
        }
    }

    /// Whether `questions(verb:level:)` has any; stops at the first.
    static func hasQuestion(verb: DrillVerb, level: DrillLevel) -> Bool {
        var rule = AskRule(verb: verb, level: level)
        let levelFacets = rule.levelFacets
        return levelFacets.contains { facet in facet.tense.persons.contains { rule.builds(facet, $0) } }
    }

    /// Which cells of a level `questions` lists.
    private struct AskRule {
        let verb: DrillVerb
        let levelFacets: [ConjugationFacet]
        private let cited: ConjugationFacet
        private let citedPerson: Person
        private var candidateKeys: [Voice: Set<String>] = [:]

        init(verb: DrillVerb, level: DrillLevel) {
            self.verb = verb
            levelFacets = ConjugationQuestionBuilder.facets(of: verb, level: level)
            cited = ConjugationFacet(.present, verb.mainVoice)
            citedPerson = verb.isImpersonal ? .thirdSingular : .firstSingular
        }

        /// Every candidate of a question in a voice is the first form of a
        /// level cell or of a cell outside the level in that voice (A ∪ B ∪
        /// C ∪ D), and the asked cell's own is right. So a question builds
        /// when at least 3 of these keys fold like no right form.
        mutating func builds(_ facet: ConjugationFacet, _ person: Person) -> Bool {
            if verb.isImpersonal && person != .thirdSingular { return false }
            if facet == cited && person == citedPerson { return false }
            guard let cell = verb.cell(facet, person) else { return false }
            let candidates = keys(facet.voice)
            return candidates.count - Set(cell.keys).filter(candidates.contains).count >= distractorCount
        }

        private mutating func keys(_ voice: Voice) -> Set<String> {
            if let cached = candidateKeys[voice] { return cached }
            let result = Set((levelFacets + outside(levelFacets, voice: voice)).flatMap { facet in
                Person.allCases.compactMap { verb.cell(facet, $0)?.keys[0] }
            })
            candidateKeys[voice] = result
            return result
        }
    }

    /// The level's facets in the voices `verb` drills.
    static func facets(of verb: DrillVerb, level: DrillLevel) -> [ConjugationFacet] {
        level.facets(mainVoice: verb.mainVoice, hasPassive: verb.hasPassive).filter { verb.voices[$0.voice] != nil }
    }

    /// The tenses of `voice` that are not among `levelFacets` (group D).
    private static func outside(_ levelFacets: [ConjugationFacet], voice: Voice) -> [ConjugationFacet] {
        ConjugationTense.allCases.map { ConjugationFacet($0, voice) }.filter { !levelFacets.contains($0) }
    }

    /// Options that read alike once accents, case and final sigma are
    /// folded are one option (0131's rule, as its `AnswerChecker.fold`,
    /// which #159 adds; until then the drill folds on its own):
    /// lowercased, NFD without nonspacing marks, ς as σ; for Greek forms the
    /// same key as `Search.foldGreek`. A form of Greek letters and spaces is
    /// folded letter by letter from a table, three times faster: every verb
    /// folds all its forms once (`DrillVerb.cells`).
    static func fold(_ form: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in form.unicodeScalars {
            if let folded = foldedGreekLetters[scalar] {
                scalars.append(contentsOf: folded)
            } else if scalar == " " {
                scalars.append(scalar)
            } else {
                return fullFold(form)
            }
        }
        return String(scalars)
    }

    /// `fullFold` of each Greek and Greek Extended code point.
    private static let foldedGreekLetters: [Unicode.Scalar: String.UnicodeScalarView] = {
        var table: [Unicode.Scalar: String.UnicodeScalarView] = [:]
        for value in UInt32(0x0370)...0x03FF {
            if let scalar = Unicode.Scalar(value) { table[scalar] = fullFold(String(scalar)).unicodeScalars }
        }
        for value in UInt32(0x1F00)...0x1FFF {
            if let scalar = Unicode.Scalar(value) { table[scalar] = fullFold(String(scalar)).unicodeScalars }
        }
        return table
    }()

    private static func fullFold(_ form: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in form.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar == "\u{03C2}" ? "\u{03C3}" : scalar)
        }
        return String(scalars)
    }

    /// A random index below `count`. Its own, with `shuffle`, so an order
    /// never changes with the standard library's.
    private static func randomIndex<G: RandomNumberGenerator>(_ count: Int, using rng: inout G) -> Int {
        Int(rng.next() % UInt64(count))
    }

    /// Fisher–Yates.
    private static func shuffle<G: RandomNumberGenerator>(_ items: inout [String], using rng: inout G) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, randomIndex(i + 1, using: &rng))
        }
    }
}
