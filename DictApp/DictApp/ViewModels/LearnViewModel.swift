// LearnViewModel.swift
// The Learn tab (0131-learning.md, #158): the pair picker, the Learn home
// and the interim My words list. The runs come with #159 and #161.

import Foundation

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
