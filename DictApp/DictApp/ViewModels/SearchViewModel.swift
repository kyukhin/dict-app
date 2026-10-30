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

    /// The dictionary chips under the search field (Issue #145): the same
    /// pair list and setting as Settings → Dictionary Order.
    let selection: DictionarySelection

    /// With a query and every pair off, Search shows "Choose a dictionary"
    /// instead of results (Issue #145). An empty field keeps Recent words.
    var showsNoDictionariesHint: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && selection.noneEnabled
    }

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(150)

    private let db: DatabaseService
    private let settings: SettingsService
    private var cancellables: Set<AnyCancellable> = []

    /// What a chip change is compared on: the pairs' order, states, sources
    /// and entry counts. A struct because tuples are not `Equatable`. An
    /// import named like a bundled source (#105) keeps the pair's source IDs,
    /// since the dictionary file has every bundled ID; only the count shows it.
    private struct PairState: Equatable {
        let id: String
        let isEnabled: Bool
        let sourceIDs: [String]
        let count: Int
    }

    /// A `nil` selection is `.shared` for the app's settings, or a new one
    /// over a test's own settings (`DictionarySelection.owning`).
    init(db: DatabaseService = .shared,
         settings: SettingsService = .shared,
         selection: DictionarySelection? = nil) {
        self.db = db
        self.settings = settings
        self.selection = selection ?? .owning(settings, db: db)

        // Issue #139: Search answers from the dictionary file while a 1.x
        // database moves in. When the move commits, re-run the current query
        // once, so the moved imports show without retyping. A no-op on an
        // empty query.
        NotificationCenter.default.publisher(for: LegacyMigration.didCommit)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)

        // Issue #145: a chip (or a Settings switch, a reorder, an import that
        // reloads the list) re-runs the current query at once. The selection writes the store before it
        // publishes, so `onQueryChanged` reads the new setting; the debounce
        // folds quick taps into one query. A title-only change (language
        // switch) re-runs nothing.
        self.selection.$pairs
            .map { $0.map { PairState(id: $0.id, isEnabled: $0.isEnabled, sourceIDs: $0.pair.sourceIDs, count: $0.count) } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)
        // The hint reads the selection, so re-render with it.
        self.selection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
        // Issue #92: preferred mode buckets per language pair, so split the
        // source order into pair groups (pure, no DB) at keystroke time.
        let groups = DictionaryGrouping.sourceGroups(order: order)

        searchTask = Task { [trimmed, db, enabledSources, mode, order, groups] in
            // Debounce: wait briefly so we don't hammer the DB on every keystroke.
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            do {
                let found: [DictionaryEntry]
                if mode == .preferredDictionary, !order.isEmpty {
                    // nil enabledSources = all enabled → all known (ordered) sources.
                    let effectiveEnabled = enabledSources ?? Set(order)
                    found = try await db.searchPreferred(
                        query: trimmed, groups: groups, enabledSources: effectiveEnabled
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
    /// retyping, and at once after a chip change (Issue #145). No-ops on an
    /// empty query, so it does NOT fire (or double-fire) on initial view
    /// load — the field starts empty.
    func refreshIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onQueryChanged()
    }
}
