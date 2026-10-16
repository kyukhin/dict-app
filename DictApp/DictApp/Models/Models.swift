// Models.swift
// Core data models for the dictionary app.

import Foundation
import GRDB

// MARK: - DictionaryEntry

struct DictionaryEntry: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    var definition: String
    var phonetic: String
    var pos: String            // part of speech
    var source: String
    var createdAt: String?

    static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id, word, definition, phonetic, pos, source, createdAt = "created_at"
    }

    // Custom coding keys to bridge snake_case SQL <-> camelCase Swift.
    enum CodingKeys: String, CodingKey {
        case id
        case word
        case definition
        case phonetic
        case pos
        case source
        case createdAt = "created_at"
    }

    /// Human-readable source label for display.
    var sourceLabel: String {
        switch source {
        case "wordnet":          return "WordNet"
        case "openrussian":      return "OpenRussian"
        // Badge is space-constrained; the full name lives in
        // `dict_metadata.display_name` (Settings + DictionaryDetailView).
        case "freedict-eng-spa": return "En–Es"
        case "wordnet-spa-eng":  return "Es–En"
        case "wordnet-arb-eng":  return "Ar–En"
        default:                 return source.capitalized
        }
    }
}

// MARK: - HistoryItem

struct HistoryItem: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var word: String
    /// Dictionary source of the entry that was last viewed for this word
    /// (Issue #6). Defaults to "" for rows migrated before `history.source`
    /// existed — those render the neutral `Sources/default` stripe until
    /// the word is viewed again.
    var source: String = ""
    var lookedAt: String?

    static let databaseTableName = "history"

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case source
        case lookedAt = "looked_at"
    }
}

// MARK: - ResultSortMode (Issue #6)

/// How search results are ordered. `.relevance` is FTS rank (the default);
/// `.preferredDictionary` surfaces the top-N of each enabled dictionary in the
/// user's configured order, then a relevance tail (see `DatabaseService`).
enum ResultSortMode: String {
    case relevance
    case preferredDictionary
}

// MARK: - Bookmark

struct Bookmark: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var entryId: Int64
    var createdAt: String?

    static let databaseTableName = "bookmarks"

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case createdAt = "created_at"
    }
}

// MARK: - BookmarkedEntry (join result)

struct BookmarkedEntry: Identifiable, Equatable {
    var id: Int64 { entry.id ?? 0 }
    let entry: DictionaryEntry
    let bookmark: Bookmark
}

// MARK: - DictMetadata

struct DictMetadata: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    var source: String
    var displayName: String
    var version: String
    var license: String
    var url: String
    var wordCount: Int
    var builtAt: String?
    var description: String

    var id: String { source }
    static let databaseTableName = "dict_metadata"

    enum CodingKeys: String, CodingKey {
        case source
        case displayName = "display_name"
        case version
        case license
        case url
        case wordCount = "word_count"
        case builtAt = "built_at"
        case description
    }
}

// MARK: - SourceStat (lightweight per-source count)

struct SourceStat: Identifiable, Hashable {
    var id: String { source }
    let source: String
    let displayName: String
    let count: Int
    /// From `dict_metadata` (Issue #92); `""` for custom imports, which have
    /// no metadata row. Defaulted so the memberwise init stays source-compatible.
    var license: String = ""
    var version: String = ""

    /// Provider name derived from the source ID (`wordnet`, `freedict`, …);
    /// the raw ID for custom imports. See `DictionaryGrouping.parse(sourceID:)`.
    var provider: String { DictionaryGrouping.parse(sourceID: source).provider }

    /// Translation direction (ISO-639-3) for bilingual bundled sources;
    /// `nil` for monolingual and custom sources.
    var direction: (from: String, to: String)? {
        let languages = DictionaryGrouping.parse(sourceID: source).languages
        guard languages.count == 2 else { return nil }
        return (from: languages[0], to: languages[1])
    }
}

// MARK: - DictionaryPair (Issue #92)

/// A language pair as shown on the Dictionary Order screen: one row, one
/// toggle, one drag slot. Bundled sources that serve the same pair of
/// languages in either direction (e.g. `freedict-eng-spa` and
/// `wordnet-spa-eng`) share one pair; monolingual and custom sources are
/// single-member pairs. `sources` is the #91 detail-view API: each member
/// exposes provider / direction / license / version on its own.
struct DictionaryPair: Identifiable, Hashable {
    /// Pair key from `DictionaryGrouping.pairKey(forSource:)`
    /// (`eng`, `eng-spa`, `custom:<id>`). Runtime-only, never persisted.
    let id: String
    /// ISO-639-3 codes, sorted; empty for custom sources.
    let languages: [String]
    let isCustom: Bool
    /// Underlying sources in canonical (user-order) order.
    let sources: [SourceStat]

    var sourceIDs: [String] { sources.map(\.source) }
    var count: Int { sources.reduce(0) { $0 + $1.count } }
}

// MARK: - DictionaryItem (Settings UI model with enabled state)

/// One row of the Dictionary Order screen (Issue #92: pair-level).
struct DictionaryItem: Identifiable, Equatable {
    var id: String { pair.id }
    let pair: DictionaryPair
    /// Localised row title, resolved by `SettingsViewModel.displayName(for:locale:)`.
    let displayName: String
    var isEnabled: Bool

    /// Summed entry count across the pair's sources.
    var count: Int { pair.count }
}
