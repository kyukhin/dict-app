// BookmarksViewModel.swift
// Issue #138: until #158 replaces the tab, Bookmarks lists My words.

import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    /// My words that resolve, newest first.
    @Published var entries: [DictionaryEntry] = []
    @Published var errorMessage: String?

    private let db: DatabaseService

    init(db: DatabaseService = .shared) {
        self.db = db
    }

    func load() async {
        do {
            entries = try await db.fetchMyWords()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ entry: DictionaryEntry) async {
        do {
            try await db.removeFromMyWords(EntryKey(entry))
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
