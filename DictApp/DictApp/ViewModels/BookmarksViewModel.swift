// BookmarksViewModel.swift

import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var entries: [BookmarkedEntry] = []
    @Published var errorMessage: String?

    private let db: DatabaseService

    init(db: DatabaseService = .shared) {
        self.db = db
    }

    func load() async {
        do {
            entries = try await db.fetchBookmarkedEntries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(entryId: Int64) async {
        do {
            try await db.removeBookmark(entryId: entryId)
            entries.removeAll { $0.entry.id == entryId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
