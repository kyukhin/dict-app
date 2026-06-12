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
        // Materialise the current set from all known sources if not yet stored.
        var current = enabledSources ?? knownSources
        if enabled {
            current.insert(source)
        } else {
            current.remove(source)
        }
        enabledSources = current
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
