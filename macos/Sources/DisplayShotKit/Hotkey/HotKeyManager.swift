import Carbon.HIToolbox
import Foundation

/// Registers one system-wide hot key via Carbon. Works without Accessibility permission.
final class HotKeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x4453_4854 // "DSHT"

    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        unregister()
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let callback: EventHandlerUPP = { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onTrigger?() }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
