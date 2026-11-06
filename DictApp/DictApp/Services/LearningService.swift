// LearningService.swift
// Learning words with spaced repetition (0131-learning.md): the services
// around the store. The clock (#157), the languages (#158), the feedback
// and the runs' launch options (#159), the new words a run starts (#161).

import AVFoundation
import Foundation
import SwiftUI

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

    /// Where `lang`'s words find their meanings (`LearningPairs.sourceOrder`):
    /// the dictionaries from `lang` into `meaningsLang`, the pair's, first,
    /// then the rest of Dictionary Order, enabled ones first in each part.
    /// Until an order is stored, Dictionary Order is the default the
    /// Settings screen derives (#74, #92). Without a pair (`meaningsLang`
    /// nil, Other), Dictionary Order, enabled first.
    func sourceOrder(lang: String, meaningsLang: String?) async throws -> [String] {
        let pairs = try await db.learningPairs()
        let order: [String]
        if let stored = settings.dictionaryOrder {
            order = stored
        } else {
            let sources = try await db.fetchSourceStats().map(\.source)
            order = DictionaryGrouping.groupedOrder(DictionaryDefaults.defaultOrder(forLanguageCode: uiLanguage(),
                                                                                    sources: sources))
        }
        let enabled = settings.enabledSources
        guard let meaningsLang else {
            func isOn(_ source: String) -> Bool { enabled?.contains(source) ?? true }
            return order.filter(isOn) + order.filter { !isOn($0) }
        }
        // A limited pair's dictionaries are those of (lang, meanings).
        return LearningPairs.sourceOrder(pair: LearningPair(lang: lang, via: meaningsLang), pairSources: pairs,
                                         dictionaryOrder: order, enabled: enabled)
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

// MARK: - New words (#161)

/// The new words a run starts today in one language (0131, "New words"), up
/// to the daily limit (`learning_new_per_day`) minus the words of the
/// language started today:
/// 1. the words in learning never answered, not paused, oldest first: My
///    words, and list words an unfinished run picked (`newPool`);
/// 2. then the checked lists' next words (E3's `nextNewWords`, in the
///    `learning_new_order` order, every key in learning excluded, paused
///    ones too), which are not in learning yet.
///
/// A word without a meaning in the pair takes no slot (Meanings, rule 4):
/// the pick reads past it, in pages for the lists, and a skipped list word
/// is not picked, so it gets no row. The Learn home counts the pick; a run
/// introduces its list words (`DatabaseService.introduce`).
@MainActor
struct NewWordPicker {
    struct Pick: Equatable {
        /// In learning, never answered.
        var pool: [LearnWord] = []
        /// Not in learning yet, in E3's order.
        var lists: [WordListItem] = []

        var count: Int { pool.count + lists.count }
    }

    /// The lists' words are read in pages of at least this many.
    static let pageSize = 10

    let db: DatabaseService
    let settings: SettingsService

    /// New words left today in `lang`: the daily limit minus the words
    /// started today, never below 0. The limit is per language.
    func left(lang: String, today: LearnDay) async throws -> Int {
        max(0, settings.learningNewPerDay - (try await db.startedCount(on: today, lang: lang)))
    }

    /// At most `left(lang:today:)` new words, and at most `limit`, each with
    /// a meaning in `meaningsLang` (nil: Other, rule 3) looked up through
    /// `sourceOrder`, the pair's dictionaries first.
    func pick(lang: String, meaningsLang: String?, sourceOrder: [String], today: LearnDay,
              limit: Int = .max) async throws -> Pick {
        let wanted = min(try await left(lang: lang, today: today), max(limit, 0))
        guard wanted > 0 else { return Pick() }
        var pick = Pick()
        let pool = try await db.newPool(lang: lang, limit: .max)
        let poolMeanings = try await db.meanings(of: pool.map(MeaningQuery.init), lang: lang,
                                                 meaningsLang: meaningsLang, sourceOrder: sourceOrder)
        pick.pool = Array(pool.filter { poolMeanings[$0.key] != nil }.prefix(wanted))
        let lists = settings.learningListIDs
        guard pick.count < wanted, !lists.isEmpty else { return pick }
        let enrolled = try await db.enrolledKeys()
        let order = settings.learningNewOrder
        var read = 0
        while pick.count < wanted {
            let count = read + max(wanted - pick.count, Self.pageSize)
            let items = try await db.nextNewWords(in: lang, from: lists, count: count, excluding: enrolled, order: order)
            let page = Array(items.dropFirst(read))
            let meaningful = try await withMeaning(page, lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder)
            pick.lists += page.filter { meaningful.contains($0.key) }.prefix(wanted - pick.count)
            guard items.count == count else { break }
            read = items.count
        }
        return pick
    }

    /// The keys of `items` with a meaning in the pair, as `meanings(of:)`
    /// finds it once they are in learning: the list's translation, else the
    /// headword (or term) in the pair's dictionaries; for Other, the
    /// translation, else the entry the word will open.
    private func withMeaning(_ items: [WordListItem], lang: String, meaningsLang: String?,
                             sourceOrder: [String]) async throws -> Set<WordKey> {
        var queries: [MeaningQuery] = []
        for item in items {
            var entry: EntryKey?
            if meaningsLang == nil, Gloss.listMeaning(translation: item.translation, translationLang: item.translationLang,
                                                      meaningsLang: nil) == nil {
                entry = try await db.entry(for: item, sourceOrder: sourceOrder).map(EntryKey.init)
            }
            queries.append(MeaningQuery(key: item.key, lookup: item.headword ?? item.term, translation: item.translation,
                                        translationLang: item.translationLang, entry: entry))
        }
        return Set(try await db.meanings(of: queries, lang: lang, meaningsLang: meaningsLang, sourceOrder: sourceOrder).keys)
    }
}

// MARK: - Feedback (#159)

/// The two feedback sounds.
enum FeedbackSound: String, CaseIterable, Sendable {
    /// Two rising notes.
    case right
    /// One low note.
    case wrong
}

/// Where the feedback sounds go: `TonePlayer` in the app, a recorder in
/// tests, which records what would have played.
@MainActor
protocol FeedbackSink: AnyObject {
    func play(_ sound: FeedbackSound)
}

/// Plays the feedback sounds and decides on the haptics, from the Sounds
/// and Haptics settings (0131, "Feedback"). E5's drill uses it too.
@MainActor
final class FeedbackPlayer {
    static let shared = FeedbackPlayer()

    private let settings: SettingsService
    private let sink: any FeedbackSink

    init(settings: SettingsService = .shared, sink: (any FeedbackSink)? = nil) {
        self.settings = settings
        self.sink = sink ?? TonePlayer()
    }

    /// The sound of an answer, unless Sounds is off. `accent` counts as right.
    func play(_ outcome: Outcome) {
        guard settings.learningSounds else { return }
        sink.play(outcome.isRight ? .right : .wrong)
    }

    /// The haptic of an answer for `.sensoryFeedback`; nil when Haptics is off.
    func haptic(for outcome: Outcome) -> SensoryFeedback? {
        guard settings.learningHaptics else { return nil }
        return outcome.isRight ? .success : .error
    }
}

/// Plays two short tones generated in code as WAV data, so there is no
/// sound file to license. The audio session is `.ambient`, set once: the
/// silent switch mutes the tones and the user's music keeps playing.
@MainActor
final class TonePlayer: FeedbackSink {
    private var players: [FeedbackSound: AVAudioPlayer] = [:]
    private var isSessionSet = false

    func play(_ sound: FeedbackSound) {
        if !isSessionSet {
            isSessionSet = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
        }
        if players[sound] == nil {
            players[sound] = try? AVAudioPlayer(data: Self.wav(sound))
            players[sound]?.prepareToPlay()
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    /// Right: two rising notes, G5 then C6, 0.1 s each. Wrong: one low
    /// note, A3, 0.2 s.
    static func wav(_ sound: FeedbackSound) -> Data {
        switch sound {
        case .right: return wav(notes: [(783.99, 0.1), (1046.5, 0.1)])
        case .wrong: return wav(notes: [(220, 0.2)])
        }
    }

    /// 16-bit mono PCM at 44.1 kHz: sine notes, each with a 5 ms attack
    /// and an exponential decay, so they do not click.
    static func wav(notes: [(frequency: Double, seconds: Double)], volume: Double = 0.3) -> Data {
        let rate = 44_100
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.seconds * Double(rate))
            for n in 0..<count {
                let t = Double(n) / Double(rate)
                let envelope = min(t / 0.005, 1) * exp(-4 * t / note.seconds)
                samples.append(Int16(sin(2 * .pi * note.frequency * t) * envelope * volume * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        samples.forEach { append($0) }
        return data
    }
}

// MARK: - Launch options (#159)

/// The runs' DEBUG launch arguments (0131, Test seams); release builds
/// ignore them.
enum LearningLaunchOptions {
    /// `-learningSeed <n>`: fixes the option order and the distractors.
    static var seed: UInt64? {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-learningSeed"), arguments.indices.contains(index + 1) else { return nil }
        return UInt64(arguments[index + 1])
        #else
        return nil
        #endif
    }

    /// `-learningAnswerHints`: the right option gets the accessibility value
    /// `answer`, so a UI test can answer right or wrong on purpose.
    static var answerHints: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-learningAnswerHints")
        #else
        return false
        #endif
    }
}
