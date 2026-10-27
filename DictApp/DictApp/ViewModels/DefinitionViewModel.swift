// DefinitionViewModel.swift

import Foundation

@MainActor
final class DefinitionViewModel: ObservableObject {
    @Published var isBookmarked: Bool = false
    @Published var errorMessage: String?

    let entry: DictionaryEntry
    /// Issue #202: the headword's voice language. Without that voice the
    /// speaker button is hidden rather than reading the word in another language.
    let speechLanguage: String
    let canSpeak: Bool
    private let db: DatabaseService

    init(entry: DictionaryEntry, db: DatabaseService = .shared,
         hasVoice: (String) -> Bool = SpeechService.hasVoice(for:)) {
        self.entry = entry
        self.db = db
        speechLanguage = SpeechService.language(forSource: entry.source)
        canSpeak = hasVoice(speechLanguage)
    }

    func onAppear() async {
        guard let id = entry.id else { return }
        do {
            try await db.addToHistory(word: entry.word, source: entry.source)
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
        SpeechService.shared.speak(entry.word, language: speechLanguage)
    }
}
