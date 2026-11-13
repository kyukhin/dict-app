// SpeechService.swift
// System Text-to-Speech using AVFoundation.

import AVFoundation

final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()

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

    private init() {}

    /// Speaks nothing when the device has no voice for `language`: the default
    /// voice would read the word in another language (#202).
    func speak(_ text: String, language: String) {
        guard let voice = AVSpeechSynthesisVoice(language: language) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
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
