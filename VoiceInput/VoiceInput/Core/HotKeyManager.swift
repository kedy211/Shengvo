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

// MARK: - CGEvent Tap for fn key support

private var fnEventTapManagers: [UInt32: HotKeyManager] = [:]
private var nextFnManagerID: UInt32 = 1

private func fnEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let managerID = userInfo.load(as: UInt32.self)
    guard let manager = fnEventTapManagers[managerID] else { return Unmanaged.passUnretained(event) }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async {
            manager.reenableEventTap()
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged {
        let flags = event.flags

        // For modifier-only combos (keyCode==0): check if fn + target modifiers are held
        if manager.targetKeyCode == 0 && flags.contains(.maskSecondaryFn) {
            let hasCtrl = flags.contains(.maskControl)
            let hasShift = flags.contains(.maskShift)
            let hasCmd = flags.contains(.maskCommand)
            let hasOption = flags.contains(.maskAlternate)

            var currentModifiers: UInt32 = 0
            if hasCmd { currentModifiers |= UInt32(cmdKey) }
            if hasShift { currentModifiers |= UInt32(shiftKey) }
            if hasCtrl { currentModifiers |= UInt32(controlKey) }
            if hasOption { currentModifiers |= UInt32(optionKey) }

            if currentModifiers == manager.targetModifiers {
                DispatchQueue.main.async {
                    manager.onFnHotKey?(0, manager.targetModifiers)
                }
            }
        }
    } else if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }

        if flags.contains(.maskSecondaryFn) && UInt32(keyCode) == manager.targetKeyCode && modifiers == manager.targetModifiers {
            DispatchQueue.main.async {
                manager.onFnHotKey?(UInt32(keyCode), modifiers)
            }
        }
    }

    return Unmanaged.passUnretained(event)
}

class HotKeyManager {
    // Carbon hotkey
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onHotKey: (() -> Void)?

    // fn key CGEvent tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnManagerID: UInt32 = 0
    var onFnHotKey: ((UInt32, UInt32) -> Void)?

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private let managerID: UInt32
    private var userDataPointer: UnsafeMutableRawPointer?

    // Target combo for CGEvent tap matching
    var targetKeyCode: UInt32 = 0
    var targetModifiers: UInt32 = 0

    init() {
        managerID = nextManagerID
        nextManagerID += 1
        hotKeyManagers[managerID] = self
        installEventHandler()
    }

    deinit {
        unregisterHotKey()
        removeEventHandler()
        stopFnEventTap()
        hotKeyManagers.removeValue(forKey: managerID)
        fnEventTapManagers.removeValue(forKey: fnManagerID)
        if let ptr = userDataPointer {
            ptr.deallocate()
        }
    }

    // MARK: - Carbon HotKey (standard modifiers)

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
            UInt32(kEventHotKeyExclusive),
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

    // MARK: - CGEvent Tap (fn key)

    func startFnEventTap(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping (UInt32, UInt32) -> Void) {
        stopFnEventTap()

        fnManagerID = nextFnManagerID
        nextFnManagerID += 1
        fnEventTapManagers[fnManagerID] = self
        self.onFnHotKey = onTrigger
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let ptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt32>.size, alignment: MemoryLayout<UInt32>.alignment)
        ptr.storeBytes(of: fnManagerID, as: UInt32.self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: fnEventTapCallback,
            userInfo: ptr
        ) else {
            print("Failed to create CGEvent tap for fn key. Check accessibility permissions.")
            ptr.deallocate()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stopFnEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }

    func unregisterAll() {
        unregisterHotKey()
        stopFnEventTap()
    }

    func reenableEventTap() {
        if let tap = eventTap {
            print("[HotKey] Event tap disabled, re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - Event Handler

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

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
