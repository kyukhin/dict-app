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
            // `fetchSourceStats()` is the count-desc default order (§6); #74 will
            // swap in device-language ordering.
            let stats = try await DatabaseService.shared.fetchSourceStats()
            let existing = stats.map(\.source)

            // Reconcile the persisted order with live sources: keep stored order
            // for sources that still exist, append new/imported ones at the end
            // (in fetchSourceStats order), then re-persist so imports stick and a
            // first-launch default materializes. (§6 — lazy, persisted on first read.)
            let effectiveOrder: [String]
            if let stored = settingsService.dictionaryOrder {
                effectiveOrder = stored.filter { existing.contains($0) }
                    + existing.filter { !stored.contains($0) }
            } else {
                effectiveOrder = existing
            }
            settingsService.dictionaryOrder = effectiveOrder

            let bySource = Dictionary(stats.map { ($0.source, $0) }, uniquingKeysWith: { a, _ in a })
            dictionaries = effectiveOrder.compactMap { source in
                guard let stat = bySource[source] else { return nil }
                return DictionaryItem(
                    source: stat.source,
                    displayName: stat.displayName,
                    count: stat.count,
                    isEnabled: settingsService.isEnabled(source: stat.source)
                )
            }
        } catch {
            print("SettingsViewModel: failed to load dictionaries: \(error)")
        }
    }

    func toggleDictionary(source: String) {
        guard let index = dictionaries.firstIndex(where: { $0.source == source }) else { return }
        let knownSources = Set(dictionaries.map { $0.source })
        let newEnabled = !dictionaries[index].isEnabled
        settingsService.setEnabled(newEnabled, for: source, knownSources: knownSources)
        dictionaries[index].isEnabled = newEnabled
    }

    /// Two-way binding for a source's enabled state, for the `DictionaryOrderView`
    /// toggle (Issue #6). Disabled sources stay in the order (greyed, draggable).
    func binding(for source: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.dictionaries.first(where: { $0.source == source })?.isEnabled ?? false
            },
            set: { [weak self] newValue in
                guard let self,
                      let item = self.dictionaries.first(where: { $0.source == source }),
                      item.isEnabled != newValue else { return }
                self.toggleDictionary(source: source)
            }
        )
    }

    /// Reorders dictionaries (drag-to-reorder) and persists the new order (§6).
    func moveDictionary(from offsets: IndexSet, to destination: Int) {
        dictionaries.move(fromOffsets: offsets, toOffset: destination)
        settingsService.dictionaryOrder = dictionaries.map(\.source)
    }
}
