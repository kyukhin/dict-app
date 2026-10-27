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
