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
