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

// MARK: - Exercises (#159)
//
// Meanings, answer checking, distractors and questions: pure, tested
// without a database (0131, "Meanings" and "Questions and answers").

/// A seeded generator for the option order and the distractors, so a run
/// can be replayed (`-learningSeed`). SplitMix64.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The meaning shown in exercises, in the meanings language of the word's
/// pair (0131, "Meanings"): the list's translation when it is in that
/// language, else the first sense of the word in the pair's dictionaries,
/// shortened. Never translated into the UI language.
enum Gloss {
    /// A meaning is cut at this many characters.
    static let maxLength = 80

    /// Rule 1: the stored `translation` when it is not empty and in
    /// `meaningsLang`, or an import's (`translationLang` `""`), which shows
    /// in every pair. With no pair (`meaningsLang` nil: Other, rule 3), any
    /// translation. nil: the meaning comes from a dictionary.
    static func listMeaning(translation: String, translationLang: String, meaningsLang: String?) -> String? {
        let translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return nil }
        guard let meaningsLang, !translationLang.isEmpty else { return translation }
        return translationLang == meaningsLang ? translation : nil
    }

    /// The first sense of a definition:
    /// 1. part-of-speech header lines (`**verb**`) and example lines
    ///    (`*"…"*`) dropped, then the remaining `*` stripped;
    /// 2. the text after `1. `, or else the first non-empty line;
    /// 3. a WordNet-style sense `X — Y` keeps X;
    /// 4. cut at 80 characters, at a space or comma, with "…".
    static func short(definition: String) -> String {
        var lines: [String] = []
        for raw in definition.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !isHeader(line), !isExample(line) else { continue }
            let text = line.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append(text) }
        }
        var sense = lines.first { $0.hasPrefix("1. ") }.map { String($0.dropFirst(3)) } ?? lines.first ?? ""
        sense = sense.trimmingCharacters(in: .whitespaces)
        if let dash = sense.range(of: " — ") {
            let head = sense[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { sense = head }
        }
        return cut(sense)
    }

    /// `**verb**`: a part-of-speech header.
    private static func isHeader(_ line: String) -> Bool {
        line.count > 4 && line.hasPrefix("**") && line.hasSuffix("**")
    }

    /// `*"…"*`: an example line, in italics.
    private static func isExample(_ line: String) -> Bool {
        line.count > 2 && line.hasPrefix("*") && !line.hasPrefix("**") && line.hasSuffix("*")
    }

    private static func cut(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        let prefix = text.prefix(maxLength)
        let end = prefix.lastIndex { $0 == " " || $0 == "," } ?? prefix.endIndex
        let head = prefix[..<end].trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
        return (head.isEmpty ? String(prefix) : head) + "…"
    }
}

/// A typed answer, graded.
struct TypedGrade: Hashable, Sendable {
    let outcome: Outcome
    /// Only the accents were off: "Mind the accent". The answer is wrong in
    /// Strict mode and right (`accent`) in Lenient mode.
    let mindTheAccent: Bool
}

/// Grades typed answers (0131, "Questions and answers"). Case, extra
/// spaces, a final σ typed as σ and one leading article never count; a
/// part of the expected term in parentheses is optional.
enum AnswerChecker {
    /// The articles dropped at the start of an answer and of the term.
    static let articles: [String: Set<String>] = [
        "ell": ["ο", "η", "το", "οι", "τα"],
        "eng": ["the", "a", "an", "to"],
        "spa": ["el", "la", "los", "las", "un", "una"],
    ]

    /// Strict: equal after `normalize` is right; equal only after `fold`
    /// is wrong, with the accent hint. Lenient (and Multiple choice, should
    /// a choice question fall back to a field): equal after `fold` is
    /// `accent`, which counts as right. Anything else, an empty answer
    /// included, is wrong.
    static func check(_ typed: String, expected: String, lang: String, mode: AnswerMode) -> Outcome {
        grade(typed, expected: expected, lang: lang, mode: mode).outcome
    }

    static func grade(_ typed: String, expected: String, lang: String, mode: AnswerMode) -> TypedGrade {
        let answer = normalize(typed, lang: lang)
        let forms = Set(expectedForms(expected).map { normalize($0, lang: lang) }).subtracting([""])
        guard !answer.isEmpty, !forms.isEmpty else { return TypedGrade(outcome: .wrong, mindTheAccent: false) }
        if forms.contains(answer) { return TypedGrade(outcome: .right, mindTheAccent: false) }
        guard Set(forms.map(foldNormalized)).contains(foldNormalized(answer)) else {
            return TypedGrade(outcome: .wrong, mindTheAccent: false)
        }
        return TypedGrade(outcome: mode == .strict ? .wrong : .accent, mindTheAccent: true)
    }

    /// NFC, trimmed, inner spaces collapsed, lowercased; trailing `. ! ? ;`
    /// and the Greek question mark dropped; σ at a word end written ς and ς
    /// inside a word σ; one leading article of `lang` dropped.
    static func normalize(_ text: String, lang: String) -> String {
        var text = text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = text.last, ".!?;\u{037E}".contains(last) || last == " " {
            text.removeLast()
        }
        var characters = Array(text)
        for index in characters.indices where characters[index] == "σ" || characters[index] == "ς" {
            let atWordEnd = index + 1 == characters.count || !characters[index + 1].isLetter
            characters[index] = atWordEnd ? "ς" : "σ"
        }
        text = String(characters)
        if let articles = articles[lang], let space = text.firstIndex(of: " "),
           articles.contains(String(text[..<space])) {
            text = String(text[text.index(after: space)...])
        }
        return text
    }

    /// `normalize`, then without combining marks (accents, Greek
    /// dialytika, Arabic harakat) and the Arabic tatweel, with ς as σ, NFC.
    static func fold(_ text: String, lang: String) -> String {
        foldNormalized(normalize(text, lang: lang))
    }

    private static func foldNormalized(_ text: String) -> String {
        let scalars = text.decomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: return false
            default: return scalar != "\u{0640}"
            }
        }
        return String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "ς", with: "σ")
            .precomposedStringWithCanonicalMapping
    }

    /// The term with and without each part in parentheses: `(ένα) σωρό`
    /// gives `ένα σωρό` and `σωρό`. At most four parts are optional.
    static func expectedForms(_ term: String) -> [String] {
        var forms = [""]
        var rest = Substring(term)
        var optional = 0
        while optional < 4, let open = rest.firstIndex(of: "("),
              let close = rest[open...].firstIndex(of: ")") {
            let before = rest[..<open]
            let inner = rest[rest.index(after: open)..<close]
            forms = forms.flatMap { [$0 + before + inner, $0 + before + " "] }
            rest = rest[rest.index(after: close)...]
            optional += 1
        }
        return forms.map { $0 + rest }
    }
}

/// A word whose meaning `DatabaseService.meanings` looks up (0131,
/// "Meanings").
struct MeaningQuery: Hashable, Sendable {
    let key: WordKey
    /// Looked up in the pair's dictionaries: the headword, else the term.
    let lookup: String
    /// The list's; `""` = none.
    let translation: String
    /// Its language; `""` = an import's, shown in every pair.
    let translationLang: String
    /// The word's own entry: its meaning without a pair (Other, rule 3).
    var entry: EntryKey?

    init(key: WordKey, lookup: String, translation: String = "", translationLang: String = "", entry: EntryKey? = nil) {
        self.key = key
        self.lookup = lookup
        self.translation = translation
        self.translationLang = translationLang
        self.entry = entry
    }

    init(_ word: LearnWord) {
        self.init(key: word.key, lookup: word.entry?.word ?? word.term, translation: word.translation,
                  translationLang: word.translationLang, entry: word.entry)
    }
}

/// A word as a question asks it, or as another option next to it.
struct WordChoice: Hashable, Sendable {
    let key: WordKey
    /// Shown and expected, without its endings.
    let term: String
    var endings = ""
    /// In the pair's meanings language (`DatabaseService.meanings`); `""` =
    /// none in this pair: never asked, never an option.
    let meaning: String
    /// The list's or the entry's part of speech.
    var partOfSpeech = ""
    /// The E3 list it was picked from.
    var listID: String?
    /// Its dictionary entry; nil for a list word without one.
    var entry: EntryKey?
    /// In learning; false for a headword of the source sample.
    var isEnrolled = true
    /// The pair dictionary that gave `meaning`, where the source sample is
    /// drawn from; nil for a list translation.
    var meaningSource: String?
}

/// Chooses the other options of a question (0131, "Questions and answers").
enum DistractorPicker {
    /// A choice question shows the right option and up to 3 others.
    static let defaultCount = 3

    /// The first label of a part of speech, mapped as the inflection tables
    /// map it (#144: adjective satellite → adj); `""` for none.
    static func primaryPOS(_ pos: String) -> String {
        guard let first = pos.split(separator: ",").first?.trimmingCharacters(in: .whitespaces).lowercased(),
              !first.isEmpty else { return "" }
        return InflectionLookup.lemmaPOS(forEntryPOS: first).first ?? first
    }

    /// Up to `count` options besides `word`. Candidates come in order of
    /// preference: the word's own list, then the enrolled words, then the
    /// source sample; within each, the same primary part of speech first,
    /// in an order shuffled by `rng`. A candidate is dropped if it is the
    /// word itself, has no meaning, folds like an option already taken
    /// (term or meaning), or shares a comma-separated part of its meaning
    /// with one: no two options read alike. The caller gives every
    /// candidate its meaning in the word's meanings language, so the four
    /// options are in one language.
    static func pick(for word: WordChoice, candidates: [WordChoice], count: Int = defaultCount,
                     rng: inout some RandomNumberGenerator) -> [WordChoice] {
        let pos = primaryPOS(word.partOfSpeech)
        func rank(_ candidate: WordChoice) -> Int {
            let origin = word.listID != nil && candidate.listID == word.listID ? 0 : candidate.isEnrolled ? 1 : 2
            let samePOS = !pos.isEmpty && primaryPOS(candidate.partOfSpeech) == pos
            return origin * 2 + (samePOS ? 0 : 1)
        }
        let groups = Dictionary(grouping: candidates, by: rank)
        var taken: [WordChoice] = []
        var terms: Set<String> = [AnswerChecker.fold(word.term, lang: word.key.lang)]
        var parts = meaningParts(word.meaning)
        for group in groups.keys.sorted() {
            for candidate in groups[group, default: []].shuffled(using: &rng) {
                guard taken.count < count else { return taken }
                guard candidate.key != word.key else { continue }
                let candidateParts = meaningParts(candidate.meaning)
                let term = AnswerChecker.fold(candidate.term, lang: candidate.key.lang)
                guard !candidateParts.isEmpty, candidateParts.isDisjoint(with: parts), !terms.contains(term) else { continue }
                taken.append(candidate)
                terms.insert(term)
                parts.formUnion(candidateParts)
            }
        }
        return taken
    }

    /// The comma-separated parts of a meaning, folded; a whole meaning
    /// folds to the union of its parts.
    static func meaningParts(_ meaning: String) -> Set<String> {
        Set(meaning.split(separator: ",").map { AnswerChecker.fold(String($0), lang: "") }.filter { !$0.isEmpty })
    }
}

/// One question of a run.
struct Question: Hashable, Sendable {
    enum Input: Hashable, Sendable {
        /// Up to 4 options.
        case choice
        /// A text field, Check and "Don't know".
        case typed
    }

    struct Option: Hashable, Sendable {
        let text: String
        /// A word's endings, shown in the secondary colour.
        var endings = ""
    }

    /// The card asked, as it was when the question was built.
    let card: CardState
    let word: WordChoice
    /// The language of every meaning, as prompt or option: the pair's
    /// meanings language; nil without a pair (Other).
    let meaningsLang: String?
    let input: Input
    /// Empty for a typed question.
    let options: [Option]
    /// nil for a typed question.
    let rightIndex: Int?

    var isRecognition: Bool { card.key.kind == .recognition }
    /// A card's first question carries the "New word" badge.
    var isNew: Bool { card.isNew }
    /// The word (recognition) or its meaning (production).
    var prompt: String { isRecognition ? word.term : word.meaning }
    var promptEndings: String { isRecognition ? word.endings : "" }
    /// The word's language for a recognition prompt, the meanings language
    /// for a production one.
    var promptLanguage: String? { isRecognition ? word.key.lang : meaningsLang }
    /// The options' language: meanings for recognition, words for production.
    var optionLanguage: String? { isRecognition ? meaningsLang : word.key.lang }
    /// The option or the word that answers it.
    var rightAnswer: String { isRecognition ? word.meaning : word.term }

    var exercise: ExerciseKind {
        if isRecognition { return .recognition }
        return input == .typed ? .productionTyped : .productionChoice
    }
}

/// Builds a question from a card (0131, "Questions and answers").
enum QuestionBuilder {
    /// Recognition is always a choice. Production on rung 0 (new or
    /// learning) is a choice; on rung 1 or higher it is typed, unless the
    /// mode is Multiple choice.
    static func wantsChoice(_ card: CardState, mode: AnswerMode) -> Bool {
        card.key.kind == .recognition || card.step == 0 || mode == .choice
    }

    /// The question for `card` of `word`, its options shuffled by `rng`.
    /// `word` and `candidates` carry their meanings in `meaningsLang`, the
    /// pair's. nil, so the run skips the card without a log row, for a word
    /// without a meaning, a card that is not a word card, and a recognition
    /// card without any other option. A production card without one is typed.
    static func build(card: CardState, word: WordChoice, candidates: [WordChoice], mode: AnswerMode,
                      meaningsLang: String?, rng: inout some RandomNumberGenerator) -> Question? {
        guard CardKind.wordKinds.contains(card.key.kind), !word.meaning.isEmpty else { return nil }
        let isRecognition = card.key.kind == .recognition
        if wantsChoice(card, mode: mode) {
            let others = DistractorPicker.pick(for: word, candidates: candidates, rng: &rng)
            if !others.isEmpty {
                func option(_ choice: WordChoice) -> Question.Option {
                    isRecognition ? Question.Option(text: choice.meaning) : Question.Option(text: choice.term, endings: choice.endings)
                }
                var options = others.map(option)
                let rightIndex = Int.random(in: 0...options.count, using: &rng)
                options.insert(option(word), at: rightIndex)
                return Question(card: card, word: word, meaningsLang: meaningsLang, input: .choice, options: options,
                                rightIndex: rightIndex)
            }
            if isRecognition { return nil }
        }
        return Question(card: card, word: word, meaningsLang: meaningsLang, input: .typed, options: [], rightIndex: nil)
    }
}

// MARK: - Runs (#159; the session and mistakes in #161)
//
// A run's summary is `ReviewSummary` over its log rows (#163,
// `reviewRows(run:)`), the same function as Today's numbers.

/// One item of a run's plan.
struct PlannedItem: Hashable, Sendable {
    /// The card as it was when planned, or after the answer that requeued it.
    var card: CardState
    /// Requeued after a wrong answer: it does not come back again.
    var isRetry = false
}

/// Plans the runs (0131, "Runs"). Pure.
enum SessionPlanner {
    /// The items of a trainer.
    static let trainerLength = 10

    /// A trainer of `kind`: due cards first, then the new words' cards,
    /// then practice, the lowest rungs first; at most 10, each card once.
    /// `newWords` come within the daily limit; their cards are new, as
    /// created.
    static func trainer(kind: CardKind, due: [CardState], newWords: [LearnWord], practice: [CardState],
                        today: LearnDay, count: Int = trainerLength) -> [PlannedItem] {
        let new = newWords.map { CardState(key: CardKey(word: $0.key, kind: kind), step: 0, dueDay: today) }
        var seen = Set<CardKey>()
        var items: [PlannedItem] = []
        for card in due + new + practice where items.count < count && card.key.kind == kind && !card.isSuspended {
            if seen.insert(card.key).inserted { items.append(PlannedItem(card: card)) }
        }
        return items
    }

    /// A wrong answer to the item at `index`: the card, as it is after the
    /// answer, goes to the end once.
    static func requeue(_ plan: [PlannedItem], wrongAt index: Int, card: CardState) -> [PlannedItem] {
        guard plan.indices.contains(index), !plan[index].isRetry else { return plan }
        return plan + [PlannedItem(card: card, isRetry: true)]
    }
}
