// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    /// Dictionary list with enabled/disabled state.
    @Published var dictionaries: [DictionaryItem] = []

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

        Task { await loadDictionaries() }
    }

    func updateUILanguage(_ language: UILanguage) {
        localization.setLanguage(language)
    }

    func loadDictionaries() async {
        do {
            let stats = try await DatabaseService.shared.fetchSourceStats()
            dictionaries = stats.map { stat in
                DictionaryItem(
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
}
