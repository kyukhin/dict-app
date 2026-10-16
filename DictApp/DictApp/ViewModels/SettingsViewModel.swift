// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management

import Foundation
import Combine
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    /// Dictionary list with enabled/disabled state, in the user's configured
    /// order (Issue #6). `orderedDictionaries` is the same list, exposed under
    /// the name the `DictionaryOrderView` reads.
    @Published var dictionaries: [DictionaryItem] = []

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
    private var cancellables: Set<AnyCancellable> = []

    /// `LocalizationManager.shared` is `@MainActor`-isolated, so passing it
    /// as a default-value expression would be evaluated in the caller's
    /// context — Swift 6 can't prove every caller is on the main actor.
    /// Accept `nil` and resolve `.shared` inside the `@MainActor`-isolated
    /// body instead.
    init(settingsService: SettingsService = .shared,
         localization: LocalizationManager? = nil) {
        self.settingsService = settingsService
        let resolvedLocalization = localization ?? .shared
        self.localization = resolvedLocalization

        // Re-publish manager changes through this view-model so the picker
        // updates immediately when the language is changed elsewhere.
        resolvedLocalization.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        resultSortMode = settingsService.resultSortMode
        Task { await loadDictionaries() }
    }

    func updateUILanguage(_ language: UILanguage) {
        localization.setLanguage(language)
    }

    func loadDictionaries() async {
        do {
            // `fetchSourceStats()` is the count-desc base order (§6); on first
            // launch #74 promotes the active UI language's dictionaries to the top.
            let stats = try await DatabaseService.shared.fetchSourceStats()
            let existing = stats.map(\.source)

            // Issue #92 §2b: re-establish the pair invariants (enabled-if-any,
            // contiguous members) on the stored prefs — covers callers that
            // bypass the App's launch-time pass, imports, and later iCloud merges.
            settingsService.normalizeDictionaryPreferences(knownSources: existing)

            // Reconcile the persisted order with live sources: keep stored order
            // for sources that still exist, append new/imported ones at the end
            // (in fetchSourceStats order), then re-persist so imports stick and a
            // first-launch default materializes. (§6 — lazy, persisted on first read.)
            var sourceOrder: [String]
            if let stored = settingsService.dictionaryOrder {
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
            settingsService.dictionaryOrder = sourceOrder

            let locale = localization.currentLocale
            dictionaries = DictionaryGrouping.pairs(from: stats, order: sourceOrder).map { pair in
                DictionaryItem(
                    pair: pair,
                    displayName: Self.displayName(for: pair, locale: locale),
                    // "Any" on read: a pair with a live enabled member never
                    // renders OFF, even before normalisation ran.
                    isEnabled: pair.sourceIDs.contains(where: settingsService.isEnabled(source:))
                )
            }
        } catch {
            print("SettingsViewModel: failed to load dictionaries: \(error)")
        }
    }

    /// Flips the enabled state of every source in the pair (Issue #92: one
    /// toggle per language pair) and persists it in one write.
    func togglePair(id pairID: String) {
        guard let index = dictionaries.firstIndex(where: { $0.id == pairID }) else { return }
        let knownSources = Set(dictionaries.flatMap(\.pair.sourceIDs))
        let newEnabled = !dictionaries[index].isEnabled
        settingsService.setEnabled(
            newEnabled, forSources: dictionaries[index].pair.sourceIDs, knownSources: knownSources
        )
        dictionaries[index].isEnabled = newEnabled
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

    /// Reorders pairs (drag-to-reorder) and persists the flattened source
    /// order (§6). Members stay contiguous by construction (I2).
    func movePair(from offsets: IndexSet, to destination: Int) {
        dictionaries.move(fromOffsets: offsets, toOffset: destination)
        settingsService.dictionaryOrder = dictionaries.flatMap(\.pair.sourceIDs)
    }

    // MARK: - Row naming (Issue #92)
    //
    // Naming is a UI concern, so it lives in the view-model rather than in the
    // grouping layer. Both helpers are `nonisolated static` so unit tests and
    // the #91 detail view can call them without a view-model instance.

    /// ISO-639-3 → catalog UI-language name table (`language.<code>.name`).
    nonisolated private static let languageNameKeys: [String: String] = [
        "eng": "en", "spa": "es", "rus": "ru", "arb": "ar",
    ]

    /// The `<lang>.lproj` bundle for `locale` (same rule as
    /// `LocalizationManager.localizedBundle`), falling back to `.main`.
    nonisolated private static func localizedBundle(for locale: Locale) -> Bundle {
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        return Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Localised name of an ISO-639-3 language code. The four shipped UI
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
            let first: String
            let second: String
            if pair.languages.contains("eng"), let other = pair.languages.first(where: { $0 != "eng" }) {
                (first, second) = (other, "eng")
            } else {
                (first, second) = (pair.languages[0], pair.languages[1])
            }
            let firstName = languageName(iso3: first, locale: locale)
            let secondName = languageName(iso3: second, locale: locale)
            return String(localized: "dictionaryPair.title \(firstName) \(secondName)",
                          bundle: localizedBundle(for: locale), locale: locale)
        default:
            return pair.id
        }
    }
}
