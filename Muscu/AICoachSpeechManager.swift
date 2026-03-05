//
//  AICoachSpeechManager.swift
//  Muscu
//
//  Synthèse vocale (TTS) pour l’AI Coach : AVSpeechSynthesizer, voix qualité Siri/Enhanced,
//  pitch professionnel calme, ducking (mix avec la musique de l’utilisateur).
//

import AVFoundation
import Foundation

/// Clé AppStorage pour le genre de voix (masculin / féminin).
let aiCoachVoiceGenderKey = "aiCoachVoiceGender"

/// Valeurs possibles pour le genre de voix.
enum AICoachVoiceGender: String, CaseIterable {
    case female = "female"
    case male = "male"
}

private final class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var manager: AICoachSpeechManager?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            manager?.deactivateAudioSession()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            manager?.deactivateAudioSession()
        }
    }
}

final class AICoachSpeechManager {

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private let delegate = SpeechSynthesizerDelegate()

    /// Genre de voix choisi (lu depuis UserDefaults / AppStorage).
    var voiceGender: AICoachVoiceGender {
        let raw = UserDefaults.standard.string(forKey: aiCoachVoiceGenderKey) ?? AICoachVoiceGender.female.rawValue
        return AICoachVoiceGender(rawValue: raw) ?? .female
    }

    init() {
        delegate.manager = self
        synthesizer.delegate = delegate
    }

    /// Lit le texte à voix haute. Utilise une voix de haute qualité (type Siri/Enhanced), pitch calme, et ducking.
    @MainActor
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        configureAudioSessionForDucking()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 0.98
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    @MainActor
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    /// Voix française de haute qualité (Enhanced si dispo), selon le genre choisi.
    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let lang = "fr-FR"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("fr") }
        let wantFemale = voiceGender == .female
        if let enhanced = voices.first(where: { voice in
            let id = voice.identifier.lowercased()
            let matchesGender = wantFemale ? (id.contains("female") || id.contains("amelie") || id.contains("marie")) : (id.contains("male") || id.contains("nicolas") || id.contains("thomas"))
            let isEnhanced = id.contains("enhanced") || id.contains("premium") || id.contains("siri")
            return matchesGender && isEnhanced
        }) { return enhanced }
        if let byGender = voices.first(where: { voice in
            let id = voice.identifier.lowercased()
            return wantFemale ? (id.contains("female") || id.contains("amelie")) : (id.contains("male") || id.contains("nicolas"))
        }) { return byGender }
        return AVSpeechSynthesisVoice(language: lang) ?? voices.first
    }

    private func configureAudioSessionForDucking() {
        do {
            if #available(iOS 13.0, *) {
                try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            } else {
                try audioSession.setCategory(.playback, options: [.duckOthers])
            }
            try audioSession.setActive(true, options: [])
        } catch {
            try? audioSession.setCategory(.playback, options: [.duckOthers])
            try? audioSession.setActive(true, options: [])
        }
    }

    fileprivate func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignorer (certains appareils peuvent lever 560030580 tout en unduckant correctement)
        }
    }
}
