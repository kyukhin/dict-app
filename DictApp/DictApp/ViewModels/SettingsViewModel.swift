// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management.
// Also holds `DictionarySelection`, the pair list shared with Search (#145).

import Foundation
import Combine
import SwiftUI

// MARK: - Dictionary selection (Issue #145)

/// The one in-memory owner of the Dictionary Order list: every language pair
/// in the Dictionary Order sequence, with its enabled state. The Search chips
/// and the Dictionary Order screen both render `pairs` and change it only
/// through these methods, so they always show the same state and order, in
/// every iPad window.
///
/// The setting itself stays in `SettingsService` (`enabled_sources`,
/// `dictionary_order`). Each method writes the store first, then publishes
/// `pairs`: `@Published` emits before the property changes, so a subscriber
/// that reads the store (the Search re-run) already sees the new value. Code
/// that writes the two keys anywhere else (the import flow) calls `load()`
/// afterwards. The shared instance outlives the root `.id(language)` rebuild
/// and re-titles its pairs on a language change.
@MainActor
final class DictionarySelection: ObservableObject {
    static let shared = DictionarySelection()

    /// The pairs in the Dictionary Order sequence. Published only on change.
    @Published private(set) var pairs: [DictionaryItem] = []
    /// True once a load has published the list.
    @Published private(set) var isLoaded = false

    /// Every pair is on.
    var allEnabled: Bool { pairs.allSatisfy(\.isEnabled) }
    /// There is at least one pair and none is on.
    var noneEnabled: Bool { !pairs.isEmpty && !pairs.contains(where: \.isEnabled) }

    private let settings: SettingsService
    private let localization: LocalizationManager
    private let db: DatabaseService
    private var cancellables: Set<AnyCancellable> = []

    /// `LocalizationManager.shared` is `@MainActor`-isolated, so it is
    /// resolved inside the body (same pattern as `SettingsViewModel`).
    init(settings: SettingsService = .shared,
         localization: LocalizationManager? = nil,
         db: DatabaseService = .shared) {
        self.settings = settings
        let resolvedLocalization = localization ?? .shared
        self.localization = resolvedLocalization
        self.db = db

        // `$currentLanguage` emits before `currentLocale` changes, so build
        // the locale from the new language, the way `setLanguage` does.
        resolvedLocalization.$currentLanguage
            .dropFirst()
            .sink { [weak self] language in self?.retitle(locale: Locale(identifier: language.code)) }
            .store(in: &cancellables)
    }

    /// The selection that owns `settings`: `.shared` for the app's settings.
    /// A unit test that brings its own `SettingsService` gets a new selection
    /// over it, so its view models never write the app's store.
    static func owning(_ settings: SettingsService,
                       localization: LocalizationManager? = nil,
                       db: DatabaseService = .shared) -> DictionarySelection {
        settings === SettingsService.shared
            ? .shared
            : DictionarySelection(settings: settings, localization: localization, db: db)
    }

    /// Loads once; later calls do nothing. Search calls it when it appears.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    /// Loads the pair list. Search loads it once; the Dictionary order screen
    /// reloads it each time it appears (Issue #105), and the import flow after
    /// an import, so imports and removals show without a relaunch. An
    /// unchanged reload writes nothing and publishes nothing.
    func load() async {
        do {
            // `fetchSourceStats()` is the count-desc base order (§6); on first
            // launch #74 promotes the active UI language's dictionaries to the top.
            let stats = try await db.fetchSourceStats()
            // Issue #105: this await is the only suspension point. Every
            // `settings` read stays below it, so a reorder or toggle made
            // while the fetch was in flight is picked up here, never reverted.
            let existing = stats.map(\.source)

            // Issue #92 §2b: re-establish the pair invariants (enabled-if-any,
            // contiguous members) on the stored prefs — covers callers that
            // bypass the App's launch-time pass, imports, and later iCloud merges.
            settings.normalizeDictionaryPreferences(knownSources: existing)

            // Reconcile the persisted order with live sources: keep stored order
            // for sources that still exist, append new/imported ones at the end
            // (in fetchSourceStats order), then re-persist so imports stick and a
            // first-launch default materializes. (§6 — lazy, persisted on first read.)
            let storedOrder = settings.dictionaryOrder
            var sourceOrder: [String]
            if let stored = storedOrder {
                sourceOrder = stored.filter { existing.contains($0) }
                    + existing.filter { !stored.contains($0) }
            } else {
                // First launch (Issue #74): no stored order → derive the default
                // from the UI language. Never reached once an order is persisted.
                sourceOrder = DictionaryDefaults.defaultOrder(
                    for: localization.currentLanguage, sources: existing
                )
            }
            // I2: pair members contiguous at the earliest member's position.
            // Canonical member order inside a pair = relative order here.
            sourceOrder = DictionaryGrouping.groupedOrder(sourceOrder)
            // Write only on change: this runs on every order-screen open (#105)
            // and must not churn the store (#73 iCloud seam).
            if sourceOrder != storedOrder {
                settings.dictionaryOrder = sourceOrder
            }

            let locale = localization.currentLocale
            let items = DictionaryGrouping.pairs(from: stats, order: sourceOrder).map { pair in
                DictionaryItem(
                    pair: pair,
                    displayName: SettingsViewModel.displayName(for: pair, locale: locale),
                    // "Any" on read: a pair with a live enabled member never
                    // renders OFF, even before normalisation ran.
                    isEnabled: pair.sourceIDs.contains(where: settings.isEnabled(source:))
                )
            }
            // Publish only on change, so an unchanged reload leaves the List
            // (and any drag in progress) untouched.
            publish(items)
            if !isLoaded { isLoaded = true }
        } catch is CancellationError {
            // The caller's `.task` was cancelled; keep the current list.
        } catch {
            print("DictionarySelection: failed to load dictionaries: \(error)")
        }
    }

    /// Turns every source of the pair on or off in one write (Issue #92: the
    /// sources of a pair share one state). The known set is every listed
    /// source, so the first change never switches off another pair. No write
    /// when the pair is already in that state or unknown.
    func setEnabled(_ enabled: Bool, pair pairID: String) {
        guard let index = pairs.firstIndex(where: { $0.id == pairID }),
              pairs[index].isEnabled != enabled else { return }
        let knownSources = Set(pairs.flatMap(\.pair.sourceIDs))
        settings.setEnabled(enabled, forSources: pairs[index].pair.sourceIDs, knownSources: knownSources)
        var items = pairs
        items[index].isEnabled = enabled
        publish(items)
    }

    /// "Only this": the stored set becomes exactly the pair's sources. One
    /// write, none when that is already the stored set.
    func enableOnly(pair pairID: String) {
        guard let target = pairs.first(where: { $0.id == pairID }) else { return }
        let only = Set(target.pair.sourceIDs)
        if settings.enabledSources != only {
            settings.enabledSources = only
        }
        publish(pairs.map { item in
            var item = item
            item.isEnabled = item.id == pairID
            return item
        })
    }

    /// "All": stores "everything on" the way a fresh install does, by removing
    /// `enabled_sources`, so a dictionary that arrives later is on too. Also
    /// clears an explicit set that already holds every source. No write when
    /// the key is already absent.
    func enableAll() {
        if settings.enabledSources != nil {
            settings.enabledSources = nil
        }
        publish(pairs.map { item in
            var item = item
            item.isEnabled = true
            return item
        })
    }

    /// Reorders pairs (drag-to-reorder) and persists the flattened source
    /// order (§6). Members stay contiguous by construction (I2).
    func move(from offsets: IndexSet, to destination: Int) {
        var items = pairs
        items.move(fromOffsets: offsets, toOffset: destination)
        guard items != pairs else { return }
        settings.dictionaryOrder = items.flatMap(\.pair.sourceIDs)
        pairs = items
    }

    /// Rebuilds every title for `locale` after an in-app language change.
    private func retitle(locale: Locale) {
        publish(pairs.map { item in
            DictionaryItem(pair: item.pair,
                           displayName: SettingsViewModel.displayName(for: item.pair, locale: locale),
                           isEnabled: item.isEnabled)
        })
    }

    private func publish(_ items: [DictionaryItem]) {
        if items != pairs {
            pairs = items
        }
    }
}

// MARK: - Settings

@MainActor
class SettingsViewModel: ObservableObject {
    /// Dictionary list with enabled/disabled state, in the user's configured
    /// order (Issue #6). Since #145 it re-publishes `DictionarySelection.pairs`,
    /// the list the Search chips share. `orderedDictionaries` is the same
    /// list, exposed under the name the `DictionaryOrderView` reads.
    @Published private(set) var dictionaries: [DictionaryItem] = []

    var orderedDictionaries: [DictionaryItem] { dictionaries }

    /// Search result ordering (Issue #6). Bound to the Settings picker; writes
    /// through to `SettingsService` so the next search picks it up.
    @Published var resultSortMode: ResultSortMode = .relevance {
        didSet {
            guard oldValue != resultSortMode else { return }
            settingsService.resultSortMode = resultSortMode
        }
    }

    /// The active UI language. Reads through to `LocalizationManager` so the
    /// picker stays in sync with the rest of the app — there is exactly one
    /// authoritative source of truth for the current language.
    var selectedUILanguage: UILanguage { localization.currentLanguage }

    /// All UI languages declared in `Resources/SupportedLocales.json`.
    var availableUILanguages: [UILanguage] { localization.supportedLanguages }

    private let settingsService: SettingsService
    private let localization: LocalizationManager
    /// The pair list shared with the Search chips (Issue #145).
    private let selection: DictionarySelection
    private var cancellables: Set<AnyCancellable> = []

    /// `LocalizationManager.shared` is `@MainActor`-isolated, so passing it
    /// as a default-value expression would be evaluated in the caller's
    /// context — Swift 6 can't prove every caller is on the main actor.
    /// Accept `nil` and resolve `.shared` inside the `@MainActor`-isolated
    /// body instead. A `nil` selection is `.shared` for the app's settings,
    /// or a new one over a test's own settings (`DictionarySelection.owning`).
    init(settingsService: SettingsService = .shared,
         localization: LocalizationManager? = nil,
         selection: DictionarySelection? = nil) {
        self.settingsService = settingsService
        let resolvedLocalization = localization ?? .shared
        self.localization = resolvedLocalization
        let resolvedSelection = selection ?? .owning(settingsService, localization: resolvedLocalization)
        self.selection = resolvedSelection

        // Re-publish manager changes through this view-model so the picker
        // updates immediately when the language is changed elsewhere.
        resolvedLocalization.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // The pair list, which the Search chips also change (#145). Emits
        // only when the selection publishes, i.e. only on change.
        resolvedSelection.$pairs.assign(to: &$dictionaries)

        resultSortMode = settingsService.resultSortMode
        Task { await loadDictionaries() }
    }

    func updateUILanguage(_ language: UILanguage) {
        localization.setLanguage(language)
    }

    /// Loads the pair list (`DictionarySelection.load()`). Runs once from
    /// `init` and again each time the Dictionary order screen appears
    /// (Issue #105), so imports and removals show without a relaunch.
    func loadDictionaries() async {
        await selection.load()
    }

    /// Flips the enabled state of every source in the pair (Issue #92: one
    /// toggle per language pair) and persists it in one write.
    func togglePair(id pairID: String) {
        guard let item = dictionaries.first(where: { $0.id == pairID }) else { return }
        selection.setEnabled(!item.isEnabled, pair: pairID)
    }

    /// Two-way binding for a pair's enabled state, for the `DictionaryOrderView`
    /// toggle (Issue #6). Disabled pairs stay in the order (greyed, draggable).
    func binding(for pairID: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.dictionaries.first(where: { $0.id == pairID })?.isEnabled ?? false
            },
            set: { [weak self] newValue in
                guard let self,
                      let item = self.dictionaries.first(where: { $0.id == pairID }),
                      item.isEnabled != newValue else { return }
                self.togglePair(id: pairID)
            }
        )
    }

    /// Reorders pairs (drag-to-reorder); see `DictionarySelection.move`.
    func movePair(from offsets: IndexSet, to destination: Int) {
        selection.move(from: offsets, to: destination)
    }

    // MARK: - Row naming (Issue #92)
    //
    // Naming is a UI concern, so it lives in the view-model rather than in the
    // grouping layer. Both helpers are `nonisolated static` so unit tests and
    // the #91 detail view can call them without a view-model instance.

    /// ISO-639-3 → catalog language name table (`language.<code>.name`).
    /// Covers the five shipped UI languages (`el` since Issue #88). ICU's
    /// ru/es names are lowercase, which reads wrong in a title.
    nonisolated private static let languageNameKeys: [String: String] = [
        "eng": "en", "spa": "es", "rus": "ru", "arb": "ar", "ell": "el",
    ]

    /// The `<lang>.lproj` bundle for `locale` (same rule as
    /// `LocalizationManager.localizedBundle`), falling back to `.main`. Also
    /// resolves the Search form captions (#142).
    nonisolated static func localizedBundle(for locale: Locale) -> Bundle {
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        return Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Localised name of an ISO-639-3 language code. The five shipped UI
    /// languages reuse their `language.<code>.name` catalog entries; any other
    /// code falls back to ICU's display name, then to the raw code.
    nonisolated static func languageName(iso3: String, locale: Locale) -> String {
        if let code = languageNameKeys[iso3] {
            // Build the key as a plain String: an interpolated
            // `String.LocalizationValue` literal would look up the format key
            // "language.%@.name" (absent) and render the raw key. Resolve
            // against the locale's lproj, because `String(localized:locale:)`
            // only picks plural rules, not the table (in-app language ≠ device).
            let key = "language." + code + ".name"
            return localizedBundle(for: locale).localizedString(forKey: key, value: key, table: nil)
        }
        return locale.localizedString(forLanguageCode: iso3) ?? iso3
    }

    /// Row title for a pair: the raw source name for custom imports, the
    /// language name for a monolingual pair ("English", never
    /// "English – English"), and `"%1$@ – %2$@"` with the non-English language
    /// first for a bilingual pair ("Spanish – English").
    nonisolated static func displayName(for pair: DictionaryPair, locale: Locale) -> String {
        if pair.isCustom {
            return pair.sources.first?.displayName ?? pair.id
        }
        switch pair.languages.count {
        case 1:
            return languageName(iso3: pair.languages[0], locale: locale)
        case 2:
            let (first, second) = titleLanguages(of: pair)
            let firstName = languageName(iso3: first, locale: locale)
            let secondName = languageName(iso3: second, locale: locale)
            return String(localized: "dictionaryPair.title \(firstName) \(secondName)",
                          bundle: localizedBundle(for: locale), locale: locale)
        default:
            return pair.id
        }
    }

    /// A bilingual pair's languages in title order: the non-English language
    /// first ("Spanish – English"), else the sorted pair order.
    nonisolated private static func titleLanguages(of pair: DictionaryPair) -> (first: String, second: String) {
        if pair.languages.contains("eng"), let other = pair.languages.first(where: { $0 != "eng" }) {
            return (other, "eng")
        }
        return (pair.languages[0], pair.languages[1])
    }

    // MARK: - Dictionary info detail (Issue #91)
    //
    // Pure presentation helpers for `DictionaryDetailView` and the (i) button.
    // No DB access: everything is derived from the already-loaded `SourceStat`s.

    /// Brand names by `SourceStat.provider`. Not translated (like "LibreDict").
    nonisolated private static let providerBrands: [String: String] = [
        "wordnet": "WordNet", "freedict": "FreeDict", "openrussian": "OpenRussian",
    ]

    /// The pair's sources in a fixed, title-consistent order, independent of
    /// the user's dictionary order (PM decision #1): the direction that reads
    /// like the title first (Spanish → English), then the reverse direction,
    /// then monolingual / custom sources. Within a direction, sources sort by
    /// ID (Issue #87: `freedict-ell-eng` before `wordnet-ell-eng`); sources
    /// without a direction keep their input order. Never adds or drops a source.
    nonisolated static func infoSources(for pair: DictionaryPair) -> [SourceStat] {
        let titleFirst = pair.languages.count == 2 ? titleLanguages(of: pair).first : nil
        func rank(_ stat: SourceStat) -> Int {
            guard let direction = stat.direction else { return 2 }
            return direction.from == titleFirst ? 0 : 1
        }
        func key(_ item: (offset: Int, element: SourceStat)) -> (Int, String, Int) {
            let r = rank(item.element)
            return (r, r < 2 ? item.element.source : "", item.offset)
        }
        return pair.sources.enumerated()
            .sorted { key($0) < key($1) }
            .map(\.element)
    }

    /// Provider brand name ("WordNet", "FreeDict", "OpenRussian"); the raw
    /// provider for an unknown bundled one; `nil` for custom imports.
    nonisolated static func providerName(for stat: SourceStat) -> String? {
        providerName(forSource: stat.source)
    }

    nonisolated private static func providerName(forSource source: String) -> String? {
        let parsed = DictionaryGrouping.parse(sourceID: source)
        if parsed.isCustom { return nil }
        return providerBrands[parsed.provider] ?? parsed.provider
    }

    /// VoiceOver label of a search-result source badge (Issue #87):
    /// "Greek to English, FreeDict" for a bilingual source, "English, WordNet"
    /// for a monolingual one, in the in-app language. `nil` for a custom
    /// import, whose visible badge text is read as is.
    nonisolated static func badgeAccessibilityLabel(forSource source: String, locale: Locale) -> String? {
        let parsed = DictionaryGrouping.parse(sourceID: source)
        guard !parsed.isCustom, let brand = providerName(forSource: source) else { return nil }
        let bundle = localizedBundle(for: locale)
        switch parsed.languages.count {
        case 1:
            let name = languageName(iso3: parsed.languages[0], locale: locale)
            return String(localized: "sourceBadge.accessibilityLabel.single \(name) \(brand)",
                          bundle: bundle, locale: locale)
        case 2:
            let from = languageName(iso3: parsed.languages[0], locale: locale)
            let to = languageName(iso3: parsed.languages[1], locale: locale)
            return String(localized: "sourceBadge.accessibilityLabel.pair \(from) \(to) \(brand)",
                          bundle: bundle, locale: locale)
        default:
            return nil
        }
    }

    /// Header of a source block in the info detail (PM decision #4): the
    /// provider brand, or the source ID for a custom import. Never the bundled
    /// untranslated English `display_name`.
    nonisolated static func infoBlockTitle(for stat: SourceStat) -> String {
        providerName(for: stat) ?? stat.source
    }

    /// "Spanish → English" for a bilingual source (Arabic: "←", see the
    /// catalog comment), the language name for a monolingual one, `nil` for
    /// a custom import.
    nonisolated static func languageSummary(for stat: SourceStat, locale: Locale) -> String? {
        let parsed = DictionaryGrouping.parse(sourceID: stat.source)
        switch parsed.languages.count {
        case 1:
            return languageName(iso3: parsed.languages[0], locale: locale)
        case 2:
            let from = languageName(iso3: parsed.languages[0], locale: locale)
            let to = languageName(iso3: parsed.languages[1], locale: locale)
            return String(localized: "dictionaryInfo.direction.value \(from) \(to)",
                          bundle: localizedBundle(for: locale), locale: locale)
        default:
            return nil
        }
    }

    /// Accessibility label of the (i) button: "Details for Spanish – English".
    nonisolated static func infoButtonLabel(for title: String, locale: Locale) -> String {
        String(localized: "dictionaryInfo.button.accessibilityLabel \(title)",
               bundle: localizedBundle(for: locale), locale: locale)
    }

    /// A plain (non-format) catalog string resolved against the in-app
    /// language's lproj, not the device language.
    nonisolated static func localizedString(_ key: String, locale: Locale) -> String {
        localizedBundle(for: locale).localizedString(forKey: key, value: key, table: nil)
    }
}
