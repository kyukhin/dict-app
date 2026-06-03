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
    var lookedAt: String?

    static let databaseTableName = "history"

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case lookedAt = "looked_at"
    }
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

struct SourceStat: Identifiable, Equatable {
    var id: String { source }
    let source: String
    let displayName: String
    let count: Int
}

// MARK: - DictionaryItem (Settings UI model with enabled state)

struct DictionaryItem: Identifiable, Equatable {
    var id: String { source }
    let source: String
    let displayName: String
    let count: Int
    var isEnabled: Bool
}
