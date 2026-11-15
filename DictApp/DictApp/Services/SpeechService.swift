// SpeechService.swift
// System Text-to-Speech using AVFoundation: Definition's speaker (#202,
// #325) and the words learning speaks as a question appears (#331).

import AVFoundation
import os
import UIKit

final class SpeechService {
    static let shared = SpeechService()
    /// Used on `queue` only.
    private let synthesizer = AVSpeechSynthesizer()
    /// Issue #331: speech starts on a serial queue of its own, never the
    /// main thread, as the learning sounds do (0131, Feedback): starting the
    /// audio output can block for seconds.
    private let queue: DispatchQueue
    /// Used on `queue` only: set once `setAmbient` succeeded.
    private var isAmbientSet = false
    /// Puts the audio session in `.ambient`; can throw.
    private let setAmbient: () throws -> Void
    /// Speaks on `queue`; nil: the synthesizer. Tests record instead.
    private let utterHook: ((_ text: String, _ language: String) -> Void)?
    /// Follow-up 4: counts `stop()` calls. A `speakWord` speaks only while
    /// the count is the one of its call, so a stop silences the words
    /// queued before it. Read and written from any thread.
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    /// Issue #202: BCP 47 voice per ISO 639-3 headword language of the bundled sources.
    static let voiceLanguages: [String: String] = [
        "eng": "en-US", "rus": "ru-RU", "spa": "es-ES", "arb": "ar-SA", "ell": "el-GR",
    ]

    /// Issue #202: the voice for a source's headwords, i.e. the first (source)
    /// language of `DictionaryGrouping.parse`. Imports declare no language, so
    /// they get `en-US` unless their file name is a bundled source ID.
    static func language(forSource id: String) -> String {
        DictionaryGrouping.parse(sourceID: id).languages.first.flatMap { voiceLanguages[$0] } ?? "en-US"
    }

    /// Issue #325: the ISO 639-3 language of a source's translations, the
    /// second language of `DictionaryGrouping.parse`; nil for a
    /// one-language source (WordNet) and for imports, which declare none.
    static func translationLanguage(forSource id: String) -> String? {
        DictionaryGrouping.parse(sourceID: id).languages.dropFirst().first
    }

    /// Issue #325: what Definition's speaker reads for `entry`, opened from
    /// a Search row that matched `side` (`nil`: opened elsewhere).
    static func target(for entry: DictionaryEntry, side: SearchSide?) -> SpeechTarget {
        target(for: entry, side: side,
               headwordLanguage: DictionaryGrouping.parse(sourceID: entry.source).languages.first,
               translationLanguage: translationLanguage(forSource: entry.source))
    }

    /// Issue #325 (kyukhin, 2026-11-13): the speaker reads the search
    /// target. A query that matched the headword of an entry whose
    /// translations are in another language with a voice code reads the
    /// first sense line (`Gloss.short`, as Learn shows a meaning), in that
    /// language: hello in En–El reads εμπρός, γεία σας. Everything else reads
    /// the headword in its language (`language(forSource:)`): a match only
    /// in the definition (exquisite → φίνα), a one-language source, an
    /// unknown translation language (`und`, an import), an empty sense, an
    /// entry not opened from Search. ISO 639-3 codes; pure.
    static func target(for entry: DictionaryEntry, side: SearchSide?,
                       headwordLanguage: String?, translationLanguage: String?) -> SpeechTarget {
        let headword = SpeechTarget(text: entry.word,
                                    language: headwordLanguage.flatMap { voiceLanguages[$0] } ?? "en-US")
        guard side == .headword, let translationLanguage, translationLanguage != headwordLanguage,
              let voice = voiceLanguages[translationLanguage] else { return headword }
        // Greek definitions are stored decomposed (NFD).
        let sense = Gloss.short(definition: entry.definition).precomposedStringWithCanonicalMapping
        return sense.isEmpty ? headword : SpeechTarget(text: sense, language: voice)
    }

    /// Issue #202: whether the device has a voice for `language`.
    static func hasVoice(for language: String) -> Bool {
        AVSpeechSynthesisVoice(language: language) != nil
    }

    /// The app uses `shared`; unit tests pass their own queue, session step
    /// and `utter` recorder.
    init(queue: DispatchQueue = DispatchQueue(label: "com.kyukhin.DictApp.SpeechService", qos: .userInitiated),
         setAmbient: @escaping () throws -> Void = { try AVAudioSession.sharedInstance().setCategory(.ambient) },
         utter: ((_ text: String, _ language: String) -> Void)? = nil) {
        self.queue = queue
        self.setAmbient = setAmbient
        utterHook = utter
    }

    /// Speaks nothing when the device has no voice for `language`: the default
    /// voice would read the word in another language (#202). Stops what
    /// is being spoken first.
    func speak(_ text: String, language: String) {
        queue.async { [self] in
            utter(text, language: language)
        }
    }

    /// Issue #331: a word learning speaks by itself, in the `.ambient`
    /// session the learning sounds use (0131, Feedback), set once: the
    /// silent switch mutes it and the user's music keeps playing. If the
    /// session cannot be set, the word is skipped and the next one tries
    /// again; a `stop()` after the call skips it too (follow-up 4).
    func speakWord(_ word: SpeechTarget) {
        let asked = generation.withLock { $0 }
        queue.async { [self] in
            if !isAmbientSet {
                do {
                    try setAmbient()
                    isAmbientSet = true
                } catch {
                    return
                }
            }
            guard generation.withLock({ $0 }) == asked else { return }
            utter(word.text, language: word.language)
        }
    }

    /// Stops what is spoken, and the words `speakWord` queued before.
    func stop() {
        generation.withLock { $0 += 1 }
        queue.async { [self] in
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// On `queue`.
    private func utter(_ text: String, language: String) {
        if let utterHook {
            utterHook(text, language)
            return
        }
        guard let voice = AVSpeechSynthesisVoice(language: language) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Issue #331 (kyukhin, 2026-11-15): the word a learning question
    /// speaks as it appears, in its language's voice; nil for none.
    /// Recognition speaks its word, what its speaker button reads; the
    /// conjugation drill the verb as its prompt cites it (γράφω, πρέπει).
    /// Production, choice and typed, and match the pairs speak nothing:
    /// their words are options or answers. Nothing when Speak words is off,
    /// while VoiceOver runs (it reads the question itself), or without a
    /// voice for the language (#202). `lang` is ISO 639-3; pure.
    static func questionWord(_ word: String, lang: String, exercise: ExerciseKind, speakWords: Bool,
                             voiceOverRunning: Bool, hasVoice: (String) -> Bool) -> SpeechTarget? {
        guard speakWords, !voiceOverRunning, !word.isEmpty else { return nil }
        switch exercise {
        case .recognition, .conjugation:
            guard let voice = voiceLanguages[lang], hasVoice(voice) else { return nil }
            return SpeechTarget(text: word, language: voice)
        case .productionChoice, .productionTyped, .match:
            return nil
        }
    }
}

/// Issue #325: what Definition's speaker reads, and with which voice
/// (`SpeechService.target`).
struct SpeechTarget: Equatable, Sendable {
    /// The headword, or the first sense line of its translation (NFC).
    let text: String
    /// The BCP 47 voice language, e.g. `el-GR`.
    let language: String
}

// MARK: - Words spoken in learning (#331)

/// Where `QuestionSpeaker` sends a question's word: the system voice in the
/// app, nothing when the app is muted, a recorder in unit tests.
@MainActor
protocol WordSpeechSink: AnyObject {
    func speak(_ word: SpeechTarget)
    func stop()
}

/// The system voice, through `SpeechService.shared`.
@MainActor
final class SystemWordSpeechSink: WordSpeechSink {
    func speak(_ word: SpeechTarget) { SpeechService.shared.speakWord(word) }
    func stop() { SpeechService.shared.stop() }
}

/// Speaks nothing: the app under XCTest or launched with `-muteSounds`
/// (`FeedbackPlayer.isMuted`). Tests never make a sound.
@MainActor
final class SilentWordSpeechSink: WordSpeechSink {
    func speak(_ word: SpeechTarget) {}
    func stop() {}
}

/// Issue #331: speaks the word a learning question shows as it appears
/// (`SpeechService.questionWord`), by the Speak words setting and
/// VoiceOver at that moment. A new question stops the word before it; the
/// runs stop it at their summary, when closed and when their screen goes.
/// The Recognition and Production runs and the conjugation drill call it;
/// match the pairs does not.
@MainActor
final class QuestionSpeaker {
    static let shared = QuestionSpeaker()

    private let settings: SettingsService
    private let sink: any WordSpeechSink
    private let voiceOverRunning: @MainActor () -> Bool
    private let hasVoice: (String) -> Bool

    init(settings: SettingsService = .shared, sink: (any WordSpeechSink)? = nil,
         voiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning },
         hasVoice: @escaping (String) -> Bool = SpeechService.hasVoice(for:)) {
        self.settings = settings
        self.sink = sink ?? (FeedbackPlayer.isMuted ? SilentWordSpeechSink() : SystemWordSpeechSink())
        self.voiceOverRunning = voiceOverRunning
        self.hasVoice = hasVoice
    }

    /// `question` appeared: speaks its word, if any, else stops the word
    /// before. Returns what it speaks: the runs show it to UI tests.
    @discardableResult
    func speak(_ question: Question) -> SpeechTarget? {
        speak(SpeechService.questionWord(question.word.term, lang: question.word.key.lang, exercise: question.exercise,
                                         speakWords: settings.learningSpeakWords,
                                         voiceOverRunning: voiceOverRunning(), hasVoice: hasVoice))
    }

    /// A drill question appeared: speaks its verb as the prompt cites it.
    @discardableResult
    func speak(_ question: ConjugationQuestion) -> SpeechTarget? {
        speak(SpeechService.questionWord(question.verb.citation, lang: ConjugationPlanner.lang, exercise: .conjugation,
                                         speakWords: settings.learningSpeakWords,
                                         voiceOverRunning: voiceOverRunning(), hasVoice: hasVoice))
    }

    /// Stops the word: a summary, a closed run, a screen left.
    func stop() {
        sink.stop()
    }

    private func speak(_ word: SpeechTarget?) -> SpeechTarget? {
        if let word { sink.speak(word) } else { sink.stop() }
        return word
    }
}
