import AppKit
import ApplicationServices
import Carbon
import NaturalLanguage

enum TextCaptureService {
    /// Checks whether the app has macOS Accessibility permission.
    static func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// Captures currently selected text from the frontmost application.
    /// First tries macOS Accessibility API (zero clipboard side-effects).
    /// Falls back to save -> Cmd+C -> read -> restore clipboard when requested.
    static func captureSelectedText(allowClipboardFallback: Bool) async -> String? {
        if let axText = readSelectedTextViaAccessibility(), !axText.isEmpty {
            return axText
        }

        guard allowClipboardFallback else { return nil }
        return await readSelectedTextViaClipboardFallback()
    }

    /// Returns true if the text is predominantly Simplified/Traditional Chinese.
    static func isPredominantlyChinese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var cjkCount = 0
        var latinCount = 0
        for scalar in trimmed.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                cjkCount += 1
            } else if (0x0041...0x005A).contains(v) || (0x0061...0x007A).contains(v) {
                latinCount += 1
            }
        }

        if cjkCount > 0 && cjkCount >= latinCount {
            return true
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let lang = recognizer.dominantLanguage {
            return lang == .simplifiedChinese || lang == .traditionalChinese
        }
        return false
    }

    /// Filters out pure whitespace, numbers, or punctuation with no translatable letters.
    static func hasTranslatableContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 5000 else { return false }
        return trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Detects whether the frontmost app is a browser or Electron-based app where
    /// AXSelectedText sometimes needs clipboard fallback.
    static func isFrontmostAppWebOrElectron() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        let knownTokens = [
            "chrome", "chromium", "safari", "firefox", "arc", "brave", "edge", "opera", "vivaldi",
            "electron", "vscode", "code", "cursor", "antigravity", "slack", "discord",
            "notion", "obsidian", "figma", "linear", "wechat", "lark", "feishu", "preview", "acrobat"
        ]
        return knownTokens.contains { bundleID.contains($0) || name.contains($0) }
    }

    // MARK: - Accessibility Capture

    private static func readSelectedTextViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        // Enable enhanced AX tree on Chromium/Electron apps so selected text is exposed directly.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focused = focusedRef else { return nil }
        let focusedElement = focused as! AXUIElement

        // Method 1: Direct kAXSelectedTextAttribute
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let text = selectedRef as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        // Method 2: kAXSelectedTextRangeAttribute + kAXStringForRangeParameterizedAttribute
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                focusedElement,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeVal,
                &stringRef
            ) == .success, let text = stringRef as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    // MARK: - Smart Clipboard Fallback (Save -> Cmd+C -> Read -> Restore)

    private struct SavedPasteboardItem {
        let dataByType: [NSPasteboard.PasteboardType: Data]
    }

    @MainActor
    private static func snapshotPasteboard(_ pb: NSPasteboard) -> [SavedPasteboardItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return SavedPasteboardItem(dataByType: dict)
        }
    }

    @MainActor
    private static func restorePasteboard(_ pb: NSPasteboard, snapshot: [SavedPasteboardItem]) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved.dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(items)
    }

    private static func readSelectedTextViaClipboardFallback() async -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let (snapshot, initialChangeCount) = await MainActor.run { () -> ([SavedPasteboardItem], Int) in
            let pb = NSPasteboard.general
            return (snapshotPasteboard(pb), pb.changeCount)
        }

        // Send synthetic Cmd+C
        sendCommandC()

        // Poll briefly for clipboard change (up to ~180ms)
        var captured: String? = nil
        for _ in 0..<9 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            let result = await MainActor.run { () -> (Bool, String?) in
                let pb = NSPasteboard.general
                if pb.changeCount != initialChangeCount {
                    return (true, pb.string(forType: .string))
                }
                return (false, nil)
            }
            if result.0 {
                captured = result.1?.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Restore original clipboard cleanly
        await MainActor.run {
            let pb = NSPasteboard.general
            if pb.changeCount != initialChangeCount {
                restorePasteboard(pb, snapshot: snapshot)
            }
        }

        if let text = captured, !text.isEmpty {
            return text
        }
        return nil
    }

    private static func sendCommandC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_C)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
