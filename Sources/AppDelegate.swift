import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let settings = SettingsStore.shared
    private let hotKeyManager = HotKeyManager()
    private let selectionMonitor = SelectionMonitor()
    private lazy var triggerPanel = FloatingTriggerPanel()
    private lazy var popoverPanel = TranslationPopoverPanel()
    private var isCapturingOCR = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupPanels()
        setupHotKeys()
        setupSelectionMonitor()

        // Prompt for Accessibility permission on first launch if not granted yet
        if !TextCaptureService.isAccessibilityTrusted(promptIfNeeded: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.promptAccessibilityPermission()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionMonitor.stop()
        hotKeyManager.unregisterAll()
        SpeechService.shared.stop()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let symbolName = NSImage(systemSymbolName: "translate", accessibilityDescription: nil) != nil
                ? "translate"
                : "character.book.closed.fill"
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "QuickTranslate")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "QuickTranslate (⌥D Translate · ⌥S OCR)"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hasAX = TextCaptureService.isAccessibilityTrusted(promptIfNeeded: false)
        if !hasAX {
            let warnItem = NSMenuItem(
                title: "⚠️ Grant Accessibility Permission…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warnItem.target = self
            menu.addItem(warnItem)
            menu.addItem(.separator())
        }

        let translateItem = NSMenuItem(
            title: "Translate Selected Text (⌥D)",
            action: #selector(menuTranslateSelection),
            keyEquivalent: ""
        )
        translateItem.target = self
        menu.addItem(translateItem)

        let ocrItem = NSMenuItem(
            title: "Screenshot OCR Translate (⌥S)",
            action: #selector(menuStartOCR),
            keyEquivalent: ""
        )
        ocrItem.target = self
        menu.addItem(ocrItem)

        let inputItem = NSMenuItem(
            title: "Quick Type / Paste Translate…",
            action: #selector(menuManualInput),
            keyEquivalent: ""
        )
        inputItem.target = self
        menu.addItem(inputItem)

        menu.addItem(.separator())

        let floatingItem = NSMenuItem(
            title: "Floating Icon on Mouse Selection",
            action: #selector(toggleFloatingIcon),
            keyEquivalent: ""
        )
        floatingItem.target = self
        floatingItem.state = settings.floatingIconEnabled ? .on : .off
        menu.addItem(floatingItem)

        let skipCNItem = NSMenuItem(
            title: "Auto-Skip Chinese Text on Mouse Select",
            action: #selector(toggleAutoSkipChinese),
            keyEquivalent: ""
        )
        skipCNItem.target = self
        skipCNItem.state = settings.autoSkipChinese ? .on : .off
        menu.addItem(skipCNItem)

        let webCaptureItem = NSMenuItem(
            title: "Smart Browser / Electron Capture",
            action: #selector(toggleSmartWebCapture),
            keyEquivalent: ""
        )
        webCaptureItem.target = self
        webCaptureItem.state = settings.smartWebCapture ? .on : .off
        menu.addItem(webCaptureItem)

        let pauseItem = NSMenuItem(
            title: settings.isPaused ? "Resume Selection Detection" : "Pause Selection Detection",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit QuickTranslate",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Wiring

    private func setupPanels() {
        triggerPanel.onTriggerClicked = { [weak self] text, anchor in
            self?.popoverPanel.showTranslation(for: text, near: anchor)
        }

        popoverPanel.onStartOCR = { [weak self] in
            self?.startOCRTranslate()
        }
    }

    private func setupHotKeys() {
        hotKeyManager.onTranslateSelection = { [weak self] in
            self?.translateCurrentSelectionViaHotKey()
        }
        hotKeyManager.onOCRTranslate = { [weak self] in
            self?.startOCRTranslate()
        }
        hotKeyManager.registerDefaultHotKeys()
    }

    private func setupSelectionMonitor() {
        selectionMonitor.isPointInsideOwnWindows = { [weak self] point in
            guard let self else { return false }
            return self.triggerPanel.containsScreenPoint(point)
                || self.popoverPanel.containsScreenPoint(point)
        }

        selectionMonitor.onDismissTransientUI = { [weak self] in
            self?.triggerPanel.hideTrigger()
            self?.popoverPanel.hidePopover(force: false)
        }

        selectionMonitor.onSelectionDetected = { [weak self] text, anchor in
            guard let self else { return }
            self.triggerPanel.show(near: anchor, for: text)
        }

        selectionMonitor.start()
    }

    // MARK: - Actions

    private func translateCurrentSelectionViaHotKey() {
        triggerPanel.hideTrigger()
        let anchor = NSEvent.mouseLocation

        if !TextCaptureService.isAccessibilityTrusted(promptIfNeeded: true) {
            popoverPanel.showErrorMessage(
                "Please enable QuickTranslate in System Settings → Privacy & Security → Accessibility, then try ⌥D again.",
                near: anchor
            )
            return
        }

        Task {
            // Explicit hotkey always allows smart clipboard fallback so it works in 100% of apps
            if let text = await TextCaptureService.captureSelectedText(allowClipboardFallback: true),
               TextCaptureService.hasTranslatableContent(text) {
                popoverPanel.showTranslation(for: text, near: anchor)
            } else {
                popoverPanel.showManualInput(near: anchor)
            }
        }
    }

    private func startOCRTranslate() {
        guard !isCapturingOCR else { return }
        isCapturingOCR = true
        triggerPanel.hideTrigger()
        popoverPanel.hidePopover(force: true)

        Task {
            defer { self.isCapturingOCR = false }
            do {
                let result = try await OCRManager.captureAndRecognizeText()
                self.popoverPanel.showTranslation(
                    for: result.text,
                    near: result.anchorPoint,
                    fromOCR: true
                )
            } catch let error as OCRManager.OCRError {
                if case .cancelled = error { return }
                let anchor = NSEvent.mouseLocation
                self.popoverPanel.showErrorMessage(error.localizedDescription, near: anchor)
            } catch {
                let anchor = NSEvent.mouseLocation
                self.popoverPanel.showErrorMessage(error.localizedDescription, near: anchor)
            }
        }
    }

    private func promptAccessibilityPermission() {
        _ = TextCaptureService.isAccessibilityTrusted(promptIfNeeded: true)
    }

    @objc private func openAccessibilitySettings() {
        _ = TextCaptureService.isAccessibilityTrusted(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func menuTranslateSelection() {
        translateCurrentSelectionViaHotKey()
    }

    @objc private func menuStartOCR() {
        startOCRTranslate()
    }

    @objc private func menuManualInput() {
        triggerPanel.hideTrigger()
        let screenCenter: NSPoint
        if let screen = NSScreen.main {
            screenCenter = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY + 120)
        } else {
            screenCenter = NSEvent.mouseLocation
        }
        popoverPanel.showManualInput(near: screenCenter)
    }

    @objc private func toggleFloatingIcon() {
        settings.floatingIconEnabled.toggle()
    }

    @objc private func toggleAutoSkipChinese() {
        settings.autoSkipChinese.toggle()
    }

    @objc private func toggleSmartWebCapture() {
        settings.smartWebCapture.toggle()
    }

    @objc private func togglePause() {
        settings.isPaused.toggle()
        if settings.isPaused {
            triggerPanel.hideTrigger()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
