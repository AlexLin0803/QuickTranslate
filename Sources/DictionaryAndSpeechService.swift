import Foundation
import AVFoundation
import CoreServices

struct DictionaryEntry {
    let headword: String
    let definition: String
}

enum NativeDictionaryService {
    /// Looks up a single word or short phrase (up to 3 words) in macOS's built-in offline Dictionary.
    static func lookup(_ rawText: String) -> DictionaryEntry? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty, trimmed.count <= 45 else { return nil }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count <= 3 else { return nil }

        let cfString = trimmed as CFString
        let range = CFRangeMake(0, trimmed.utf16.count)
        guard let rawDef = DCSCopyTextDefinition(nil, cfString, range)?.takeRetainedValue() as String? else {
            return nil
        }

        let cleaned = formatDefinition(rawDef)
        guard !cleaned.isEmpty else { return nil }
        return DictionaryEntry(headword: trimmed, definition: cleaned)
    }

    private static func formatDefinition(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Truncate overly long dictionary articles cleanly for the compact popup
        if trimmed.count > 480 {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: 480)
            return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return trimmed
    }
}

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    @Published private(set) var isSpeaking: Bool = false
    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggleSpeak(_ text: String, languageCode: String = "en-US") {
        if synthesizer.isSpeaking {
            stop()
            return
        }
        speak(text, languageCode: languageCode)
    }

    func speak(_ text: String, languageCode: String = "en-US") {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = bestVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.0
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(languageCode.prefix(2).lowercased())
        }
        // Prefer enhanced / premium macOS voices if installed, otherwise default en-US
        if let premium = voices.first(where: { $0.quality == .premium && $0.language == languageCode }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced && $0.language == languageCode }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: languageCode) ?? voices.first
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
