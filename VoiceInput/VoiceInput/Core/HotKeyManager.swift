import Carbon
import Cocoa

private var hotKeyManagers: [UInt32: HotKeyManager] = [:]
private var nextManagerID: UInt32 = 1

private func hotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let managerID = userData.load(as: UInt32.self)
    guard let manager = hotKeyManagers[managerID] else { return OSStatus(eventNotHandledErr) }

    DispatchQueue.main.async {
        manager.onHotKey?()
    }
    return noErr
}

class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onHotKey: (() -> Void)?

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private let managerID: UInt32
    private var userDataPointer: UnsafeMutableRawPointer?

    init() {
        managerID = nextManagerID
        nextManagerID += 1
        hotKeyManagers[managerID] = self
        installEventHandler()
    }

    deinit {
        unregisterHotKey()
        removeEventHandler()
        hotKeyManagers.removeValue(forKey: managerID)
        if let ptr = userDataPointer {
            ptr.deallocate()
        }
    }

    func registerHotKey(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        unregisterHotKey()
        self.onHotKey = onTrigger
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x56494345) // "VICE"
        hotKeyID.id = managerID

        let status = RegisterEventHotKey(
            currentKeyCode,
            currentModifiers,
            hotKeyID,
            GetEventMonitorTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }

    func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        registerHotKey(keyCode: keyCode, modifiers: modifiers, onTrigger: onHotKey ?? {})
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        // Allocate persistent memory for the manager ID
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt32>.size, alignment: MemoryLayout<UInt32>.alignment)
        ptr.storeBytes(of: managerID, as: UInt32.self)
        userDataPointer = ptr

        let status = InstallEventHandler(
            GetEventMonitorTarget(),
            hotKeyCallback,
            1,
            &eventTypes,
            ptr,
            &eventHandlerRef
        )

        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }

    private func removeEventHandler() {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}
