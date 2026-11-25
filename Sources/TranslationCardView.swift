import AppKit
import SwiftUI
import Translation

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var errorMessage: String? = nil
    @Published var isTranslating: Bool = false
    @Published var isPinned: Bool = false
    @Published var isEnglishToChinese: Bool = true
    @Published var dictionaryEntry: DictionaryEntry? = nil
    @Published var showDictionary: Bool = true
    @Published var fromOCR: Bool = false
    @Published var isEditingInput: Bool = false
    @Published var copiedFeedback: Bool = false
    @Published var translationConfig: TranslationSession.Configuration? = nil

    private var requestID = UUID()

    var englishTextForSpeech: String {
        isEnglishToChinese ? sourceText : translatedText
    }

    var directionLabel: String {
        isEnglishToChinese ? "EN → 简体中文" : "简体中文 → EN"
    }

    func startManualInput() {
        SpeechService.shared.stop()
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        isTranslating = false
        dictionaryEntry = nil
        fromOCR = false
        isEditingInput = true
    }

    func requestTranslation(text: String, fromOCR: Bool = false) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        SpeechService.shared.stop()
        self.sourceText = cleaned
        self.fromOCR = fromOCR
        self.isEditingInput = false
        self.errorMessage = nil
        self.translatedText = ""
        self.isTranslating = true
        self.copiedFeedback = false
        self.requestID = UUID()

        let isChinese = TextCaptureService.isPredominantlyChinese(cleaned)
        self.isEnglishToChinese = !isChinese
        self.dictionaryEntry = isChinese ? nil : NativeDictionaryService.lookup(cleaned)

        triggerSession()
    }

    func swapDirectionAndRetranslate() {
        isEnglishToChinese.toggle()
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        translatedText = ""
        isTranslating = true
        requestID = UUID()
        triggerSession()
    }

    func retryTranslation() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        translatedText = ""
        isTranslating = true
        requestID = UUID()
        triggerSession()
    }

    func copyTranslation() {
        let toCopy = translatedText.isEmpty ? sourceText : translatedText
        guard !toCopy.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(toCopy, forType: .string)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.copiedFeedback = false
        }
    }

    private func triggerSession() {
        let src = Locale.Language(identifier: isEnglishToChinese ? "en" : "zh-Hans")
        let dst = Locale.Language(identifier: isEnglishToChinese ? "zh-Hans" : "en")

        if translationConfig == nil
            || translationConfig?.source != src
            || translationConfig?.target != dst {
            translationConfig = TranslationSession.Configuration(source: src, target: dst)
        } else {
            translationConfig?.invalidate()
        }
    }

    func performTranslation(using session: TranslationSession) async {
        let activeID = self.requestID
        let text = self.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self.isTranslating = false
            return
        }

        do {
            let response = try await session.translate(text)
            guard self.requestID == activeID else { return }
            self.translatedText = response.targetText
            self.errorMessage = nil
            self.isTranslating = false
        } catch {
            guard self.requestID == activeID else { return }
            self.isTranslating = false
            self.errorMessage = error.localizedDescription
        }
    }
}

struct TranslationCardView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @ObservedObject private var speech = SpeechService.shared
    let onClose: () -> Void
    let onStartOCR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar
            Divider().opacity(0.35)
            sourceSection
            Divider().opacity(0.35)
            translationSection

            if let entry = viewModel.dictionaryEntry {
                Divider().opacity(0.35)
                dictionarySection(entry)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
        .padding(12)
        .translationTask(viewModel.translationConfig) { session in
            await viewModel.performTranslation(using: session)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.swapDirectionAndRetranslate() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(viewModel.directionLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Swap translation direction")

            if viewModel.fromOCR {
                Text("OCR")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(action: {
                speech.toggleSpeak(viewModel.englishTextForSpeech, languageCode: "en-US")
            }) {
                Image(systemName: speech.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(speech.isSpeaking ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.englishTextForSpeech.isEmpty)
            .help(speech.isSpeaking ? "Stop pronunciation" : "Read English aloud")

            Button(action: onStartOCR) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Screenshot OCR translate (⌥S)")

            Button(action: { viewModel.copyTranslation() }) {
                Image(systemName: viewModel.copiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.copiedFeedback ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.translatedText.isEmpty)
            .help("Copy translation")

            Button(action: { viewModel.isPinned.toggle() }) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12.5))
                    .foregroundStyle(viewModel.isPinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "Unpin popup" : "Pin popup on screen")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isEditingInput {
                TextField("Type or paste text to translate…", text: $viewModel.sourceText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .onSubmit {
                        viewModel.requestTranslation(text: viewModel.sourceText)
                    }

                HStack {
                    Spacer()
                    Button("Translate") {
                        viewModel.requestTranslation(text: viewModel.sourceText)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                ScrollView {
                    HStack(alignment: .top) {
                        Text(viewModel.sourceText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: { viewModel.isEditingInput = true }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit text")
                    }
                }
                .frame(maxHeight: 84)
            }
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating offline with Apple Translation…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if let err = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    HStack(spacing: 8) {
                        Button("Retry") {
                            viewModel.retryTranslation()
                        }
                        .controlSize(.small)
                        Text("First-time offline pack downloads automatically via macOS.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !viewModel.translatedText.isEmpty {
                ScrollView {
                    Text(viewModel.translatedText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 190)
            } else {
                Text("Select any text or type above to translate.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
    }

    private func dictionarySection(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { viewModel.showDictionary.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 11))
                    Text("macOS Dictionary · \(entry.headword)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                    Image(systemName: viewModel.showDictionary ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if viewModel.showDictionary {
                ScrollView {
                    Text(entry.definition)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
        }
    }
}
