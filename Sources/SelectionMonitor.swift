import AppKit
import Foundation

@MainActor
final class SelectionMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseDownPoint: NSPoint?
    private var mouseDownTime: TimeInterval = 0
    private var captureTask: Task<Void, Never>?

    var isPointInsideOwnWindows: ((NSPoint) -> Bool)?
    var onDismissTransientUI: (() -> Void)?
    var onSelectionDetected: ((String, NSPoint) -> Void)?

    func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .scrollWheel,
            .keyDown
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Escape closes open translation UI
            if event.keyCode == 53 {
                self?.onDismissTransientUI?()
            }
            return event
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            if isPointInsideOwnWindows?(mouseLocation) == true {
                mouseDownPoint = nil
                return
            }
            captureTask?.cancel()
            onDismissTransientUI?()
            mouseDownPoint = mouseLocation
            mouseDownTime = event.timestamp

        case .rightMouseDown, .scrollWheel, .keyDown:
            captureTask?.cancel()
            if isPointInsideOwnWindows?(mouseLocation) != true {
                onDismissTransientUI?()
            }

        case .leftMouseUp:
            guard !SettingsStore.shared.isPaused,
                  SettingsStore.shared.floatingIconEnabled else {
                mouseDownPoint = nil
                return
            }
            if isPointInsideOwnWindows?(mouseLocation) == true {
                mouseDownPoint = nil
                return
            }

            let isMultiClick = event.clickCount >= 2
            var isDrag = false
            if let down = mouseDownPoint {
                let distance = hypot(mouseLocation.x - down.x, mouseLocation.y - down.y)
                let duration = event.timestamp - mouseDownTime
                // Ignore ultra-long drags (e.g., moving windows or drawing) and tiny accidental clicks
                isDrag = distance >= 6.0 && duration < 8.0
            }
            mouseDownPoint = nil

            guard isDrag || isMultiClick else { return }

            // Ignore if modifier keys like Command/Control are held (e.g., Cmd+Click link)
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return }

            scheduleSelectionCapture(at: mouseLocation)

        default:
            break
        }
    }

    private func scheduleSelectionCapture(at anchorPoint: NSPoint) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            // Let the active app finish committing the mouse selection
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }

            let allowFallback = SettingsStore.shared.smartWebCapture
                && TextCaptureService.isFrontmostAppWebOrElectron()

            guard let rawText = await TextCaptureService.captureSelectedText(allowClipboardFallback: allowFallback),
                  !Task.isCancelled else {
                return
            }

            guard TextCaptureService.hasTranslatableContent(rawText) else { return }

            if SettingsStore.shared.autoSkipChinese && TextCaptureService.isPredominantlyChinese(rawText) {
                return
            }

            await MainActor.run {
                self?.onSelectionDetected?(rawText, anchorPoint)
            }
        }
    }
}
