// LearningService.swift
// Learning words with spaced repetition (0131-learning.md): the services
// around the store. The clock (#157).

import Foundation

// MARK: - Clock (#157)

/// The learning day of `now`. A day starts at 4 AM local time, as in Anki:
/// an answer at 00:30 counts for the day before (Kirill, 2026-11-03).
/// Injected into the view models; the store takes `today` as an argument.
struct LearningClock: Sendable {
    /// The hour a learning day starts at.
    static let dayStartHour = 4

    var now: @Sendable () -> Date = { Date() }
    /// Gregorian, in the current time zone.
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    var today: LearnDay { Self.day(at: now(), calendar: calendar) }

    /// The local date of `date`, or the day before when its local hour is
    /// under 4. Calendar arithmetic, never "minus 4 hours": on a
    /// daylight-saving change day the two differ for an hour.
    static func day(at date: Date, calendar: Calendar) -> LearnDay {
        guard calendar.component(.hour, from: date) < dayStartHour,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) else {
            return LearnDay(date: date, calendar: calendar)
        }
        return LearnDay(date: dayBefore, calendar: calendar)
    }
}

// MARK: - Languages and pairs (#158)

/// 0237's side of choosing a pair (0237, "For E3 and E4"): which languages
/// have built-in lists, what a pair still has to download, and its install.
/// A protocol so tests inject a fake. The offered pairs themselves are
/// `DatabaseService.learningPairs()`.
protocol PairPacksInstalling: Sendable {
    /// The languages with built-in lists (`PackCatalog.languages`, `hasBuiltInLists`).
    var languagesWithLists: Set<String> { get }
    /// The bytes of the pair's packs not installed yet
    /// (`CatalogPair.downloadSize(installed:)`); 0 when none is missing.
    func downloadSize(of pair: LearningPair) async -> Int64
    /// Installs the pair's missing packs (a limited pair's are its
    /// (lang, meanings) pair's); returns at once when none is missing.
    func installPair(lang: String, via: String) async throws
}

// ponytail: wired to PackService in #241/#242
/// Until #241: the catalogue's two languages with lists (the Greek lists
/// come in the Greek pack, the English lists in `eng-lists`); every
/// dictionary is in the bundle, so nothing to download or install.
struct PendingPairPacks: PairPacksInstalling {
    let languagesWithLists: Set<String> = ["ell", "eng"]
    func downloadSize(of pair: LearningPair) async -> Int64 { 0 }
    func installPair(lang: String, via: String) async throws {}
}

/// The learned languages (`learning_languages`) and their vias
/// (`learning_via`): choosing a pair, from the picker, from "Learn %@ via
/// %@?" on a word or from E3's import, changing a via and stopping a
/// language (#162). Learning a language is explicit (Kirill, 2026-11-03)
/// and goes through a pair (Kirill, 2026-11-04).
@MainActor
final class LearningLanguageService {
    static let shared = LearningLanguageService()

    let packs: any PairPacksInstalling
    /// The in-app language's code (`en`, `el`): the default via's first choice.
    let uiLanguage: @MainActor () -> String
    private let db: DatabaseService
    private let settings: SettingsService
    private let clock: LearningClock

    init(db: DatabaseService = .shared, settings: SettingsService = .shared,
         packs: any PairPacksInstalling = PendingPairPacks(), clock: LearningClock = LearningClock(),
         uiLanguage: @escaping @MainActor () -> String = { LocalizationManager.shared.currentLanguage.code }) {
        self.db = db
        self.settings = settings
        self.packs = packs
        self.clock = clock
        self.uiLanguage = uiLanguage
    }

    /// In the order chosen.
    var learned: [String] { settings.learningLanguages }

    func isLearned(_ lang: String) -> Bool { learned.contains(lang) }

    /// The language the Learn home shows, nil when none is learned.
    var chosen: String? {
        get { LearningLanguages.chosen(stored: settings.learningLanguage, learned: learned) }
        set { settings.learningLanguage = newValue }
    }

    /// The pair `lang` is learned through: its stored via while offered,
    /// else its default; nil for a language without a pair (Other).
    func pair(for lang: String) async throws -> LearningPair? {
        LearningPairs.pair(for: lang, stored: settings.learningVia, offered: try await db.learningPairs().keys,
                           uiLanguage: uiLanguage())
    }

    /// Chooses `pair`: its language appended to the learned languages
    /// (once) and made the chosen one, its via stored, its My words not in
    /// learning yet enrolled, and the install of the pair's missing packs
    /// started. Returns that install; the pair stays chosen if it fails.
    @discardableResult
    func learn(_ pair: LearningPair) async throws -> Task<Void, any Error> {
        settings.learningVia[pair.lang] = pair.via
        try await add(pair.lang)
        return install(pair.lang, via: pair.via)
    }

    /// Learn on a word, E3's import, E5's and E6's Practise, after their
    /// alert: `lang` through its pair (`pair(for:)`), or alone when it has
    /// none (Other), with nothing to install.
    @discardableResult
    func learn(language lang: String) async throws -> Task<Void, any Error>? {
        if let pair = try await pair(for: lang) {
            return try await learn(pair)
        }
        try await add(lang)
        return nil
    }

    /// #162: a learned language's new via, from the next question. Changes
    /// no data; installs the new pair's missing packs.
    @discardableResult
    func setVia(_ via: String, for lang: String) -> Task<Void, any Error> {
        settings.learningVia[lang] = via
        return install(lang, via: via)
    }

    /// Stop learning `lang`: it leaves the learned languages. Its cards, log,
    /// checked lists and via stay as they are, so choosing it again resumes.
    func stop(_ lang: String) {
        settings.learningLanguages = learned.filter { $0 != lang }
    }

    private func add(_ lang: String) async throws {
        if !isLearned(lang) {
            settings.learningLanguages = learned + [lang]
        }
        chosen = lang
        try await db.enrolMyWords(lang: lang, today: clock.today)
    }

    private func install(_ lang: String, via: String) -> Task<Void, any Error> {
        let packs = packs
        // ponytail: #241 shows the install's progress and Try again
        return Task { try await packs.installPair(lang: lang, via: via) }
    }
}
