import Foundation
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var onWorkspaceHotkey: ((Int) -> Void)?
    private var onRealignHotkey: (() -> Void)?

    // Key codes for 1...9 on ANSI/macOS keyboard
    private let numberKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
    ]

    private init() {}

    func register(onWorkspaceIndex: @escaping (Int) -> Void, onRealign: @escaping () -> Void) {
        unregisterAll()
        self.onWorkspaceHotkey = onWorkspaceIndex
        self.onRealignHotkey = onRealign

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
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
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = Int(hotKeyID.id)
                Task { @MainActor in
                    if id >= 1 && id <= 9 {
                        manager.onWorkspaceHotkey?(id - 1)
                    } else if id == 100 {
                        manager.onRealignHotkey?()
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )

        let signature = OSType(0x44574B53) // 'DWKS'
        let modifiers = UInt32(cmdKey | optionKey)

        for (idx, keyCode) in numberKeyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: UInt32(idx + 1))
            if RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                registeredHotKeys.append(ref)
            }
        }

        var realignRef: EventHotKeyRef?
        let realignID = EventHotKeyID(signature: signature, id: 100)
        if RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, realignID, GetApplicationEventTarget(), 0, &realignRef) == noErr, let realignRef {
            registeredHotKeys.append(realignRef)
        }
    }

    func unregisterAll() {
        for ref in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
