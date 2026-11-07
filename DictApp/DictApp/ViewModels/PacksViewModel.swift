// PacksViewModel.swift
// The language packs on screen (Issue #243, docs/specs/0237-downloads.md,
// "Settings → Dictionaries" and "UI"): the rows of the Languages screen,
// the texts of each `PackState`, and the remove alert. `PackService` does
// the work and `PackStatusModel` publishes the states; nothing here touches
// a file or the network.

import Combine
import Foundation

// MARK: - Rows

/// One row of the Languages screen: the bundled English, or a pack.
struct LanguageRow: Identifiable, Equatable, Sendable {
    /// `eng` for the bundled English row, else the pack's id.
    let id: String
    /// nil for the bundled English row ("Included").
    let pack: PackID?
    /// "Greek", "English word lists".
    let name: String
    /// "4 dictionaries · word forms"; "WordNet" for English; nil when the
    /// pack has nothing to list yet.
    let contents: String?
    /// The asset to download and the installed file, in bytes.
    let downloadSize: Int64
    let installedSize: Int64
}

// MARK: - Texts

/// The texts of a pack's row and states (0237, "UI"), in the in-app
/// language (`locale`), never the device's. Pure.
enum PackTexts {
    /// Every language the screen names: English first, then the catalog's
    /// languages. `language.<code>.name` for the five UI languages.
    static func languageName(_ iso3: String, locale: Locale) -> String {
        SettingsViewModel.languageName(iso3: iso3, locale: locale)
    }

    /// A name inside a sentence ("Remove Greek?", "Удалить греческий?"):
    /// English keeps its capital, the other UI languages write it in lower
    /// case (Arabic has no case).
    static func inSentence(_ name: String, locale: Locale) -> String {
        locale.language.languageCode == .english ? name : name.lowercased(with: locale)
    }

    /// A row's name: the language's, or for a pack of word lists only (the
    /// English lists) "English word lists".
    static func name(of pack: CatalogPack, locale: Locale) -> String {
        let language = languageName(pack.lang, locale: locale)
        guard pack.kind == "lists" else { return language }
        return String(localized: "languages.lists \(inSentence(language, locale: locale))",
                      bundle: bundle(locale), locale: locale)
    }

    /// "6.9 MB": `ByteCountFormatter`'s file style, in the in-app locale.
    static func size(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// "3.1 of 6.9 MB": the bytes received in the unit of the total, with
    /// the file style's precision (whole kB, MB to one decimal, GB to two).
    static func progress(received: Int64, total: Int64, locale: Locale) -> String {
        let (divisor, digits): (Double, Int) = switch total {
        case 1_000_000_000...: (1e9, 2)
        case 1_000_000...: (1e6, 1)
        case 1_000...: (1e3, 0)
        default: (1, 0)
        }
        let part = (Double(min(received, total)) / divisor)
            .formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return String(localized: "languages.progress \(part) \(size(total, locale: locale))",
                      bundle: bundle(locale), locale: locale)
    }

    static func download(_ bytes: Int64, locale: Locale) -> String {
        String(localized: "languages.download \(size(bytes, locale: locale))", bundle: bundle(locale), locale: locale)
    }

    static func installed(_ bytes: Int64, locale: Locale) -> String {
        String(localized: "languages.installed \(size(bytes, locale: locale))", bundle: bundle(locale), locale: locale)
    }

    static func update(_ bytes: Int64, locale: Locale) -> String {
        String(localized: "languages.update \(size(bytes, locale: locale))", bundle: bundle(locale), locale: locale)
    }

    static func updateRequired(_ bytes: Int64, locale: Locale) -> String {
        String(localized: "languages.updateRequired \(size(bytes, locale: locale))",
               bundle: bundle(locale), locale: locale)
    }

    /// The reason shown in red (0237, "Offline and errors"); nil for a
    /// cancel, which shows no error. `name`: the row's name; `space`: the
    /// asset and the installed file, which a full disk must hold.
    static func error(_ error: PackError, name: String, space: Int64, locale: Locale) -> String? {
        let key: String
        switch error {
        case .offline: key = "pack.error.offline"
        case .stopped: key = "pack.error.stopped"
        case .unavailable: key = "pack.error.unavailable"
        case .damaged: key = "pack.error.damaged"
        case .cancelled: return nil
        case .noSpace:
            return String(localized: "pack.error.noSpace \(name) \(size(space, locale: locale))",
                          bundle: bundle(locale), locale: locale)
        }
        return SettingsViewModel.localizedString(key, locale: locale)
    }

    /// The progress bar of a pack in `state` (0237, "Settings →
    /// Dictionaries"): its fraction and "Waiting", "3.1 of 6.9 MB" or
    /// "Installing…"; nil when nothing runs.
    static func progressLine(_ state: PackState, locale: Locale) -> (fraction: Double, text: String)? {
        switch state {
        case .waiting:
            return (0, SettingsViewModel.localizedString("languages.waiting", locale: locale))
        case .downloading(let received, let total):
            return (total > 0 ? Double(received) / Double(total) : 0,
                    progress(received: received, total: total, locale: locale))
        case .installing:
            return (1, SettingsViewModel.localizedString("languages.installing", locale: locale))
        case .notInstalled, .installed, .updateAvailable, .updateRequired, .failed:
            return nil
        }
    }

    /// The first-launch sheet's button for the checked total: "Download 18.1 MB".
    static func welcomeDownload(_ bytes: Int64, locale: Locale) -> String {
        String(localized: "welcome.download \(size(bytes, locale: locale))", bundle: bundle(locale), locale: locale)
    }

    /// A sheet row's caption: what the pack holds, then its download size,
    /// "2 dictionaries · 6.9 MB". Right-to-left languages start with U+200F
    /// (#119).
    static func caption(_ row: LanguageRow, locale: Locale) -> String {
        let text = [row.contents, size(row.downloadSize, locale: locale)].compactMap { $0 }.joined(separator: " · ")
        return (locale.language.characterDirection == .rightToLeft ? "\u{200F}" : "") + text
    }

    /// "This word is in the Greek dictionaries." (0237, "Update from 1.x").
    static func notDownloadedMessage(_ pack: CatalogPack, locale: Locale) -> String {
        String(localized: "notDownloaded.message \(inSentence(languageName(pack.lang, locale: locale), locale: locale))",
               bundle: bundle(locale), locale: locale)
    }

    /// The Search hint, "Greek is not downloaded." (0237, "Offline and
    /// errors"); also the caption of a My words row waiting for its pack.
    static func notDownloadedSearch(_ pack: CatalogPack, locale: Locale) -> String {
        String(localized: "notDownloaded.search \(inSentence(languageName(pack.lang, locale: locale), locale: locale))",
               bundle: bundle(locale), locale: locale)
    }

    /// "Download Greek · 10.7 MB", the button of the "not downloaded" view
    /// and the Search hint.
    static func notDownloadedDownload(_ pack: CatalogPack, locale: Locale) -> String {
        let name = inSentence(languageName(pack.lang, locale: locale), locale: locale)
        return String(localized: "notDownloaded.download \(name) \(size(pack.size, locale: locale))",
                      bundle: bundle(locale), locale: locale)
    }

    /// "4 dictionaries · word forms · word lists", for what the pack holds.
    static func contents(dictionaries: Int, forms: Bool, lists: Bool, locale: Locale) -> String? {
        var parts: [String] = []
        if dictionaries > 0 {
            parts.append(String(localized: "languages.contents.dictionaries \(dictionaries)",
                                bundle: bundle(locale), locale: locale))
        }
        if forms {
            parts.append(SettingsViewModel.localizedString("languages.contents.forms", locale: locale))
        }
        if lists {
            parts.append(SettingsViewModel.localizedString("languages.contents.lists", locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func bundle(_ locale: Locale) -> Bundle {
        SettingsViewModel.localizedBundle(for: locale)
    }
}

// MARK: - The Languages screen

/// The Languages screen (Settings → Dictionaries → Languages): every
/// language the app knows, English first, then by name, each in its
/// `PackState`, with Download, Cancel, Update, Try again and Remove.
@MainActor
final class LanguagesViewModel: ObservableObject {
    /// The remove alert of a pack.
    struct Removal: Identifiable, Equatable {
        let pack: PackID
        /// "Remove Greek?"
        let title: String
        let message: String

        var id: String { pack.rawValue }
    }

    @Published private(set) var rows: [LanguageRow] = []
    /// The packs with a file, usable or not: what Remove can delete.
    @Published private(set) var installed: Set<PackID> = []
    /// The alert on screen, if any.
    @Published var removal: Removal?

    let status: PackStatusModel
    private let packs: PackService
    private let localization: LocalizationManager
    private let catalog: () -> PackCatalog
    /// E4's learned languages and their stored vias (0131).
    private let learning: @MainActor () -> (languages: [String], via: [String: String])
    private var cancellables: Set<AnyCancellable> = []

    /// `nil` status and localization: the shared ones, resolved on the main
    /// actor. `catalog`: `PackCatalog.shared`; `learning`: the settings'
    /// `learningLanguages` and `learningVia`. A test passes its own.
    init(packs: PackService = .shared, status: PackStatusModel? = nil,
         localization: LocalizationManager? = nil, settings: SettingsService = .shared,
         catalog: (() -> PackCatalog)? = nil,
         learning: (@MainActor () -> (languages: [String], via: [String: String]))? = nil) {
        self.packs = packs
        let status = status ?? .shared
        self.status = status
        let localization = localization ?? .shared
        self.localization = localization
        self.catalog = catalog ?? { PackCatalog.shared }
        self.learning = learning ?? { (settings.learningLanguages, settings.learningVia) }

        rows = Self.rows(catalog: self.catalog(), locale: localization.currentLocale)
        // Each pack's state, as `PackService` publishes it.
        status.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // A pack installed, updated or removed changes what Remove can delete.
        NotificationCenter.default.publisher(for: PackService.didChange, object: packs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
    }

    var locale: Locale { localization.currentLocale }

    /// Reads the packs with a file. The screen calls it when it appears.
    func refresh() async {
        let ids = Set(await packs.installedPacks().map(\.id))
        if ids != installed {
            installed = ids
        }
    }

    /// nil for the bundled English row.
    func state(of row: LanguageRow) -> PackState? {
        row.pack.map(status.state(of:))
    }

    /// An installed pack, not busy: swipe or Edit removes it. A failed
    /// update keeps its file, so it can be removed too.
    func canRemove(_ row: LanguageRow) -> Bool {
        guard let id = row.pack else { return false }
        switch status.state(of: id) {
        case .installed, .updateAvailable, .updateRequired: return true
        case .failed: return installed.contains(id)
        case .notInstalled, .waiting, .downloading, .installing: return false
        }
    }

    var hasRemovable: Bool { rows.contains(where: canRemove) }

    // MARK: Actions

    /// Download, Update and Try again: queues the install of `id` (0237,
    /// "Download and install"). It goes on when the screen closes; the row
    /// follows its state.
    func install(_ id: PackID) {
        let packs = packs
        Task { try? await packs.install(id) }
    }

    func cancel(_ id: PackID) {
        let packs = packs
        Task { await packs.cancel(id) }
    }

    /// Shows the remove alert of `id`.
    func requestRemove(_ id: PackID) {
        let learned = learning()
        removal = Self.removal(of: id, catalog: catalog(), learned: learned.languages, via: learned.via,
                               uiLanguage: localization.currentLanguage.code, locale: locale)
    }

    /// The alert's Remove: removes the pack (0237, "Remove"). Its
    /// dictionaries keep their place and switch in Dictionary Order.
    func confirmRemove(_ removal: Removal) {
        self.removal = nil
        let packs = packs
        Task {
            do {
                try await packs.remove(removal.pack)
            } catch {
                print("LanguagesViewModel: failed to remove \(removal.pack): \(error)")
            }
            await refresh()
        }
    }

    // MARK: Pure

    /// The packs whose file holds the word forms: `packs.json` puts the form
    /// tables (`lemma`, `form_lookup`, `paradigm`, …) into `ell`, and the
    /// catalog does not list them.
    nonisolated static let packsWithWordForms: Set<PackID> = [.ell]

    /// English (bundled) first, then its lists pack, then every other pack
    /// by its name in `locale`.
    nonisolated static func rows(catalog: PackCatalog, locale: Locale) -> [LanguageRow] {
        let english = LanguageRow(id: "eng", pack: nil, name: PackTexts.languageName("eng", locale: locale),
                                  contents: "WordNet", downloadSize: 0, installedSize: 0)
        let packRows = catalog.packs.map { pack in
            LanguageRow(
                id: pack.id.rawValue, pack: pack.id, name: PackTexts.name(of: pack, locale: locale),
                contents: PackTexts.contents(dictionaries: catalog.sources(of: pack.id).count,
                                             forms: packsWithWordForms.contains(pack.id),
                                             lists: catalog.lists.contains { $0.packID == pack.id },
                                             locale: locale),
                downloadSize: pack.size, installedSize: pack.fileSize)
        }
        let englishPacks = catalog.packs.filter { $0.lang == "eng" }.map(\.id.rawValue)
        let others = packRows.filter { !englishPacks.contains($0.id) }.sorted {
            $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                == .orderedAscending
        }
        return [english] + packRows.filter { englishPacks.contains($0.id) } + others
    }

    /// The remove alert of `id` (0237, "Remove"): what goes and what stays;
    /// when its language is learned, that the words stay, and that its lists
    /// come back only when it has built-in lists (`hasBuiltInLists`: Greek,
    /// English); for each learned pair of another language whose meanings come
    /// from its dictionaries ("English via Greek"), that the pair shows no
    /// meanings until the pack returns. `learned` and `via`: 0131's
    /// `learning_languages` and `learning_via`; `uiLanguage` the in-app
    /// language's code, for a language with no stored via.
    nonisolated static func removal(of id: PackID, catalog: PackCatalog, learned: [String], via: [String: String],
                                    uiLanguage: String, locale: Locale) -> Removal? {
        guard let pack = catalog.pack(id) else { return nil }
        let bundle = SettingsViewModel.localizedBundle(for: locale)
        let title = String(localized: "languages.remove.title \(PackTexts.inSentence(PackTexts.name(of: pack, locale: locale), locale: locale))",
                           bundle: bundle, locale: locale)
        let language = PackTexts.inSentence(PackTexts.languageName(pack.lang, locale: locale), locale: locale)
        var sentences = [SettingsViewModel.localizedString(removeMessageKey(of: pack, catalog: catalog), locale: locale)]
        if learned.contains(pack.lang) {
            // Only a language with built-in lists gets them back (PM, #243).
            if catalog.languages.contains(where: { $0.lang == pack.lang && $0.hasBuiltInLists }) {
                sentences.append(String(localized: "languages.remove.learning \(language) \(language)",
                                        bundle: bundle, locale: locale))
            } else {
                sentences.append(SettingsViewModel.localizedString("languages.remove.learning.noLists",
                                                                   locale: locale))
            }
        }
        let sources = Set(catalog.sources(of: id).map(\.source))
        let pairs = catalog.pairs
        for lang in learned where lang != pack.lang {
            guard let pairVia = Self.via(of: lang, stored: via, pairs: pairs, uiLanguage: uiLanguage),
                  let pair = pairs.first(where: { $0.lang == lang && $0.via == pairVia }),
                  pair.sources.contains(where: sources.contains) else { continue }
            sentences.append(String(localized: "languages.remove.pair \(pairName(pair, locale: locale)) \(language)",
                                    bundle: bundle, locale: locale))
        }
        return Removal(pack: id, title: title, message: sentences.joined(separator: " "))
    }

    /// The remove alert's first sentence, naming only what the pack holds
    /// (#245): its dictionaries, Greek's word forms, its built-in word lists
    /// (`hasBuiltInLists`); a pack of lists only names its lists. No pack has
    /// dictionaries and lists without forms: Greek is the only language
    /// with both.
    nonisolated static func removeMessageKey(of pack: CatalogPack, catalog: PackCatalog) -> String {
        let dictionaries = !catalog.sources(of: pack.id).isEmpty
        let forms = packsWithWordForms.contains(pack.id)
        let lists = catalog.lists.contains { $0.packID == pack.id }
        switch (dictionaries, forms, lists) {
        case (false, _, _): return "languages.remove.message.lists"
        case (true, true, true): return "languages.remove.message"
        case (true, true, false): return "languages.remove.message.forms"
        case (true, false, _): return "languages.remove.message.dictionaries"
        }
    }

    /// The via `lang` is learned through (0131, `learning_via`): the stored
    /// one while the catalog offers that pair, else its default: the UI
    /// language when that pair exists, else English, else the first by code.
    nonisolated static func via(of lang: String, stored: [String: String], pairs: [CatalogPair],
                                uiLanguage: String) -> String? {
        let vias = Set(pairs.filter { $0.lang == lang }.map(\.via))
        if let stored = stored[lang], vias.contains(stored) { return stored }
        let base = uiLanguage.split(separator: "-").first.map(String.init) ?? uiLanguage
        let ui = uiLanguageISO3[base] ?? base
        if vias.contains(ui) { return ui }
        if vias.contains("eng") { return "eng" }
        return vias.sorted().first
    }

    /// "English via Greek" (E4's `learn.pair`).
    nonisolated static func pairName(_ pair: CatalogPair, locale: Locale) -> String {
        let lang = PackTexts.languageName(pair.lang, locale: locale)
        let via = PackTexts.inSentence(PackTexts.languageName(pair.via, locale: locale), locale: locale)
        return String(format: SettingsViewModel.localizedString("learn.pair %@ %@", locale: locale), lang, via)
    }

    /// The UI languages' codes as the dictionaries write them.
    private nonisolated static let uiLanguageISO3 = ["en": "eng", "el": "ell", "es": "spa", "ru": "rus", "ar": "arb"]
}

// MARK: - The first-launch sheet (#245)

/// The first-launch sheet (0237, "First launch" and "Update from 1.x and
/// from the 2.0 alpha"): the languages it offers, which are checked, its
/// answer, then the chosen languages' progress. Its kind (`PackOffer.Sheet`)
/// picks the text and the packs checked at first. The answer is recorded
/// once (`PackOffer.record`): Download, Continue, Not now, or swiping the
/// sheet down. Nothing downloads until the user taps Download.
@MainActor
final class WelcomeViewModel: ObservableObject, Identifiable {
    let sheet: PackOffer.Sheet
    /// The languages offered, in the Languages screen's order: every
    /// language pack, and any other pack the sheet checks (the English
    /// lists of a missing sheet).
    let rows: [LanguageRow]
    @Published private(set) var checked: Set<PackID>
    /// The packs Download chose, in install order; nil while choosing.
    @Published private(set) var downloading: [PackID]?
    /// Download, Continue or Not now ran.
    private(set) var isAnswered = false

    let status: PackStatusModel
    private let packs: PackService
    private let settings: SettingsService
    private let localization: LocalizationManager
    private var cancellables: Set<AnyCancellable> = []

    /// `nil` status, localization and catalog: the shared ones. A test
    /// passes its own.
    init(sheet: PackOffer.Sheet, packs: PackService = .shared, status: PackStatusModel? = nil,
         localization: LocalizationManager? = nil, settings: SettingsService = .shared,
         catalog: PackCatalog? = nil) {
        self.sheet = sheet
        self.packs = packs
        let status = status ?? .shared
        self.status = status
        let localization = localization ?? .shared
        self.localization = localization
        self.settings = settings
        let catalog = catalog ?? .shared
        rows = Self.rows(for: sheet, catalog: catalog, locale: localization.currentLocale)
        checked = Set(sheet.checked).filter { id in Self.isOffered(status.state(of: id)) }
        // Each pack's state, as `PackService` publishes it.
        status.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var locale: Locale { localization.currentLocale }

    /// The text under the title, by kind.
    var message: String {
        let key = switch sheet.kind {
        case .fresh: "welcome.body"
        case .upgrade: "welcome.upgrade.body"
        case .missing: "welcome.missing.body"
        }
        return SettingsViewModel.localizedString(key, locale: locale)
    }

    /// While choosing, every language offered; after Download, the chosen ones.
    var shownRows: [LanguageRow] {
        guard let downloading else { return rows }
        return rows.filter { $0.pack.map(downloading.contains) ?? false }
    }

    func state(of row: LanguageRow) -> PackState? {
        row.pack.map(status.state(of:))
    }

    /// A row can be checked unless its pack is installed or already busy.
    func canCheck(_ row: LanguageRow) -> Bool {
        guard let id = row.pack else { return false }
        return Self.isOffered(status.state(of: id))
    }

    func isChecked(_ row: LanguageRow) -> Bool {
        row.pack.map(checked.contains) ?? false
    }

    func toggle(_ row: LanguageRow) {
        guard let id = row.pack, downloading == nil, canCheck(row) else { return }
        if checked.contains(id) {
            checked.remove(id)
        } else {
            checked.insert(id)
        }
    }

    /// The packs Download installs, in the rows' order.
    var chosen: [PackID] {
        rows.compactMap(\.pack).filter { checked.contains($0) && Self.isOffered(status.state(of: $0)) }
    }

    /// The checked total, in bytes.
    var downloadSize: Int64 {
        let chosen = Set(chosen)
        return rows.filter { $0.pack.map(chosen.contains) ?? false }.reduce(0) { $0 + $1.downloadSize }
    }

    /// "Download 18.1 MB", or "Continue" with nothing checked.
    var primaryTitle: String {
        chosen.isEmpty
            ? SettingsViewModel.localizedString("welcome.continue", locale: locale)
            : PackTexts.welcomeDownload(downloadSize, locale: locale)
    }

    // MARK: Answers

    /// Download: records the answer and queues the checked packs in the
    /// rows' order; the sheet then shows their progress. With nothing
    /// checked it is Continue: returns true, and the sheet closes.
    func download() -> Bool {
        let ids = chosen
        answer()
        guard !ids.isEmpty else { return true }
        downloading = ids
        let packs = packs
        Task { await packs.enqueue(ids) }
        return false
    }

    /// Not now: records the answer; nothing downloads.
    func notNow() {
        answer()
    }

    /// The sheet went away: swiping it down unanswered is Not now. After
    /// Download (Done, or a swipe), the downloads go on.
    func closed() {
        answer()
    }

    /// Try again and Cancel of a chosen pack's row.
    func install(_ id: PackID) {
        let packs = packs
        Task { try? await packs.install(id) }
    }

    func cancel(_ id: PackID) {
        let packs = packs
        Task { await packs.cancel(id) }
    }

    private func answer() {
        guard !isAnswered else { return }
        isAnswered = true
        PackOffer.record(sheet, in: settings)
    }

    // MARK: Pure

    /// The packs a pack row offers to download: not installed, needing an
    /// update, or failed; never one installed or busy.
    nonisolated static func isOffered(_ state: PackState) -> Bool {
        switch state {
        case .notInstalled, .updateAvailable, .updateRequired, .failed: return true
        case .installed, .waiting, .downloading, .installing: return false
        }
    }

    /// The sheet's rows: the Languages screen's rows of every language pack
    /// and of every other pack the sheet checks; never English, which is
    /// in the app.
    nonisolated static func rows(for sheet: PackOffer.Sheet, catalog: PackCatalog, locale: Locale) -> [LanguageRow] {
        let offered = Set(catalog.packs.filter { $0.kind == "language" }.map(\.id)).union(sheet.checked)
        return LanguagesViewModel.rows(catalog: catalog, locale: locale).filter { row in
            row.pack.map(offered.contains) ?? false
        }
    }
}

// MARK: - Not downloaded (#245)

/// The pack a word or a query waits for (0237, "Update from 1.x" and
/// "Offline and errors"). Pure: the views ask `PackStatusModel` whether it
/// is installed yet.
enum NotDownloaded {
    /// The pack that holds `source`, if the catalog has it.
    static func pack(ofSource source: String, catalog: PackCatalog) -> CatalogPack? {
        catalog.sources.first { $0.source == source }.flatMap { catalog.pack($0.packID) }
    }

    /// The dictionary pack of the language a query's script names: Greek,
    /// Cyrillic (Russian), Arabic. Nil for Latin and any other script: they
    /// name no single language.
    static func pack(forQuery query: String, catalog: PackCatalog) -> CatalogPack? {
        guard let letter = query.unicodeScalars.first(where: \.properties.isAlphabetic),
              let lang = language(of: letter),
              let id = catalog.languages.first(where: { $0.lang == lang })?.dictionaryPack else { return nil }
        return catalog.pack(id)
    }

    /// Installed and attached: its words resolve and its rows are searched.
    static func isAvailable(_ state: PackState) -> Bool {
        switch state {
        case .installed, .updateAvailable: return true
        case .notInstalled, .updateRequired, .waiting, .downloading, .installing, .failed: return false
        }
    }

    /// ISO 639-3 of the language a letter's script names.
    private static func language(of letter: Unicode.Scalar) -> String? {
        switch letter.value {
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return "ell"
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return "rus"
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return "arb"
        default: return nil
        }
    }
}
