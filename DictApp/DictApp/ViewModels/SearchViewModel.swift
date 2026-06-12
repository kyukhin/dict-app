// SearchViewModel.swift
// Debounced search-as-you-type against the SQLite FTS5 index.

import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [DictionaryEntry] = []
    @Published var recentWords: [HistoryItem] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(150)

    private let db: DatabaseService
    private let settings: SettingsService

    init(db: DatabaseService = .shared, settings: SettingsService = .shared) {
        self.db = db
        self.settings = settings
    }

    func loadRecent() async {
        recentWords = (try? await db.fetchHistory(limit: 10)) ?? []
    }

    /// Call this from `.onChange(of: query)` in the view.
    func onQueryChanged() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        // Capture the relevant settings at the moment the query fires (Issue #6:
        // also the sort mode + dictionary order). nil enabledSources means "all
        // enabled" (first-launch default); empty set means "none enabled".
        let enabledSources: Set<String>? = settings.enabledSources
        let mode = settings.resultSortMode
        let order = settings.dictionaryOrder ?? []

        searchTask = Task { [trimmed, db, enabledSources, mode, order] in
            // Debounce: wait briefly so we don't hammer the DB on every keystroke.
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            do {
                let found: [DictionaryEntry]
                if mode == .preferredDictionary, !order.isEmpty {
                    // nil enabledSources = all enabled → all known (ordered) sources.
                    let effectiveEnabled = enabledSources ?? Set(order)
                    found = try await db.searchPreferred(
                        query: trimmed, order: order, enabledSources: effectiveEnabled
                    )
                } else {
                    found = try await db.search(query: trimmed, enabledSources: enabledSources)
                }
                guard !Task.isCancelled else { return }
                self.results = found
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
            }
            self.isSearching = false
        }
    }

    /// Re-runs the current query (Issue #6 §3d) so returning to Search after a
    /// sort-mode / dictionary-order change in Settings reflects it without
    /// retyping. No-ops on an empty query, so it does NOT fire (or double-fire)
    /// on initial view load — the field starts empty.
    func refreshIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onQueryChanged()
    }
}
