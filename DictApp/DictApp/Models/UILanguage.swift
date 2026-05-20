// UILanguage.swift
// Declarative model for a UI language. Loaded from
// `Resources/SupportedLocales.json` so adding a new language is a
// configuration / resource change rather than a code change.

import Foundation

struct UILanguage: Identifiable, Hashable, Codable {
    /// BCP-47 / ISO identifier, also the String Catalog locale name
    /// (e.g. "en", "ru").
    let code: String

    /// String-Catalog key that resolves to this language's name in the
    /// *currently active* UI language (e.g. "Russian" when UI is in
    /// English, "Русский" when UI is in Russian).
    let displayKey: String

    /// The language's name in its own script. Constant across UI languages
    /// (read straight from the manifest, never translated).
    let nativeName: String

    var id: String { code }
}
