// SettingsViewModel.swift
// ViewModel for Settings view with UI language and dictionary management

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    // UI Language Management
    @Published var selectedUILanguage: UILanguage = .english
    @Published var availableUILanguages: [UILanguage] = [.english]

    // Dictionary Management (temporarily disabled)
    @Published var totalCount: Int = 0
    @Published var isImporting = false
    @Published var importResult: String?

    private let settingsService = SettingsService.shared

    init() {
        loadUILanguageSettings()
    }

    func loadUILanguageSettings() {
        selectedUILanguage = settingsService.selectedUILanguage
        availableUILanguages = UILanguage.allCases
    }

    func updateUILanguage(_ language: UILanguage) {
        selectedUILanguage = language
        settingsService.selectedUILanguage = language
    }
}
