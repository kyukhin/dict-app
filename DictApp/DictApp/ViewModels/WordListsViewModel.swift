// WordListsViewModel.swift
// Word lists (0130-word-lists.md, #154): the Lists screen, New words from
// and a list's screen. Only the lists of learned languages show (0131);
// the checked lists are `SettingsService.learningListIDs`. The SQL is in
// `DatabaseService`; #155 adds `ListImportViewModel` here.

import Foundation

/// A section of the Lists screen: one language's built-in lists, or My
/// lists (My words, then the imported lists).
struct WordListSection: Identifiable, Hashable {
    enum Kind: Hashable {
        case language(String)
        case myLists
    }

    let kind: Kind
    let lists: [WordList]

    var id: Kind { kind }
}

// MARK: - Lists screen and New words from

/// The Lists screen and New words from: the lists of the learned languages
/// in sections, and the checked set, whose checkmarks and "Learning" badges
/// they show. A tap on New words from checks or unchecks a list; the next
/// new word picked follows (E4).
@MainActor
final class WordListsViewModel: ObservableObject {
    @Published private(set) var sections: [WordListSection] = []
    /// `learning_lists`, hidden lists of stopped languages included.
    @Published private(set) var checked: Set<WordListID> = []
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService

    init(db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil) {
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
    }

    /// New words from's rows: the Lists screen's sections without My words,
    /// whose words are learned at once (E4).
    var newWordsFromSections: [WordListSection] {
        sections.compactMap { section in
            let lists = section.lists.filter { $0.kind != .myWords }
            return lists.isEmpty ? nil : WordListSection(kind: section.kind, lists: lists)
        }
    }

    /// Whether a list New words from shows is checked; else its footer
    /// reads "No list checked."
    var hasCheckedList: Bool {
        newWordsFromSections.contains { section in section.lists.contains { checked.contains($0.id) } }
    }

    func load() async {
        do {
            sections = Self.sections(try await db.wordLists(), learned: languages.learned,
                                     uiLanguage: LearningPairs.code(ofUILanguage: languages.uiLanguage()))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        checked = settings.learningListIDs
        isLoaded = true
    }

    /// Re-reads the checked set: a list's "Learn this list" changed it.
    func refreshChecked() {
        checked = settings.learningListIDs
    }

    /// New words from's tap: checks or unchecks list `id`.
    func toggleChecked(_ id: WordListID) {
        checked = Self.toggle(id, in: settings)
    }

    /// The Lists screen's swipe, after its alert: an imported list goes with
    /// its words and its checkmark. Its words' cards and progress stay.
    /// Built-in lists and My words cannot be deleted.
    func delete(_ list: WordList) async {
        guard list.kind == .user else { return }
        do {
            try await db.deleteUserList(list.id)
            settings.learningListIDs.remove(list.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await load()
    }

    /// Checks `id` when it is not, else unchecks it; returns the new set.
    static func toggle(_ id: WordListID, in settings: SettingsService) -> Set<WordListID> {
        var ids = settings.learningListIDs
        if ids.remove(id) == nil {
            ids.insert(id)
        }
        settings.learningListIDs = ids
        return ids
    }

    /// The sections of `lists` (`wordLists()`'s order) for the languages of
    /// `learned` (0130, "Lists screen"): each language's built-in lists by
    /// level, Greek's before English's but the UI language's (ISO 639-3)
    /// last; then My lists: My words, then the imported lists of learned
    /// languages, newest first.
    nonisolated static func sections(_ lists: [WordList], learned: [String], uiLanguage: String) -> [WordListSection] {
        let learned = Set(learned)
        let builtIn = Dictionary(grouping: lists.filter { $0.kind == .builtIn && learned.contains($0.lang) }, by: \.lang)
        let order = builtIn.keys.sorted { a, b in
            func rank(_ lang: String) -> (Int, Int, String) {
                (lang == uiLanguage ? 1 : 0, languageOrder.firstIndex(of: lang) ?? languageOrder.count, lang)
            }
            return rank(a) < rank(b)
        }
        let myLists = lists.filter { $0.kind == .myWords } + lists.filter { $0.kind == .user && learned.contains($0.lang) }
        return order.map { WordListSection(kind: .language($0), lists: builtIn[$0] ?? []) }
            + [WordListSection(kind: .myLists, lists: myLists)]
    }

    /// The languages with built-in lists in the order their sections take.
    private nonisolated static let languageOrder = ["ell", "eng"]

    // MARK: Titles

    /// A list's title in the in-app language (`locale`): "Greek A1"
    /// (`wordLists.listTitle`, the level in the UI's letters, Ελληνικά Α1),
    /// "My words", or an import's own name.
    nonisolated static func title(of list: WordList, locale: Locale) -> String {
        switch list.kind {
        case .builtIn:
            return String(format: localized("wordLists.listTitle %@ %@", locale: locale),
                          LearnViewModel.languageName(list.lang, locale: locale), levelName(list.level, locale: locale))
        case .myWords:
            return localized("wordLists.myWords", locale: locale)
        case .user:
            return list.title
        }
    }

    /// A CEFR level as the UI writes it (`wordLists.level.A1`: Greek writes
    /// Α1 … Γ2); an import's other level names as they are.
    nonisolated static func levelName(_ level: String, locale: Locale) -> String {
        guard cefrLevels.contains(level) else { return level }
        return localized("wordLists.level." + level, locale: locale)
    }

    nonisolated static let cefrLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    /// A section's header: the language's name, or "My lists".
    nonisolated static func sectionTitle(_ kind: WordListSection.Kind, locale: Locale) -> String {
        switch kind {
        case let .language(lang): return LearnViewModel.languageName(lang, locale: locale)
        case .myLists: return localized("wordLists.section.myLists", locale: locale)
        }
    }

    /// `key` from the in-app language's table (`locale`), not the device's.
    nonisolated static func localized(_ key: String, locale: Locale) -> String {
        SettingsViewModel.localizedBundle(for: locale).localizedString(forKey: key, value: key, table: nil)
    }
}

// MARK: - A list's screen

/// A list's screen: its words alphabetical, one section per level when it
/// has several (A1 first, words without a level last), each with its meaning
/// in the meanings language of the list language's pair (0131, "Meanings"),
/// and "Learn this list". My words shows its entries' snippets instead,
/// newest first, and its swipe is Stop learning.
@MainActor
final class WordListViewModel: ObservableObject {
    /// A word and what its row shows under it.
    struct Row: Identifiable, Hashable {
        let item: WordListItem
        /// In the pair's meanings language, else the part of speech; may be
        /// empty.
        let meaning: String

        var id: WordKey { item.key }
    }

    /// The words of one level (`levelOrder` 0: none).
    struct LevelSection: Identifiable, Hashable {
        let level: String
        let levelOrder: Int
        let rows: [Row]

        var id: Int { levelOrder }
    }

    let list: WordList
    @Published private(set) var sections: [LevelSection] = []
    /// My words' rows, newest first.
    @Published private(set) var myWords: [MyWordsEntry] = []
    /// The list is checked in New words from.
    @Published private(set) var isChecked = false
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    /// The list language's pair's meanings language; nil for Other.
    private var meaningsLang: String?

    init(list: WordList, db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil) {
        self.list = list
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
    }

    /// The words shown; the list's own count until they load.
    var count: Int {
        guard isLoaded else { return list.count }
        return list.kind == .myWords ? myWords.count : sections.reduce(0) { $0 + $1.rows.count }
    }

    /// "Learn this list" is for every list but My words.
    var canLearn: Bool { list.kind != .myWords }

    func load() async {
        isChecked = settings.learningListIDs.contains(list.id)
        do {
            if list.kind == .myWords {
                myWords = try await db.myWordsEntries()
            } else {
                let items = try await db.wordListItems(list.id)
                meaningsLang = try await languages.pair(for: list.lang)?.meaningsLang
                // ponytail: rule 1 only; on the rebase onto #159 the rows get
                // the pair dictionary's first sense from `db.meanings(of:lang:
                // meaningsLang:sourceOrder:)`, one batch after this, keeping
                // the part of speech while it loads.
                let meanings = Dictionary(items.compactMap { item in
                    Self.listMeaning(item, meaningsLang: meaningsLang).map { (item.key, $0) }
                }, uniquingKeysWith: { first, _ in first })
                sections = Self.sections(items, meanings: meanings)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// "Learn this list": checks the list in New words from, or unchecks it.
    func toggleLearning() {
        isChecked = WordListsViewModel.toggle(list.id, in: settings).contains(list.id)
    }

    /// The Definition a word opens (0130): its headword in the first of the
    /// pair's dictionaries in Dictionary Order, enabled ones first, else in
    /// the first dictionary of its language. nil for a standalone word.
    func entry(for item: WordListItem) async -> DictionaryEntry? {
        guard item.headword != nil else { return nil }
        do {
            let order = try await languages.sourceOrder(lang: item.key.lang, meaningsLang: meaningsLang)
            return try await db.entry(for: item, sourceOrder: order)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// My words' swipe is Stop learning (0131): every My words row of the
    /// word leaves, whatever its dictionary, and its cards are paused.
    func stopLearning(_ row: MyWordsEntry) async {
        do {
            try await db.stopLearning(EntryKey(row.entry))
            myWords = try await db.myWordsEntries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rule 1 of 0131's "Meanings": the list's translation when it is in the
    /// meanings language, or an import's (`translationLang` empty), which
    /// shows in every pair; with no pair (Other), any translation. nil: the
    /// meaning comes from the pair's dictionary.
    nonisolated static func listMeaning(_ item: WordListItem, meaningsLang: String?) -> String? {
        let translation = item.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return nil }
        guard let meaningsLang, !item.translationLang.isEmpty else { return translation }
        return item.translationLang == meaningsLang ? translation : nil
    }

    /// `items` (alphabetical) by level: A1 … C2, an import's other levels in
    /// order, words without a level last; each row with its meaning from
    /// `meanings`, else its part of speech.
    nonisolated static func sections(_ items: [WordListItem], meanings: [WordKey: String]) -> [LevelSection] {
        let byLevel = Dictionary(grouping: items, by: \.levelOrder)
        return byLevel.keys.sorted { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }.map { order in
            let items = byLevel[order] ?? []
            return LevelSection(level: items.first?.level ?? "", levelOrder: order, rows: items.map { item in
                Row(item: item, meaning: meanings[item.key] ?? item.partOfSpeech)
            })
        }
    }
}
