import AppKit
import Vision

enum OCRManager {
    enum OCRError: LocalizedError {
        case cancelled
        case imageLoadFailed
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil
            case .imageLoadFailed:
                return "Could not read screenshot. Please allow Screen Recording permission in System Settings."
            case .noTextFound:
                return "No readable text found in the selected area."
            }
        }
    }

    /// Launches macOS's native interactive screenshot selection (crosshair),
    /// runs offline Apple Vision OCR on the captured region, and deletes the temporary file.
    static func captureAndRecognizeText() async throws -> (text: String, anchorPoint: NSPoint) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicktranslate-ocr-\(UUID().uuidString).png")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let captured = try await runInteractiveScreenCapture(to: tempURL)
        guard captured else {
            throw OCRError.cancelled
        }

        let mousePoint = await MainActor.run { NSEvent.mouseLocation }

        guard FileManager.default.fileExists(atPath: tempURL.path),
              let image = NSImage(contentsOf: tempURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageLoadFailed
        }

        let recognized = try await recognizeText(in: cgImage)
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OCRError.noTextFound
        }

        return (trimmed, mousePoint)
    }

    private static func runInteractiveScreenCapture(to url: URL) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: interactive region selection, -x: silent (no camera shutter sound)
            process.arguments = ["-i", "-x", url.path]
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path) {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return mergeOCRLines(lines)
        }.value
    }

    /// Joins OCR lines smoothly so wrapped English sentences translate naturally instead of line-by-line.
    private static func mergeOCRLines(_ lines: [String]) -> String {
        var result = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if result.isEmpty {
                result = line
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += line
            } else if result.hasSuffix(".") || result.hasSuffix("?") || result.hasSuffix("!") || result.hasSuffix(":") {
                result += "\n" + line
            } else {
                result += " " + line
            }
        }
        return result
    }
}
