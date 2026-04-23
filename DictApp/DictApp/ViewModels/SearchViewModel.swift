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

    init(db: DatabaseService = .shared) {
        self.db = db
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

        searchTask = Task { [trimmed, db] in
            // Debounce: wait briefly so we don't hammer the DB on every keystroke.
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            do {
                let found = try await db.search(query: trimmed)
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
}
