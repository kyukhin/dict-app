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
    /// 0132, #168: the verb Practise drills, from the table's paradigm, with
    /// its translation in the meanings language of Greek's pair; nil for a
    /// noun, an adjective, another source, or a verb with no question.
    @Published private(set) var drillVerb: DrillVerb?
    /// "Learn Greek via English?" (Greek's pair), asked by Practise while
    /// Greek is not a learned language; nil when not shown.
    @Published var practiseQuestion: LearningPair?
    /// The Practise run to present; nil when none.
    @Published var practiseRun: PractiseRun?
    /// 0133, #174: the grammar topics that apply to a Greek headword, in
    /// level and topic order, titled in Greek's explanation language; empty
    /// for other sources and without the Greek pack.
    @Published private(set) var grammarTopics: [GrammarTopicSummary] = []

    /// A single-verb drill (0132, "A single verb").
    struct PractiseRun: Identifiable {
        let id = UUID()
        let verb: DrillVerb
        /// The drill's tense level; the run raises it to the verb's first
        /// level with a question.
        let level: DrillLevel
        let meaningsLang: String
    }

    /// 0134, #178: the examples of the entry's word (`wordKey(for:)`), in
    /// the build's order; empty for words without examples.
    @Published private(set) var examples: [ExampleSentence] = []

    let entry: DictionaryEntry
    /// Issue #325: what the speaker reads, the search target
    /// (`SpeechService.target`): the headword, or the first sense line of
    /// its translation when a search matched the headword.
    let speechText: String
    /// Issue #202: the voice language of `speechText`. Without that voice the
    /// speaker button is hidden rather than reading the text in another language.
    let speechLanguage: String
    let canSpeak: Bool
    private let db: DatabaseService
    private let settings: SettingsService
    private let languages: LearningLanguageService
    private let clock: LearningClock
    /// The entry's word (`wordKey(for:)`), known after `onAppear`.
    private var wordKey: WordKey?
    /// The meanings language of `drillVerb`'s translation.
    private var drillMeaningsLang = "eng"

    /// `searchSide`: the side of the entry the Search row matched (#325);
    /// `nil` when the entry was opened elsewhere.
    init(entry: DictionaryEntry, searchSide: SearchSide? = nil, db: DatabaseService = .shared,
         settings: SettingsService = .shared, languages: LearningLanguageService? = nil,
         clock: LearningClock = LearningClock(), hasVoice: (String) -> Bool = SpeechService.hasVoice(for:)) {
        self.entry = entry
        self.db = db
        self.settings = settings
        self.languages = languages ?? .shared
        self.clock = clock
        let speech = SpeechService.target(for: entry, side: searchSide)
        speechText = speech.text
        speechLanguage = speech.language
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
        SpeechService.shared.speak(speechText, language: speechLanguage)
    }

    // MARK: - Issue #144: inflection table

    /// Loads the table of a Greek headword, its labels in the language of
    /// `locale`, then the grammar topics that apply to it, with or without
    /// a table (0133, #174). Other sources read nothing. A table and its
    /// topics are extra: a failed read leaves the screen without them.
    func loadInflection(locale: Locale) async {
        guard InflectionLookup.sources.contains(entry.source) else { return }
        let paradigm = try? await db.inflection(for: entry)
        let table = paradigm.flatMap { ParadigmLayout.table(for: $0, locale: locale) }
        inflectionTable = table
        // 0132, #168: a conjugation table with a question gives Practise.
        if let paradigm, table?.kind == .conjugation,
           let verb = DrillVerb.make(word: entry.word, paradigm: paradigm, translation: "") {
            drillVerb = verb.translated(await drillTranslation(of: verb))
        }
        await loadGrammar(paradigm: table == nil ? nil : paradigm)
    }

    // MARK: - 0133, #174: grammar topics

    /// The topics that apply to the entry (`GrammarLinks.topics`): by its
    /// headword or its table's lemma, by the classes of the table it shows
    /// (`paradigm`, nil without one) or else of its part of speech, and the
    /// tenses of its verb. Greek's links and topics, read on each use.
    private func loadGrammar(paradigm: LemmaParadigm?) async {
        let lang = ConjugationPlanner.lang
        do {
            let links = try await db.grammarLinks(lang: lang)
            guard !links.isEmpty else { return }
            let topics = try await db.grammarTopics(lang: lang,
                                                    explainLang: try await languages.explanationLanguage(of: lang))
            let subject = GrammarSubject(headword: entry.word, paradigm: paradigm, entryPOS: entry.pos)
            grammarTopics = GrammarLinks.topics(for: subject, topics: topics, links: links)
        } catch {
            grammarTopics = []
        }
    }

    // MARK: - 0132, #168: Practise

    /// The drilled word's meaning (πηγαίνω for πάω) in the meanings language
    /// of Greek's pair, its stored via or else its default: 0131's
    /// `meanings`, the first of the pair's dictionaries in Dictionary Order
    /// that has it. "" when none has.
    private func drillTranslation(of verb: DrillVerb) async -> String {
        let lang = ConjugationPlanner.lang
        do {
            guard let meaningsLang = try await languages.pair(for: lang)?.meaningsLang else { return "" }
            drillMeaningsLang = meaningsLang
            let sourceOrder = try await languages.sourceOrder(lang: lang, meaningsLang: meaningsLang)
            let key = WordKey(lang: lang, word: verb.word)
            let meanings = try await db.meanings(of: [MeaningQuery(key: key, lookup: verb.word)], lang: lang,
                                                 meaningsLang: meaningsLang, sourceOrder: sourceOrder)
            return meanings[key] ?? ""
        } catch {
            return ""
        }
    }

    /// Practise: the verb's drill at once when Greek is learned; otherwise
    /// E4's "Learn Greek via English?" first (Kirill, 2026-11-04).
    func practise() async {
        guard let drillVerb else { return }
        let lang = ConjugationPlanner.lang
        guard languages.isLearned(lang) else {
            do {
                practiseQuestion = try await languages.pair(for: lang)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        startPractise(drillVerb)
    }

    /// The answer to `practiseQuestion`: Yes learns Greek through that pair
    /// (`learn(language:)`, as Learn does), then starts the drill; No
    /// cancels it, and nothing changes.
    func answerPractise(yes: Bool) async {
        practiseQuestion = nil
        guard yes, let drillVerb else { return }
        do {
            try await languages.learn(language: ConjugationPlanner.lang)
            try await refreshLearning()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        startPractise(drillVerb)
    }

    /// The single-verb run at the drill's tense level ("Tenses up to", or
    /// A1 with no Greek list checked).
    private func startPractise(_ verb: DrillVerb) {
        let level = DrillScope.tenseLevel(checked: settings.learningListIDs, stored: settings.learningDrillTenses)
        practiseRun = PractiseRun(verb: verb, level: level, meaningsLang: drillMeaningsLang)
    }

    // MARK: - 0134, #178: example sentences

    /// Loads the examples of the entry's `WordKey`: γράφω from El–En · FD
    /// and from El–En · WN shows the same ones. Examples are extra: a failed
    /// read leaves the screen without them.
    func loadExamples() async {
        guard let key = try? await db.wordKey(for: EntryKey(entry)),
              let found = try? await db.examples(for: key) else { return }
        examples = found
    }
}
