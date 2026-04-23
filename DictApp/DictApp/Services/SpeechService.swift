// SpeechService.swift
// System Text-to-Speech using AVFoundation.

import AVFoundation

final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, language: String = "en-US") {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
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
