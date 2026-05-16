// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    // UI Language Management
    @Published var selectedUILanguage: UILanguage = .english
    @Published var availableUILanguages: [UILanguage] = [.english]

    // Dictionary list with enabled/disabled state
    @Published var dictionaries: [DictionaryItem] = []

    // Legacy import functionality
    @Published var isImporting = false
    @Published var importResult: String?

    private let settingsService = SettingsService.shared

    init() {
        loadUILanguageSettings()
        Task { await loadDictionaries() }
    }

    func loadUILanguageSettings() {
        selectedUILanguage = settingsService.selectedUILanguage
        availableUILanguages = UILanguage.allCases
    }

    func updateUILanguage(_ language: UILanguage) {
        selectedUILanguage = language
        settingsService.selectedUILanguage = language
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
