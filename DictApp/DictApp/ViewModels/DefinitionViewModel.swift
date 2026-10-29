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
        do {
            try await db.addToHistory(word: entry.word, source: entry.source)
            isBookmarked = try await db.isInMyWords(EntryKey(entry))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Issue #138: until #158, the star adds the entry to My words or removes it.
    func toggleBookmark() async {
        do {
            if isBookmarked {
                try await db.removeFromMyWords(EntryKey(entry))
            } else {
                try await db.addToMyWords(EntryKey(entry))
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
