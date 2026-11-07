// BookmarksViewModel.swift
// Issue #138: until #158 replaces the tab, Bookmarks lists My words.

import Combine
import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    /// One My words row: its key, and its entry; none while the
    /// dictionary's pack is not installed (#245), when the row opens the
    /// "not downloaded" view.
    struct Row: Identifiable, Equatable {
        let key: EntryKey
        let entry: DictionaryEntry?

        var id: EntryKey { key }
    }

    /// My words newest first: those that resolve, and those waiting for
    /// their pack.
    @Published private(set) var rows: [Row] = []
    @Published var errorMessage: String?

    /// The rows that resolve.
    var entries: [DictionaryEntry] { rows.compactMap(\.entry) }

    private let db: DatabaseService
    private var cancellables: Set<AnyCancellable> = []

    init(db: DatabaseService = .shared) {
        self.db = db
        // #245: a pack installed or removed resolves its rows, or puts them
        // back to waiting.
        NotificationCenter.default.publisher(for: PackService.didChange, object: PackService.shared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.load() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        do {
            rows = try await db.fetchMyWordRows().map { Row(key: $0.key, entry: $0.entry) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ entry: DictionaryEntry) async {
        await remove(EntryKey(entry))
    }

    func remove(_ key: EntryKey) async {
        do {
            try await db.removeFromMyWords(key)
            rows.removeAll { $0.key == key }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
