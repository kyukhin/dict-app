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

    /// Issue #111: share of the bundled dictionaries unpacked so far, floored
    /// to whole percents (never "100%" before the end); `nil` when no unpack
    /// is running. Drives the progress bar on the Search screen.
    @Published private(set) var unpackFraction: Double?

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(150)

    private let db: DatabaseService
    private let settings: SettingsService
    private var cancellables: Set<AnyCancellable> = []

    /// `DictionaryUnpackStatus.shared` is `@MainActor`-isolated, so it cannot
    /// be a default-value expression (evaluated in the caller's context);
    /// accept `nil` and resolve `.shared` in the isolated body, as
    /// `SettingsViewModel.init` does.
    init(db: DatabaseService = .shared, settings: SettingsService = .shared,
         unpackStatus: DictionaryUnpackStatus? = nil) {
        self.db = db
        self.settings = settings
        let status = unpackStatus ?? .shared

        status.$phase
            .map(Self.displayFraction(for:))
            .removeDuplicates()
            .sink { [weak self] in self?.unpackFraction = $0 }
            .store(in: &cancellables)

        // PM decision 3: when a dictionary finishes unpacking, re-run the
        // current query so its results fill in without retyping. Each
        // `.unpacking` value after the current one is a committed source;
        // `.idle` adds no data. Debounced, so dictionaries that land in quick
        // succession cost one re-run. A no-op on an empty query.
        status.$phase
            .dropFirst()
            .filter { phase in
                if case .unpacking = phase { return true }
                return false
            }
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)
    }

    /// The bar's value for `phase`: `nil` when idle, else the fraction
    /// clamped to 0...1 and floored to whole percents.
    nonisolated static func displayFraction(for phase: DictionaryUnpackStatus.Phase) -> Double? {
        guard case .unpacking(let fraction) = phase else { return nil }
        let clamped = min(max(fraction, 0), 1)
        // The epsilon keeps an exact whole percent (0.29 * 100 = 28.999…) on its value.
        return ((clamped * 100) + 1e-9).rounded(.down) / 100
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
    /// retyping. No-ops on an empty query, so it does NOT fire (or double-fire)
    /// on initial view load — the field starts empty.
    func refreshIfNeeded() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onQueryChanged()
    }
}
