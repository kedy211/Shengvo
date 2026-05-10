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

// MARK: - CGEvent Tap

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
        DispatchQueue.main.async { manager.reenableEventTap() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    switch type {
    case .flagsChanged:
        manager.handleFlagsChanged(keyCode: UInt32(keyCode), flags: flags, event: event)
    case .keyDown:
        manager.handleKeyDown(keyCode: UInt32(keyCode), flags: flags)
    case .keyUp:
        manager.handleKeyUp(keyCode: UInt32(keyCode), flags: flags)
    default:
        break
    }

    // 单 Option 键模式下吞掉事件，防止触发菜单栏
    if manager.shouldSuppressEvent(keyCode: UInt32(keyCode), flags: flags) {
        return nil
    }

    return Unmanaged.passUnretained(event)
}

class HotKeyManager {
    // Carbon hotkey
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onHotKey: (() -> Void)?

    // CGEvent tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnManagerID: UInt32 = 0
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private let managerID: UInt32
    private var userDataPointer: UnsafeMutableRawPointer?

    // Target combo for CGEvent tap matching
    var targetKeyCode: UInt32 = 0
    var targetModifiers: UInt32 = 0
    var isToggleMode: Bool = true
    var singleKeyType: String? = nil // fn / rightCmd / leftOption / rightOption

    // 单 modifier 键模式下的当前状态追踪
    private var singleModifierActive: Bool = false

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
        if let ptr = userDataPointer { ptr.deallocate() }
    }

    // MARK: - Carbon HotKey (standard modifiers)

    func registerHotKey(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        unregisterHotKey()
        self.onHotKey = onTrigger
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x56494345)
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

    // MARK: - CGEvent Tap (both single-key and modifier-only)

    func startEventTap(
        keyCode: UInt32,
        modifiers: UInt32,
        mode: String,
        singleKey: String?,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) {
        stopFnEventTap()

        fnManagerID = nextFnManagerID
        nextFnManagerID += 1
        fnEventTapManagers[fnManagerID] = self

        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers
        self.isToggleMode = (mode == "toggle")
        self.singleKeyType = singleKey
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.singleModifierActive = false

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<UInt32>.size,
            alignment: MemoryLayout<UInt32>.alignment
        )
        ptr.storeBytes(of: fnManagerID, as: UInt32.self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: fnEventTapCallback,
            userInfo: ptr
        ) else {
            print("Failed to create CGEvent tap. Check accessibility permissions.")
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

    // MARK: - CGEvent Handlers

    func handleKeyDown(keyCode: UInt32, flags: CGEventFlags) {
        // 如果使用单 modifier 键模式，keyDown 不处理（由 flagsChanged 处理）
        guard singleKeyType == nil else { return }

        guard matchesTarget(keyCode: keyCode, flags: flags) else { return }

        if isToggleMode {
            // Toggle: keyDown fires once (keyUp is ignored via shouldSuppressEvent)
            if !singleModifierActive {
                singleModifierActive = true
                DispatchQueue.main.async { self.onKeyDown?() }
            }
        } else {
            // Hold: keyDown starts
            if !singleModifierActive {
                singleModifierActive = true
                DispatchQueue.main.async { self.onKeyDown?() }
            }
        }
    }

    func handleKeyUp(keyCode: UInt32, flags: CGEventFlags) {
        guard singleKeyType == nil else { return }

        if !isToggleMode && singleModifierActive {
            singleModifierActive = false
            DispatchQueue.main.async { self.onKeyUp?() }
        }
    }

    func handleFlagsChanged(keyCode: UInt32, flags: CGEventFlags, event: CGEvent) {
        guard let singleKey = singleKeyType else { return }

        let modifierActive = isSingleModifierActive(singleKey: singleKey, flags: flags, keyCode: keyCode)

        if modifierActive && !singleModifierActive {
            // Modifier pressed
            singleModifierActive = true
            if isToggleMode {
                DispatchQueue.main.async { self.onKeyDown?() }
            } else {
                DispatchQueue.main.async { self.onKeyDown?() }
            }
        } else if !modifierActive && singleModifierActive {
            // Modifier released
            singleModifierActive = false
            if !isToggleMode {
                DispatchQueue.main.async { self.onKeyUp?() }
            }
        }
    }

    func shouldSuppressEvent(keyCode: UInt32, flags: CGEventFlags) -> Bool {
        guard let singleKey = singleKeyType else { return false }

        // 单 Option 键模式下抑制 Option 事件防止菜单栏激活
        if singleKey == "leftOption" || singleKey == "rightOption" {
            if isSingleModifierActive(singleKey: singleKey, flags: flags, keyCode: keyCode) {
                return true
            }
        }

        // Toggle 模式下抑制 keyUp 防止重复触发
        if isToggleMode && singleKeyType == nil && singleModifierActive {
            return true
        }

        return false
    }

    // MARK: - Helpers

    private func matchesTarget(keyCode: UInt32, flags: CGEventFlags) -> Bool {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }

        return keyCode == targetKeyCode && modifiers == targetModifiers
    }

    private func isSingleModifierActive(singleKey: String, flags: CGEventFlags, keyCode: UInt32) -> Bool {
        switch singleKey {
        case "fn":
            return flags.contains(.maskSecondaryFn)
        case "rightCmd":
            return flags.contains(.maskCommand) && keyCode == 0x36 // Right CMD
        case "leftOption":
            return flags.contains(.maskAlternate) && keyCode == 0x3A // Left Option
        case "rightOption":
            return flags.contains(.maskAlternate) && keyCode == 0x3D // Right Option
        default:
            return false
        }
    }

    // MARK: - Event Handler

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<UInt32>.size,
            alignment: MemoryLayout<UInt32>.alignment
        )
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
