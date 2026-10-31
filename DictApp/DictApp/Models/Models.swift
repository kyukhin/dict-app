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

    /// Human-readable source label for display (the search-result badge).
    /// Bilingual bundled sources show direction + provider (Issue #87):
    /// en dash U+2013, then " · " (U+00B7 between spaces), then `FD` / `WN`.
    /// The visible text stays untranslated; VoiceOver reads the localized
    /// `SettingsViewModel.badgeAccessibilityLabel(forSource:locale:)`.
    var sourceLabel: String {
        switch source {
        case "wordnet":          return "WordNet"
        case "openrussian":      return "OpenRussian"
        // Badge is space-constrained; the full name lives in
        // `dict_metadata.display_name` (Settings + DictionaryDetailView).
        case "freedict-eng-spa": return "En\u{2013}Es \u{00B7} FD"
        case "wordnet-spa-eng":  return "Es\u{2013}En \u{00B7} WN"
        case "wordnet-arb-eng":  return "Ar\u{2013}En \u{00B7} WN"
        case "freedict-ell-eng": return "El\u{2013}En \u{00B7} FD"
        case "wordnet-ell-eng":  return "El\u{2013}En \u{00B7} WN"
        case "freedict-eng-ell": return "En\u{2013}El \u{00B7} FD"
        case "wordnet-eng-ell":  return "En\u{2013}El \u{00B7} WN"
        default:                 return source.capitalized
        }
    }
}

// MARK: - HistoryItem

/// `Hashable` so Search's Recent words can push it (`NavigationLink(value:)`).
struct HistoryItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
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

// MARK: - EntryKey (Issue #138)

/// The stable key of a dictionary entry: its source ID and its headword as
/// stored. User data (History, My words) points at entries by this key,
/// never by a row id, so it survives a new dictionary file. Resolution is
/// case-insensitive on `word` (`DatabaseService.entry(for:)`).
struct EntryKey: Hashable, Sendable {
    let source: String
    let word: String

    init(source: String, word: String) {
        self.source = source
        self.word = word
    }

    init(_ entry: DictionaryEntry) {
        self.init(source: entry.source, word: entry.word)
    }
}

// MARK: - Search by any form (Issue #142)

/// Why the form step added a row to Search: the query is an inflected form
/// of `lemma` (0136-word-forms.md, "Search path"). Captioned by
/// `FormCaption`; never persisted.
struct FormMatch: Hashable, Sendable {
    /// What the form step knows about the query as a form of the lemma.
    enum Analysis: Hashable, Sendable {
        /// Greek: the Wiktextract tags of the form's caption tag set
        /// (`dict.form_lookup.tagset_id`), e.g. aorist 1sg is `active
        /// first-person indicative past perfective singular`.
        case greek(tags: Set<String>)
        // #143 adds the English analysis: morphy's pos, rule and suffix.
    }

    /// The lemma's headword (NFC), e.g. γράφω.
    let lemma: String
    let analysis: Analysis
}

/// One Search row: an entry, plus the form match that brought it in when
/// the query is an inflected form of its headword (Issue #142). Its
/// identity is the entry id, unique across the dictionary file and the
/// imports (#129).
struct SearchResult: Identifiable, Hashable, Sendable {
    let entry: DictionaryEntry
    var formMatch: FormMatch?

    init(entry: DictionaryEntry, formMatch: FormMatch? = nil) {
        self.entry = entry
        self.formMatch = formMatch
    }

    var id: Int64? { entry.id }
}

// MARK: - DictionaryFile (Issue #140)

/// The bundled, read-only dictionary file `dictionaries.sqlite`, written by
/// `Scripts/build_dictionaries.py` and attached as `dict`.
enum DictionaryFile {
    static let resourceName = "dictionaries"
    static let resourceExtension = "sqlite"

    /// The file's `PRAGMA user_version`. The app and the file ship together,
    /// so nothing checks it at runtime; a unit test checks the bundled file.
    /// A changed table shape bumps it and `FORMAT_VERSION` in the build script.
    static let formatVersion = 2
}

// MARK: - DictMetadata

/// One `dict.dict_metadata` row: a bundled dictionary (Issue #138).
struct DictMetadata: Codable, Identifiable, Equatable, FetchableRecord {
    var source: String
    var displayName: String
    var version: String
    var license: String
    var url: String
    var wordCount: Int
    var description: String

    var id: String { source }

    enum CodingKeys: String, CodingKey {
        case source
        case displayName = "display_name"
        case version
        case license
        case url
        case wordCount = "word_count"
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

/// One row of the Dictionary Order screen (Issue #92: pair-level). `Hashable`
/// for `navigationDestination(item:)` (Issue #91).
struct DictionaryItem: Identifiable, Hashable {
    var id: String { pair.id }
    let pair: DictionaryPair
    /// Localised row title, resolved by `SettingsViewModel.displayName(for:locale:)`.
    let displayName: String
    var isEnabled: Bool

    /// Summed entry count across the pair's sources.
    var count: Int { pair.count }
}
