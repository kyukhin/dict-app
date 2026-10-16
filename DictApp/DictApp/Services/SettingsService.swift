// SettingsService.swift
// Service for managing app settings persistence.
//
// All persistence flows through an injected `KeyValueStore` (Issue #6) — a thin
// seam so #73 can swap UserDefaults for an iCloud-backed store without touching
// any consumer. The UserDefaults *key strings* are unchanged from before the
// seam (`ui_language`, `enabled_sources`), so routing everything through the
// store is a pure internal refactor with no data migration / user-facing reset.

import Foundation

// MARK: - KeyValueStore seam (Issue #6, load-bearing for #73)
//
// A `UserDefaults` adapter today; #73 (iCloud preference sync) swaps in an
// `NSUbiquitousKeyValueStore`/composite adapter with zero changes to any
// consumer — `SettingsService` is the only code that touches this protocol.
// Chosen over a property-wrapper (hard-binds to UserDefaults, leaks the backend
// to every call site; iCloud's async-merge model doesn't fit a synchronous
// wrapper) and over a bare struct (no behavioural seam for change-notification /
// conflict handling). Mirrors the `LocalizationManager` pattern (injectable
// deps + `.shared`). Kept in this file per design §8 ("or a new KeyValueStore.swift").
protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ string: String?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {
    // `data(forKey:)`, `string(forKey:)` and `removeObject(forKey:)` already
    // satisfy the protocol. The nil-tolerant typed setters forward to the
    // built-in `set(_ value: Any?, forKey:)` via an `as Any?` cast — passing the
    // unwrapped value directly would re-resolve to these typed overloads and
    // recurse.
    func set(_ data: Data?, forKey key: String) {
        if let data { set(data as Any?, forKey: key) } else { removeObject(forKey: key) }
    }

    func set(_ string: String?, forKey key: String) {
        if let string { set(string as Any?, forKey: key) } else { removeObject(forKey: key) }
    }
}

final class SettingsService {
    static let shared = SettingsService()

    private let store: KeyValueStore
    private let uiLanguageKey = "ui_language"
    private let enabledSourcesKey = "enabled_sources"
    private let dictionaryOrderKey = "dictionary_order"
    private let resultSortModeKey = "result_sort_mode"

    /// Injectable for tests (pass an in-memory `KeyValueStore`); production uses
    /// `.shared`, which backs onto `UserDefaults.standard`.
    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// Persisted BCP-47 code of the user's chosen UI language. Returns `nil`
    /// when no preference has been stored yet, leaving the choice up to the
    /// caller (typically: pick the system locale's language if supported).
    ///
    /// We store only the code; resolving it to a `UILanguage` requires the
    /// supported-locales manifest, which the `LocalizationManager` owns.
    var selectedUILanguageCode: String? {
        get { store.string(forKey: uiLanguageKey) }
        set { store.set(newValue, forKey: uiLanguageKey) }
    }

    // MARK: - Enabled Sources

    /// The set of source identifiers the user has enabled.
    /// When nil (key absent = first launch), all sources are treated as enabled.
    var enabledSources: Set<String>? {
        get {
            guard let data = store.data(forKey: enabledSourcesKey),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil // nil = "all enabled" (first-launch default)
            }
            return Set(array)
        }
        set {
            if let newValue {
                store.set(try? JSONEncoder().encode(Array(newValue)), forKey: enabledSourcesKey)
            } else {
                store.removeObject(forKey: enabledSourcesKey)
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
        setEnabled(enabled, forSources: [source], knownSources: knownSources)
    }

    /// Enables or disables every source in `sources` in one write (Issue #92:
    /// one toggle per language pair). Materialises the current set from
    /// `knownSources` if nothing is stored yet, like the single-source variant.
    func setEnabled(_ enabled: Bool, forSources sources: [String], knownSources: Set<String>) {
        var current = enabledSources ?? knownSources
        if enabled {
            current.formUnion(sources)
        } else {
            current.subtract(sources)
        }
        enabledSources = current
    }

    /// Idempotent pair-level normalisation of the stored prefs (Issue #92 §2b):
    /// I1 — all members of a pair share one enabled state (enabled-if-any);
    /// I2 — members of a pair are contiguous at the earliest member's position.
    /// Runs at launch and on every Settings load; a fresh install (nil / nil)
    /// is a no-op. Each value is written back only when it actually changed,
    /// so there is no store churn (relevant for the #73 iCloud seam).
    func normalizeDictionaryPreferences(knownSources: [String]) {
        let enabled = enabledSources
        let normalizedEnabled = DictionaryGrouping.enabledIfAny(enabled, knownSources: knownSources)
        if normalizedEnabled != enabled {
            enabledSources = normalizedEnabled
        }

        let order = dictionaryOrder
        let normalizedOrder = order.map(DictionaryGrouping.groupedOrder)
        if normalizedOrder != order {
            dictionaryOrder = normalizedOrder
        }
    }

    // MARK: - Imported sources (Issue #105)
    //
    // Called by the import flow after a successful import, so the new source
    // is ON and searchable before any screen reloads. Both rules leave `nil`
    // alone and write only when the stored value changes (no churn for #73).

    /// Enables a freshly imported source (PM decision 2). A materialised set
    /// gains the ID in one write; `nil` (all enabled) stays `nil`, because
    /// materialising it would freeze today's source list into the store. Not
    /// `setEnabled(_:forSources:knownSources:)`, which materialises `nil`.
    func enableImportedSource(_ source: String) {
        guard let enabled = enabledSources else { return }
        // A file named like a bundled source (e.g. `wordnet-spa-eng.json`)
        // joins that pair, so switch the whole pair on (#92 invariant I1).
        let key = DictionaryGrouping.pairKey(forSource: source)
        let bundled = DictionaryGrouping.bundledSourceIDs.union(DictionaryGrouping.legacyBareIDs.keys)
        let updated = enabled.union([source]).union(bundled.filter { DictionaryGrouping.pairKey(forSource: $0) == key })
        if updated != enabled { enabledSources = updated }
    }

    /// Appends a freshly imported source to a stored order that lacks it, at
    /// the end, where a Settings reload would put it (PM decision 3). Keeps
    /// preferred-mode search, which uses `Set(dictionary_order)` as the
    /// enabled set when `enabled_sources` is `nil`, from missing the import.
    /// A `nil` order stays `nil`: the first Settings load derives the default.
    func appendImportedSourceToOrder(_ source: String) {
        guard let order = dictionaryOrder, !order.contains(source) else { return }
        dictionaryOrder = DictionaryGrouping.groupedOrder(order + [source])
    }

    // MARK: - Dictionary Order (Issue #6)

    /// The user's dictionary ordering as ordered source IDs. `nil` = not yet
    /// materialized; the orchestration layer (`SettingsViewModel`) computes the
    /// default from `fetchSourceStats()` order on first load and persists it
    /// (§6). Stored as a JSON `[String]` in `data`, same shape as
    /// `enabledSources`.
    var dictionaryOrder: [String]? {
        get {
            guard let data = store.data(forKey: dictionaryOrderKey),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            if let newValue {
                store.set(try? JSONEncoder().encode(newValue), forKey: dictionaryOrderKey)
            } else {
                store.removeObject(forKey: dictionaryOrderKey)
            }
        }
    }

    // MARK: - Result Sort Mode (Issue #6)

    /// How search results are ordered. Absent → `.relevance` (the default).
    /// Persisted as the enum `rawValue` string.
    var resultSortMode: ResultSortMode {
        get { ResultSortMode(rawValue: store.string(forKey: resultSortModeKey) ?? "") ?? .relevance }
        set { store.set(newValue.rawValue, forKey: resultSortModeKey) }
    }
}

// MARK: - Default dictionary order (Issue #74)

/// Pure default-value logic for the first-launch dictionary order. No
/// persistence: `SettingsViewModel.loadDictionaries()` calls this only when
/// `SettingsService.dictionaryOrder` is still `nil`, so a user-configured order
/// is never overridden. Kept in this file (not a new one) because the app target
/// is not a synchronized folder and adding a file would require a pbxproj edit.
enum DictionaryDefaults {
    /// Source IDs that serve a given UI language, in preferred order.
    /// Languages not listed (or IDs not present in `sources`) fall through to
    /// the incoming order unchanged.
    static let preferredSources: [String: [String]] = [
        "en": ["wordnet"],
        "ru": ["openrussian"],
        "es": ["wordnet-spa-eng", "freedict-eng-spa"],
        "ar": ["wordnet-arb-eng"],
    ]

    /// Returns `sources` reordered so the language's preferred dictionaries
    /// come first (in mapping order), followed by the remaining sources in
    /// their original relative order. Preferred IDs absent from `sources` are
    /// skipped; the result is always a permutation of `sources`.
    static func defaultOrder(for language: UILanguage, sources: [String]) -> [String] {
        defaultOrder(forLanguageCode: language.code, sources: sources)
    }

    static func defaultOrder(forLanguageCode code: String, sources: [String]) -> [String] {
        let preferred = (preferredSources[code] ?? []).filter { sources.contains($0) }
        return preferred + sources.filter { !preferred.contains($0) }
    }
}

// MARK: - Language-pair grouping (Issue #92)

/// Pure pair→sources grouping over source IDs. No persistence, no database,
/// no locale: the pair of a source is a function of its ID alone, following
/// the `Scripts/build_seed.py` naming convention (bare provider name for the
/// legacy monolingual / unambiguous bundles, `provider-src-tgt` with ISO-639-3
/// codes for bilingual ones). Kept in this file next to `DictionaryDefaults`
/// for the same reason (the app target is not a synchronized folder).
///
/// Pair keys (`eng`, `eng-spa`, `custom:<id>`) are runtime-only: they serve as
/// UI model ids, accessibility ids and search bucket keys, and are never
/// persisted — `enabled_sources` / `dictionary_order` stay keyed by source ID.
enum DictionaryGrouping {
    /// Legacy bare IDs that predate the `provider-src-tgt` convention.
    /// Languages are in translation direction (source → target).
    static let legacyBareIDs: [String: [String]] = [
        "wordnet": ["eng"],
        "openrussian": ["rus", "eng"],
    ]

    /// Exact bilingual `provider-src-tgt` IDs shipped in the seed. Only these
    /// may merge into a pair: imports take their ID from the file name and
    /// write no `dict_metadata` row, so `freedict-spa-eng.json` must stay
    /// custom (PM decision #2). A new bundled dictionary is one entry here.
    static let bundledSourceIDs: Set<String> = ["wordnet-spa-eng", "freedict-eng-spa", "wordnet-arb-eng"]

    /// Splits a source ID into provider, languages (in translation direction,
    /// ISO-639-3) and whether it is a custom import. Custom sources report the
    /// raw ID as provider and no languages.
    static func parse(sourceID id: String) -> (provider: String, languages: [String], isCustom: Bool) {
        if let languages = legacyBareIDs[id] {
            return (id, languages, false)
        }
        if bundledSourceIDs.contains(id) {
            let parts = id.split(separator: "-").map(String.init)
            return (parts[0], [parts[1], parts[2]], false)
        }
        return (id, [], true)
    }

    /// Direction-agnostic pair key: sorted languages joined by `-` for bundled
    /// sources (`wordnet-spa-eng` and `freedict-eng-spa` both → `eng-spa`),
    /// `custom:<id>` for everything else (the prefix rules out a collision
    /// with an import named like a key, e.g. `eng.json`).
    static func pairKey(forSource id: String) -> String {
        let parsed = parse(sourceID: id)
        if parsed.isCustom { return "custom:" + id }
        return parsed.languages.sorted().joined(separator: "-")
    }

    /// `order` split into pair groups by first occurrence; members keep their
    /// relative order from `order`. Used by preferred-dictionary search (one
    /// bucket per group).
    static func sourceGroups(order: [String]) -> [[String]] {
        let keys = order.map(pairKey(forSource:))
        var taken = [Bool](repeating: false, count: order.count)
        var groups: [[String]] = []
        for i in order.indices where !taken[i] {
            var group: [String] = []
            for j in i..<order.count where !taken[j] && keys[j] == keys[i] {
                group.append(order[j])
                taken[j] = true
            }
            groups.append(group)
        }
        return groups
    }

    /// Permutation of `order` enforcing I2: when a pair's earliest member is
    /// reached, it is emitted followed by the pair's later members (in their
    /// existing relative order), which are skipped where they originally
    /// stood. Idempotent; already-grouped input is returned unchanged.
    static func groupedOrder(_ order: [String]) -> [String] {
        sourceGroups(order: order).flatMap { $0 }
    }

    /// Enforces I1 (enabled-if-any) on a stored enabled set: every known or
    /// listed source whose pair has at least one enabled member becomes
    /// enabled. `nil` (all enabled) stays `nil`; `{}` stays `{}`. IDs present
    /// in `enabled` but absent from `knownSources` are kept verbatim (the
    /// pre-existing tolerance for removed sources).
    static func enabledIfAny(_ enabled: Set<String>?, knownSources: [String]) -> Set<String>? {
        guard let enabled else { return nil }
        let enabledKeys = Set(enabled.map(pairKey(forSource:)))
        let universe = Set(knownSources).union(enabled)
        return Set(universe.filter { enabledKeys.contains(pairKey(forSource: $0)) })
    }

    /// One `DictionaryPair` per group of `sourceGroups(order:)`, with `sources`
    /// resolved from `stats` in group order. IDs missing from `stats` are
    /// dropped; a group with no resolvable member yields no pair.
    static func pairs(from stats: [SourceStat], order: [String]) -> [DictionaryPair] {
        let bySource = Dictionary(stats.map { ($0.source, $0) }, uniquingKeysWith: { a, _ in a })
        return sourceGroups(order: order).compactMap { group in
            let members = group.compactMap { bySource[$0] }
            guard let first = members.first else { return nil }
            let parsed = parse(sourceID: first.source)
            return DictionaryPair(
                id: pairKey(forSource: first.source),
                languages: parsed.isCustom ? [] : parsed.languages.sorted(),
                isCustom: parsed.isCustom,
                sources: members
            )
        }
    }
}
