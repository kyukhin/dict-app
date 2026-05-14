// SettingsService.swift
// Service for managing app settings persistence

import Foundation

class SettingsService {
    static let shared = SettingsService()

    private let userDefaults = UserDefaults.standard
    private let uiLanguageKey = "ui_language"

    private init() {}

    var selectedUILanguage: UILanguage {
        get {
            let rawValue = userDefaults.string(forKey: uiLanguageKey) ?? UILanguage.english.rawValue
            return UILanguage(rawValue: rawValue) ?? .english
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: uiLanguageKey)
        }
    }
}