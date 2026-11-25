import AppKit
import SwiftUI

@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

private struct FloatingTriggerButtonView: View {
    let onTap: () -> Void
    @ObservedObject var hoverState: HoverState

    private var symbolName: String {
        if NSImage(systemSymbolName: "translate", accessibilityDescription: nil) != nil {
            return "translate"
        }
        return "character.book.closed.fill"
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                hoverState.isHovering ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.18),
                                lineWidth: hoverState.isHovering ? 1.5 : 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 2)

                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hoverState.isHovering ? Color.accentColor : Color.primary)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(hoverState.isHovering ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hoverState.isHovering)
        }
        .buttonStyle(.plain)
        .padding(4)
        .onHover { hovering in
            hoverState.isHovering = hovering
        }
        .help("Translate selection (简体中文)")
    }
}

@MainActor
final class FloatingTriggerPanel: NSPanel {
    private var autoHideWorkItem: DispatchWorkItem?
    private var pendingText: String = ""
    private var pendingAnchor: NSPoint = .zero
    var onTriggerClicked: ((String, NSPoint) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
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
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hoverState = HoverState()
        let hosting = NSHostingView(rootView: FloatingTriggerButtonView(onTap: { [weak self] in
            guard let self else { return }
            let text = self.pendingText
            let anchor = self.pendingAnchor
            self.hideTrigger()
            self.onTriggerClicked?(text, anchor)
        }, hoverState: hoverState))
        hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(near point: NSPoint, for text: String) {
        pendingText = text
        pendingAnchor = point

        let panelSize = NSSize(width: 40, height: 40)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: point.x + 10, y: point.y + 12)
        if origin.x + panelSize.width > visibleFrame.maxX - 8 {
            origin.x = point.x - panelSize.width - 10
        }
        if origin.y + panelSize.height > visibleFrame.maxY - 8 {
            origin.y = point.y - panelSize.height - 14
        }
        origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - panelSize.width - 8))
        origin.y = max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - panelSize.height - 8))

        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        alphaValue = 0.0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 1.0
        }

        autoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideTrigger()
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: workItem)
    }

    func hideTrigger() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        if isVisible {
            orderOut(nil)
        }
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        guard isVisible else { return false }
        return frame.insetBy(dx: -4, dy: -4).contains(point)
    }
}
