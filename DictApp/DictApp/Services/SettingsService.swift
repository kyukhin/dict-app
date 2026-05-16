// SettingsService.swift
// Service for managing app settings persistence

import Foundation

class SettingsService {
    static let shared = SettingsService()

    private let userDefaults = UserDefaults.standard
    private let uiLanguageKey = "ui_language"
    private let enabledSourcesKey = "enabled_sources"

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

    // MARK: - Enabled Sources

    /// The set of source identifiers the user has enabled.
    /// When nil (key absent = first launch), all sources are treated as enabled.
    var enabledSources: Set<String>? {
        get {
            guard let data = userDefaults.data(forKey: enabledSourcesKey),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil // nil = "all enabled" (first-launch default)
            }
            return Set(array)
        }
        set {
            if let newValue {
                let data = try? JSONEncoder().encode(Array(newValue))
                userDefaults.set(data, forKey: enabledSourcesKey)
            } else {
                userDefaults.removeObject(forKey: enabledSourcesKey)
            }
        }
    }

    /// Returns true if the given source is enabled.
    /// When no preference has been stored yet, all sources are enabled by default.
    func isEnabled(source: String) -> Bool {
        guard let stored = enabledSources else { return true }
        return stored.contains(source)
    }

    /// Enables or disables a specific source and persists the change.
    func setEnabled(_ enabled: Bool, for source: String, knownSources: Set<String>) {
        // Materialise the current set from all known sources if not yet stored.
        var current = enabledSources ?? knownSources
        if enabled {
            current.insert(source)
        } else {
            current.remove(source)
        }
        enabledSources = current
    }
}
