// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    // UI Language Management
    @Published var selectedUILanguage: UILanguage = .english
    @Published var availableUILanguages: [UILanguage] = [.english]

    // Dictionary info (read-only, loaded from DB)
    @Published var sourceStats: [SourceStat] = []

    // Legacy import functionality
    @Published var totalCount: Int = 0
    @Published var isImporting = false
    @Published var importResult: String?

    private let settingsService = SettingsService.shared

    init() {
        loadUILanguageSettings()
        Task { await loadSourceStats() }
    }

    func loadUILanguageSettings() {
        selectedUILanguage = settingsService.selectedUILanguage
        availableUILanguages = UILanguage.allCases
    }

    func updateUILanguage(_ language: UILanguage) {
        selectedUILanguage = language
        settingsService.selectedUILanguage = language
    }

    func loadSourceStats() async {
        do {
            sourceStats = try await DatabaseService.shared.fetchSourceStats()
        } catch {
            // Non-fatal: leave sourceStats empty
            print("SettingsViewModel: failed to load source stats: \(error)")
        }
    }
}
