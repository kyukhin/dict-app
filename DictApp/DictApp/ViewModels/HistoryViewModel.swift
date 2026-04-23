// HistoryViewModel.swift

import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var errorMessage: String?

    private let db: DatabaseService

    init(db: DatabaseService = .shared) {
        self.db = db
    }

    func load() async {
        do {
            items = try await db.fetchHistory()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() async {
        do {
            try await db.clearHistory()
            items = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
