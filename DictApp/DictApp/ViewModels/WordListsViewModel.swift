// WordListsViewModel.swift
// Word lists (0130-word-lists.md, #154): the Lists screen, New words from
// and a list's screen. Only the lists of learned languages show (0131).
// Built-in lists are those of the installed packs: a pack that is not
// installed reads as empty, and its lists come back, still checked, when it
// is installed again (0237). The checked lists are
// `SettingsService.learningListIDs`. The SQL is in `DatabaseService`.
// Import (#155): `ListImportViewModel`, over the pure `ListText` parser.

import Combine
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

/// A list's progress in one language (0166, "Lists"; 0130, "For E4 and
/// E10", item 8): `ListProgress.of` over E3's keys of the list and the
/// language's word states (`wordStates(lang:)`). My words keeps only its
/// keys of `lang`. The statistics screen's Lists block reads it; E3's list
/// rows (#154) take the same.
struct ListProgressReader: Sendable {
    let db: DatabaseService

    func progress(of id: WordListID, lang: String,
                  states: [WordKey: WordLearningState]) async throws -> ListProgress {
        let keys = try await db.wordListItems(id).map(\.key).filter { $0.lang == lang }
        return ListProgress.of(items: keys, states: states)
    }
}

// MARK: - Lists screen and New words from

/// The Lists screen and New words from: the lists of the learned languages
/// in sections, each with its progress, and the checked set, whose
/// checkmarks and "Learning" badges they show. A tap on New words from
/// checks or unchecks a list; the next new word picked follows (E4).
@MainActor
final class WordListsViewModel: ObservableObject {
    @Published private(set) var sections: [WordListSection] = []
    /// `learning_lists`, hidden lists of stopped languages included.
    @Published private(set) var checked: Set<WordListID> = []
    /// Each shown list's progress (0166); a list without one hides its bar.
    @Published private(set) var progress: [WordListID: ListProgress] = [:]
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private var packChanges: AnyCancellable?

    init(db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil) {
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        // 0237: a pack installed or removed while the screen is open brings
        // its lists or takes them away.
        packChanges = NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.load() }
            }
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

    /// The lists, then their progress bars, which take a read per list.
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
        do {
            progress = try await Self.progress(of: sections.flatMap(\.lists), myWordsLanguage: languages.chosen, db: db)
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// The progress of each of `lists` in its language (0166): a list's
    /// words of its language; My words', those of `myWordsLanguage`, the
    /// language chosen on the Learn home (none without one). One read of
    /// the word states per language.
    static func progress(of lists: [WordList], myWordsLanguage: String?,
                         db: DatabaseService) async throws -> [WordListID: ListProgress] {
        let reader = ListProgressReader(db: db)
        var states: [String: [WordKey: WordLearningState]] = [:]
        var result: [WordListID: ListProgress] = [:]
        for list in lists {
            guard let lang = list.kind == .myWords ? myWordsLanguage : list.lang else { continue }
            if states[lang] == nil {
                states[lang] = try await db.wordStates(lang: lang)
            }
            result[list.id] = try await reader.progress(of: list.id, lang: lang, states: states[lang] ?? [:])
        }
        return result
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

    /// The progress bar as VoiceOver reads it: "1 learned · 5 learning ·
    /// 1,451 new", in the in-app language.
    nonisolated static func progressText(_ progress: ListProgress, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        return [
            String(localized: "stats.list.learned \(progress.learned)", bundle: bundle, locale: locale),
            String(localized: "stats.list.learning \(progress.learning)", bundle: bundle, locale: locale),
            String(localized: "stats.list.new \(progress.new)", bundle: bundle, locale: locale),
        ].joined(separator: " · ")
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
    /// Where the list's words find their meanings and Definitions
    /// (`LearningLanguageService.sourceOrder`), for the pair's meanings
    /// language (nil for Other); read on load.
    private var meaningsLang: String?
    private var sourceOrder: [String]?
    private var cancellables: Set<AnyCancellable> = []

    init(list: WordList, db: DatabaseService = .shared, settings: SettingsService = .shared,
         languages: LearningLanguageService? = nil) {
        self.list = list
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        guard list.kind == .myWords else { return }
        // #245: a pack installed or removed resolves its My words rows, or
        // puts them back to waiting.
        NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.load() }
            }
            .store(in: &cancellables)
    }

    /// The words shown; the list's own count until they load.
    var count: Int {
        guard isLoaded else { return list.count }
        return list.kind == .myWords ? myWords.count : sections.reduce(0) { $0 + $1.rows.count }
    }

    /// "Learn this list" is for every list but My words.
    var canLearn: Bool { list.kind != .myWords }

    /// The words at once, each with its part of speech (on the first load;
    /// a reload keeps the meanings shown); then one batch of meanings in the
    /// pair's meanings language (`meanings(of:)`, 0131's rules 1 to 3), for
    /// linked and standalone words alike, so a list's translation shows only
    /// when it is in that language (or the list is an import). A word
    /// without a meaning keeps its part of speech.
    func load() async {
        isChecked = settings.learningListIDs.contains(list.id)
        do {
            if list.kind == .myWords {
                myWords = try await db.myWordsEntries()
                isLoaded = true
            } else {
                let items = try await db.wordListItems(list.id)
                if sections.isEmpty {
                    sections = Self.sections(items, meanings: [:])
                }
                isLoaded = true
                let meaningsLang = try await languages.pair(for: list.lang)?.meaningsLang
                let order = try await languages.sourceOrder(lang: list.lang, meaningsLang: meaningsLang)
                self.meaningsLang = meaningsLang
                sourceOrder = order
                let meanings = try await db.meanings(of: items.map(MeaningQuery.init), lang: list.lang,
                                                     meaningsLang: meaningsLang, sourceOrder: order)
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
            let order: [String]
            if let sourceOrder {
                order = sourceOrder
            } else {
                order = try await languages.sourceOrder(lang: item.key.lang, meaningsLang: meaningsLang)
            }
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
            try await db.stopLearning(row.entry.map { EntryKey($0) } ?? row.key)
            myWords = try await db.myWordsEntries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

extension MeaningQuery {
    /// A list word's query (0131, "Meanings"): its headword, else its term,
    /// with the list's translation and its language.
    init(_ item: WordListItem) {
        self.init(key: item.key, lookup: item.headword ?? item.term, translation: item.translation,
                  translationLang: item.translationLang, partOfSpeech: item.partOfSpeech)
    }
}

// MARK: - Import (#155)

/// Import (0130, "Import"): a file (CSV, TSV or TXT) or pasted text parsed
/// by `ListText` into a preview (its name, language, delimiter and columns,
/// "1,457 words · 39 merged · 0 rows with errors", the first words and the
/// broken rows), then saved as a user list linked like the built-in lists.
/// A list of a language not learned asks "Learn %@ via %@?" first (0131).
@MainActor
final class ListImportViewModel: ObservableObject {
    /// What Import asks for a language not learned (0131, as Learn on a word).
    enum Question: Equatable {
        /// "Learn Spanish via English?": the language's pair.
        case pair(LearningPair)
        /// "Learn lists in other languages?": Other (`und`), without a pair.
        case other
    }

    /// Why a file or a paste gives no preview.
    enum Failure: Equatable {
        /// "Save the file as UTF-8 and try again".
        case encoding
        /// Over 20,000 rows or 10 MB.
        case tooBig
        /// A file that could not be read.
        case unreadable(String)
    }

    /// The saved list's numbers: "Imported %d words, %d found in the dictionaries".
    struct Outcome: Equatable {
        let id: WordListID
        let words: Int
        let linked: Int
    }

    /// The languages the preview offers, Other last.
    static let languages = ["ell", "eng", "spa", "rus", "arb", "und"]

    #if DEBUG
    /// `-importListFixture <path>` (UI tests): "Import a file" reads this
    /// file instead of opening the file picker.
    static var fixtureURL: URL?
    #endif

    @Published private(set) var preview: ListImportPreview?
    /// The list's name: the file's name, or "Pasted list"; editable.
    @Published var name = ""
    @Published private(set) var language = "und"
    @Published private(set) var delimiter = ListText.Delimiter.comma
    /// The paste box.
    @Published var pastedText = ""
    /// The alert Import shows; nil when none is shown.
    @Published var question: Question?
    @Published private(set) var failure: Failure?
    @Published private(set) var outcome: Outcome?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let languages: LearningLanguageService
    /// The text the preview was parsed from, and where it came from.
    private var text = ""
    private var origin = ListText.Origin.file
    /// Drops a preview a later change of language or delimiter replaced.
    private var generation = 0

    init(db: DatabaseService = .shared, languages: LearningLanguageService? = nil) {
        self.db = db
        self.languages = languages ?? .shared
    }

    /// The delimiter picker's choices: tab, semicolon, comma, and an Anki
    /// file's own.
    var delimiterChoices: [ListText.Delimiter] {
        ListText.Delimiter.choices.contains(delimiter) ? ListText.Delimiter.choices
            : ListText.Delimiter.choices + [delimiter]
    }

    /// Import is enabled with words to save and a name.
    var canImport: Bool {
        guard let preview, outcome == nil, !isWorking else { return false }
        return !preview.words.isEmpty && !trimmedName.isEmpty
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Reads the file at `url` (a file picker's security-scoped URL) and
    /// opens its preview, named after the file. False, with `failure`, when
    /// it is too big, not UTF-8 or UTF-16 with a BOM, or unreadable.
    func open(fileAt url: URL) async -> Bool {
        let text: String
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ListText.maxBytes {
                throw ListText.Failure.tooBig
            }
            text = try ListText.text(of: Data(contentsOf: url))
        } catch {
            failure = Self.failure(error)
            return false
        }
        return await open(text: text, origin: .file, name: url.deletingPathExtension().lastPathComponent)
    }

    /// Opens the preview of the paste box, named `name` ("Pasted list").
    func openPasted(name: String) async -> Bool {
        // 0130, Limits: 10 MB per import, as for a file.
        guard pastedText.utf8.count <= ListText.maxBytes else {
            failure = .tooBig
            return false
        }
        return await open(text: pastedText, origin: .paste, name: name)
    }

    /// A delimiter chosen in the preview: the text is parsed again.
    func setDelimiter(_ delimiter: ListText.Delimiter) async {
        guard delimiter != self.delimiter else { return }
        self.delimiter = delimiter
        do {
            try await prepare(try await Self.parsed(text, delimiter: delimiter, origin: origin))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A language chosen in the preview: the words are linked again.
    func setLanguage(_ language: String) async {
        guard language != self.language, let parse = preview?.parse else { return }
        self.language = language
        do {
            try await prepare(parse)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Import: saves the list when its language is learned; otherwise asks
    /// `question` first (0130, Kirill 2026-11-04).
    func confirm() async {
        guard canImport, let preview else { return }
        guard !languages.isLearned(preview.lang) else {
            await save()
            return
        }
        do {
            question = try await languages.pair(for: preview.lang).map(Question.pair) ?? .other
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The answer to `question`: Yes learns the pair (or Other alone), as
    /// the picker does, then saves; No saves the list, hidden until its
    /// language is learned.
    func answer(_ question: Question, yes: Bool) async {
        self.question = nil
        guard let preview else { return }
        if yes {
            do {
                switch question {
                case let .pair(pair): try await languages.learn(pair)
                case .other: try await languages.learn(language: preview.lang)
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        await save()
    }

    private func save() async {
        guard let preview, outcome == nil else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let id = try await db.saveUserList(preview, title: trimmedName)
            outcome = Outcome(id: id, words: preview.words.count, linked: preview.linkedCount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Parses `text` with its delimiter detected, guesses its language from
    /// its terms' script and links its words.
    private func open(text: String, origin: ListText.Origin, name: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let parse = try await Self.parsed(text, delimiter: nil, origin: origin)
            self.text = text
            self.origin = origin
            self.name = name
            delimiter = parse.delimiter
            language = ListText.guessLanguage(parse.words)
            preview = nil
            outcome = nil
            failure = nil
            try await prepare(parse)
            return true
        } catch {
            failure = Self.failure(error)
            return false
        }
    }

    /// The preview of `parse` in the current language.
    private func prepare(_ parse: ListText.Result) async throws {
        generation += 1
        let current = generation
        let preview = try await db.prepareListImport(parse, lang: language)
        if current == generation { self.preview = preview }
    }

    /// `ListText.parse` off the main actor.
    private nonisolated static func parsed(_ text: String, delimiter: ListText.Delimiter?,
                                           origin: ListText.Origin) async throws -> ListText.Result {
        try await Task.detached(priority: .userInitiated) {
            try ListText.parse(text, delimiter: delimiter, origin: origin)
        }.value
    }

    private static func failure(_ error: any Error) -> Failure {
        switch error as? ListText.Failure {
        case .encoding?: return .encoding
        case .tooBig?: return .tooBig
        case nil: return .unreadable(error.localizedDescription)
        }
    }

    // MARK: Texts

    /// "1,457 words · 39 merged · 0 rows with errors", in the in-app language.
    nonisolated static func summary(_ preview: ListImportPreview, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        return mark(locale) + [
            String(localized: "wordLists.count \(preview.words.count)", bundle: bundle, locale: locale),
            String(localized: "listImport.merged \(preview.parse.merged)", bundle: bundle, locale: locale),
            String(localized: "listImport.errors \(preview.parse.broken.count)", bundle: bundle, locale: locale),
        ].joined(separator: " · ")
    }

    /// The columns found: "Term · Translation · Level · Endings".
    nonisolated static func columnsText(_ columns: [ListText.Column], locale: Locale) -> String {
        mark(locale) + columns.map { WordListsViewModel.localized("listImport.column." + $0.rawValue, locale: locale) }
            .joined(separator: " · ")
    }

    /// "Imported 1,457 words, 1,371 found in the dictionaries".
    nonisolated static func outcomeText(_ outcome: Outcome, locale: Locale) -> String {
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        let linked = outcome.linked.formatted(.number.locale(locale))
        return String(localized: "listImport.result \(outcome.words) \(linked)", bundle: bundle, locale: locale)
    }

    /// A delimiter's name: Tab, Semicolon, Comma, Space, or the character.
    nonisolated static func delimiterName(_ delimiter: ListText.Delimiter, locale: Locale) -> String {
        switch delimiter {
        case .tab: return WordListsViewModel.localized("listImport.delimiter.tab", locale: locale)
        case .semicolon: return WordListsViewModel.localized("listImport.delimiter.semicolon", locale: locale)
        case .comma: return WordListsViewModel.localized("listImport.delimiter.comma", locale: locale)
        case .space: return WordListsViewModel.localized("listImport.delimiter.space", locale: locale)
        default: return "\u{201C}" + String(Character(delimiter.scalar)) + "\u{201D}"
        }
    }

    /// Why a row is skipped, as the preview reads it.
    nonisolated static func problemText(_ problem: ListText.Problem, locale: Locale) -> String {
        WordListsViewModel.localized("listImport.error." + problem.rawValue, locale: locale)
    }

    /// U+200F before a composed text in a right-to-left language (#119).
    private nonisolated static func mark(_ locale: Locale) -> String {
        locale.language.characterDirection == .rightToLeft ? "\u{200F}" : ""
    }
}
