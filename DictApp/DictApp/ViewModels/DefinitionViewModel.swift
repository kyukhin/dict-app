// DefinitionViewModel.swift

import Foundation

@MainActor
final class DefinitionViewModel: ObservableObject {
    @Published var isBookmarked: Bool = false
    @Published var errorMessage: String?

    let entry: DictionaryEntry
    private let db: DatabaseService

    init(entry: DictionaryEntry, db: DatabaseService = .shared) {
        self.entry = entry
        self.db = db
    }

    func onAppear() async {
        guard let id = entry.id else { return }
        do {
            try await db.addToHistory(word: entry.word)
            isBookmarked = try await db.isBookmarked(entryId: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleBookmark() async {
        guard let id = entry.id else { return }
        do {
            if isBookmarked {
                try await db.removeBookmark(entryId: id)
            } else {
                try await db.addBookmark(entryId: id)
            }
            isBookmarked.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func speak() {
        SpeechService.shared.speak(entry.word)
    }
}
