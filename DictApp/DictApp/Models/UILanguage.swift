// UILanguage.swift
// Model for UI language selection in Settings

import Foundation

enum UILanguage: String, CaseIterable, Identifiable {
    case english = "en"
    // Future languages when Issues #1 and #9 are implemented
    // case spanish = "es"
    // case french = "fr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        }
    }

    var nativeName: String {
        switch self {
        case .english:
            return "English"
        }
    }
}