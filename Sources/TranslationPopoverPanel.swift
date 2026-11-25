import AppKit
import SwiftUI

@MainActor
final class TranslationPopoverPanel: NSPanel {
    let viewModel = TranslationViewModel()
    private var hostingView: NSHostingView<TranslationCardView>!
    var onStartOCR: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 404, height: 240),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let rootView = TranslationCardView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.hidePopover(force: true)
            },
            onStartOCR: { [weak self] in
                self?.onStartOCR?()
            }
        )
        hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showTranslation(for text: String, near anchor: NSPoint, fromOCR: Bool = false) {
        position(near: anchor)
        orderFrontRegardless()
        // Trigger translation after the panel is in the window hierarchy so Apple's .translationTask runs cleanly
        viewModel.requestTranslation(text: text, fromOCR: fromOCR)
    }

    func showManualInput(near anchor: NSPoint) {
        viewModel.startManualInput()
        position(near: anchor)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showErrorMessage(_ message: String, near anchor: NSPoint) {
        viewModel.sourceText = ""
        viewModel.translatedText = ""
        viewModel.dictionaryEntry = nil
        viewModel.isTranslating = false
        viewModel.errorMessage = message
        position(near: anchor)
        orderFrontRegardless()
    }

    func hidePopover(force: Bool = false) {
        if !force && viewModel.isPinned {
            return
        }
        SpeechService.shared.stop()
        if isVisible {
            orderOut(nil)
        }
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        guard isVisible else { return false }
        return frame.contains(point)
    }

    private func position(near anchor: NSPoint) {
        let fitSize = hostingView.fittingSize
        let width = max(404, fitSize.width)
        let height = max(190, min(fitSize.height, 520))

        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: anchor.x - width * 0.25, y: anchor.y - height - 16)
        if origin.y < visibleFrame.minY + 12 {
            // Place above the cursor if there isn't enough space below
            origin.y = anchor.y + 18
        }
        origin.x = max(visibleFrame.minX + 12, min(origin.x, visibleFrame.maxX - width - 12))
        origin.y = max(visibleFrame.minY + 12, min(origin.y, visibleFrame.maxY - height - 12))

        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}
