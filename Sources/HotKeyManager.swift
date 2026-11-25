import Carbon
import Foundation

final class HotKeyManager {
    static let translateHotKeyID: UInt32 = 1
    static let ocrHotKeyID: UInt32 = 2

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []

    var onTranslateSelection: (() -> Void)?
    var onOCRTranslate: (() -> Void)?

    func registerDefaultHotKeys() {
        installHandlerIfNeeded()

        // Option + D -> Translate selected text
        register(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey), id: Self.translateHotKeyID)

        // Option + S -> Screenshot OCR translate
        register(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey), id: Self.ocrHotKeyID)
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregisterAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            DispatchQueue.main.async {
                switch hotKeyID.id {
                case HotKeyManager.translateHotKeyID:
                    manager.onTranslateSelection?()
                case HotKeyManager.ocrHotKeyID:
                    manager.onOCRTranslate?()
                default:
                    break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        let signature: OSType = 0x5154524E // 'QTRN'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref = ref {
            hotKeyRefs.append(ref)
        }
    }
}
