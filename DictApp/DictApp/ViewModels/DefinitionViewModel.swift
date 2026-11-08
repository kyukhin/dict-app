// DefinitionViewModel.swift

import Foundation

@MainActor
final class DefinitionViewModel: ObservableObject {
    /// What the Learn button shows and does (0131, "Learn on the
    /// Definition screen", #158).
    enum LearnAction: Equatable {
        /// An outlined cap: adds the entry to My words and learns the word,
        /// or asks first when its language is not learned (`LearnQuestion`).
        case learn
        /// A filled cap: the word leaves My words and its cards are paused.
        case stopLearning
        /// A filled cap: the word is in My words, its language not learned.
        case removeFromMyWords
    }

    /// What Learn asks on a word of a language not learned.
    enum LearnQuestion: Equatable {
        /// "Learn Spanish via English?": the language's pair (its stored
        /// via, else its default); a limited pair's warning is the message.
        case pair(LearningPair)
        /// 0130's "Learn lists in other languages?": a language without a
        /// pair, learned on its own (Other).
        case other(lang: String)
    }

    /// The word in learning with its cards, paused ones included; nil when
    /// it was never enrolled.
    @Published private(set) var learning: WordLearningState?
    /// 0166, #165: every wrong answer on the word's two cards, ever; 0 when
    /// it is not in learning or paused.
    @Published private(set) var errorCount = 0
    /// My words holds the word, from this dictionary or another.
    @Published private(set) var isInMyWords = false
    @Published private(set) var isLanguageLearned = false
    /// The alert Learn shows; nil when none is shown.
    @Published var question: LearnQuestion?
    @Published var errorMessage: String?
    /// Issue #144: the Greek headword's inflection table; nil for other
    /// sources and for words without one.
    @Published private(set) var inflectionTable: InflectionTable?

    let entry: DictionaryEntry
    /// Issue #202: the headword's voice language. Without that voice the
    /// speaker button is hidden rather than reading the word in another language.
    let speechLanguage: String
    let canSpeak: Bool
    private let db: DatabaseService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    /// The entry's word (`wordKey(for:)`), known after `onAppear`.
    private var wordKey: WordKey?

    init(entry: DictionaryEntry, db: DatabaseService = .shared,
         languages: LearningLanguageService? = nil, clock: LearningClock = LearningClock(),
         hasVoice: (String) -> Bool = SpeechService.hasVoice(for:)) {
        self.entry = entry
        self.db = db
        self.languages = languages ?? .shared
        self.clock = clock
        speechLanguage = SpeechService.language(forSource: entry.source)
        canSpeak = hasVoice(speechLanguage)
    }

    var learnAction: LearnAction {
        if let learning, !learning.isPaused {
            return isInMyWords && !isLanguageLearned ? .removeFromMyWords : .stopLearning
        }
        return isInMyWords ? .removeFromMyWords : .learn
    }

    /// The History write and the Learn button's state, each on its own: a
    /// failed write still shows the button right. The first error shows.
    func onAppear() async {
        var failure: (any Error)?
        do {
            try await db.addToHistory(word: entry.word, source: entry.source)
        } catch {
            failure = error
        }
        do {
            try await refreshLearning()
        } catch {
            failure = failure ?? error
        }
        if let failure {
            errorMessage = failure.localizedDescription
        }
    }

    /// The Learn button. Learn on a word of a learned language adds it to
    /// My words and learns it at once (a stopped word resumes with its
    /// progress); of another language it asks `LearnQuestion` first. Stop
    /// learning and Remove from My words remove every My words row of the
    /// word and pause its cards.
    func toggleLearn() async {
        do {
            switch learnAction {
            case .learn:
                guard let wordKey else { return }
                guard isLanguageLearned else {
                    question = try await languages.pair(for: wordKey.lang).map(LearnQuestion.pair)
                        ?? .other(lang: wordKey.lang)
                    return
                }
                try await db.learnWord(EntryKey(entry), today: clock.today)
            case .stopLearning, .removeFromMyWords:
                try await db.stopLearning(EntryKey(entry))
            }
            try await refreshLearning()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The answer to `question` (Kirill, 2026-11-03 and 2026-11-04): Yes
    /// learns the pair, as the picker does, or the language alone, then the
    /// word; No only adds the word to My words, without cards, until its
    /// language is chosen.
    func answer(_ question: LearnQuestion, yes: Bool) async {
        self.question = nil
        do {
            if yes {
                switch question {
                case let .pair(pair): try await languages.learn(pair)
                case let .other(lang): try await languages.learn(language: lang)
                }
                try await db.learnWord(EntryKey(entry), today: clock.today)
            } else {
                try await db.addToMyWords(EntryKey(entry))
            }
            try await refreshLearning()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLearning() async throws {
        let key = try await db.wordKey(for: EntryKey(entry))
        wordKey = key
        let state = try await db.learningState(of: key)
        var errors = 0
        if let state, !state.isPaused {
            errors = try await db.errorCount(lang: key.lang, word: key.word)
        }
        learning = state
        errorCount = errors
        isInMyWords = try await db.isInMyWords(key)
        isLanguageLearned = languages.isLearned(key.lang)
    }

    /// 0166, #165: the word's learning status under the part of speech, in
    /// the in-app language (`locale`); empty when the word is not in
    /// learning, is paused, or its language is not learned (a stopped
    /// language's numbers are hidden, 0166 Decisions, 2026-11-03).
    func statusLines(locale: Locale) -> [String] {
        guard let learning, isLanguageLearned else { return [] }
        return WordStatusText.lines(state: learning, errors: errorCount, today: clock.today, locale: locale)
    }

    func speak() {
        SpeechService.shared.speak(entry.word, language: speechLanguage)
    }

    // MARK: - Issue #144: inflection table

    /// Loads the table of a Greek headword, its labels in the language of
    /// `locale`. Other sources read nothing. A table is extra: a failed read
    /// leaves the screen without one.
    func loadInflection(locale: Locale) async {
        guard InflectionLookup.sources.contains(entry.source) else { return }
        guard let paradigm = try? await db.inflection(for: entry) else { return }
        inflectionTable = ParadigmLayout.table(for: paradigm, locale: locale)
    }
}
