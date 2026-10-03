import Carbon
import AppKit

class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    var onHotKeyPressed: (() -> Void)?

    func registerDefaultHotKey() {
        // Option (⌥) + Space (키코드 49)
        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354), id: 1) // "PAST"
        let modifierFlags: UInt32 = UInt32(optionKey)
        let spaceKeyCode: UInt32 = 49 // kVK_Space

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (handler, event, userData) -> OSStatus in
                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                if status == noErr && receivedID.id == 1 {
                    DispatchQueue.main.async {
                        HotKeyManager.shared.onHotKeyPressed?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        let status = RegisterEventHotKey(
            spaceKeyCode,
            modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            print("[+] 전역 단축키 등록 완료: Option + Space")
        } else {
            print("[!] 전역 단축키 등록 실패: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
