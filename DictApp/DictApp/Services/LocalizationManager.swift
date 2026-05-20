// LocalizationManager.swift
// Single source of truth for the active UI locale at runtime.
//
// Reads the list of supported languages from
// `Resources/SupportedLocales.json`, picks the active language from (in
// order) the persisted preference, the device's preferred languages, then
// English as a final fallback. Publishes a `Locale` so SwiftUI views set
// `\.locale` against it and Apple's localized-string lookups, plural
// rules, and date/number formatters all stay in sync.

import Foundation
import Combine
import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Active locale published to the SwiftUI environment (`\.locale`).
    @Published private(set) var currentLocale: Locale

    /// The full record matching `currentLocale`. The picker binds to this.
    @Published private(set) var currentLanguage: UILanguage

    /// All languages declared in `SupportedLocales.json`. The picker reads
    /// this so adding a language is purely a resource change.
    @Published private(set) var supportedLanguages: [UILanguage]

    private let settingsService: SettingsService

    /// Internal so unit tests can construct disposable instances with a
    /// controlled `SettingsService` and a chosen `Bundle`. Production code
    /// must continue to use `LocalizationManager.shared`.
    init(settingsService: SettingsService = .shared,
         bundle: Bundle = .main) {
        self.settingsService = settingsService
        let supported = Self.loadSupportedLanguages(from: bundle)
        self.supportedLanguages = supported

        let active = Self.resolveInitialLanguage(
            persistedCode: settingsService.selectedUILanguageCode,
            supported: supported
        )
        self.currentLanguage = active
        self.currentLocale = Locale(identifier: active.code)
    }

    /// Updates the active language and persists the choice. No-op if
    /// `language` isn't in `supportedLanguages` (defensive — UI never offers
    /// that, but tests may).
    func setLanguage(_ language: UILanguage) {
        guard supportedLanguages.contains(where: { $0.code == language.code }) else { return }
        currentLanguage = language
        currentLocale = Locale(identifier: language.code)
        settingsService.selectedUILanguageCode = language.code
    }

    // MARK: - Bundle-resolved string lookup
    //
    // For the small number of sites where a plain `String` is required
    // (alerts, accessibility labels constructed outside a `Text`), this
    // helper looks the key up against the localization bundle for the
    // *currently active* language so the result honours the in-app
    // language choice rather than the device locale.

    var localizedBundle: Bundle {
        Bundle.main.path(forResource: currentLanguage.code, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }

    func localized(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, bundle: localizedBundle, comment: comment)
    }

    // MARK: - Initial-language resolution

    /// Internal so unit tests can exercise the resolution rules without
    /// constructing a full `LocalizationManager`.
    static func resolveInitialLanguage(persistedCode: String?,
                                       supported: [UILanguage]) -> UILanguage {
        let englishFallback = supported.first(where: { $0.code == "en" })
            ?? supported.first
            ?? UILanguage(code: "en", displayKey: "language.en.name", nativeName: "English")

        if let code = persistedCode,
           let match = supported.first(where: { $0.code == code }) {
            return match
        }

        // No persisted choice. Try the device's preferred languages in
        // order, matching each against the supported list by language code
        // (handle "en-US" → "en" by trimming the region suffix).
        for raw in Locale.preferredLanguages {
            let primary = raw.split(separator: "-").first.map(String.init) ?? raw
            if let match = supported.first(where: { $0.code == primary }) {
                return match
            }
        }

        return englishFallback
    }

    // MARK: - Manifest loading

    private static func loadSupportedLanguages(from bundle: Bundle) -> [UILanguage] {
        guard let url = bundle.url(forResource: "SupportedLocales", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([UILanguage].self, from: data),
              !decoded.isEmpty else {
            // Manifest missing or unreadable — fall back to English-only so
            // the app keeps working even if the resource never registered.
            print("LocalizationManager: SupportedLocales.json missing or invalid; defaulting to English-only.")
            return [UILanguage(code: "en", displayKey: "language.en.name", nativeName: "English")]
        }
        return decoded
    }
}
