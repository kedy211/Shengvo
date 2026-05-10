import SwiftUI
import Carbon

struct HotKeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var usesFn: Bool
    @Binding var hotKeyMode: String
    @Binding var hotKeySingleKey: String?

    @State private var isRecording = false
    @State private var displayText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode selector
            HStack(spacing: 8) {
                Text("触发方式:")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                Spacer()
                Picker("", selection: $hotKeyMode) {
                    Text("切换模式 (按一下开始，再按一下结束)").tag("toggle")
                    Text("按住模式 (按住录音，松开结束)").tag("hold")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Single key selector
            HStack(spacing: 8) {
                Text("热键类型:")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                Spacer()
                Picker("", selection: Binding<String?>(
                    get: { hotKeySingleKey },
                    set: { hotKeySingleKey = $0 }
                )) {
                    Text("组合键").tag(nil as String?)
                    Text("Fn").tag("fn" as String?)
                    Text("Right ⌘").tag("rightCmd" as String?)
                    Text("Left ⌥").tag("leftOption" as String?)
                    Text("Right ⌥").tag("rightOption" as String?)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
            }

            // No compatibility notice needed — Right CMD is available on all modern Mac keyboards

            // Combination key recorder (only when single key is NOT selected)
            if hotKeySingleKey == nil {
                HStack {
                    Text("快捷键:")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)

                    Button(action: {
                        isRecording.toggle()
                        if isRecording {
                            displayText = "请按下快捷键..."
                        }
                    }) {
                        Text(isRecording ? "按下快捷键..." : formatHotKey())
                            .frame(minWidth: 120)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecording ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    if isRecording {
                        Button("取消") {
                            isRecording = false
                            displayText = ""
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .background(
                    HotKeyCaptureView(isRecording: $isRecording, keyCode: $keyCode, modifiers: $modifiers, usesFn: $usesFn)
                        .frame(width: 0, height: 0)
                )
            }

            // Visual hint for current mode
            if hotKeySingleKey != nil {
                HStack(spacing: 6) {
                    Image(systemName: hotKeyMode == "hold" ? "hand.draw" : "hand.point.up")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(hotKeyMode == "hold"
                         ? "按住 \(singleKeyLabel(hotKeySingleKey)) 开始录音，松开停止"
                         : "按下 \(singleKeyLabel(hotKeySingleKey)) 开始/停止录音")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func singleKeyLabel(_ key: String?) -> String {
        switch key {
        case "fn": return "Fn"
        case "rightCmd": return "Right ⌘"
        case "leftOption": return "Left ⌥"
        case "rightOption": return "Right ⌥"
        default: return ""
        }
    }

    private func formatHotKey() -> String {
        var desc = ""
        if usesFn { desc += "fn " }
        if modifiers & UInt32(cmdKey) != 0 { desc += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { desc += "⇧" }
        if modifiers & UInt32(controlKey) != 0 { desc += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { desc += "⌥" }
        if keyCode != 0 {
            desc += keyCodeToString(keyCode)
        }
        return desc
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return "?"
        }
    }
}

struct HotKeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var usesFn: Bool

    func makeNSView(context: Context) -> HotKeyCaptureNSView {
        let view = HotKeyCaptureNSView()
        view.onKeyCapture = { capturedKeyCode, capturedModifiers, capturedUsesFn in
            DispatchQueue.main.async {
                self.keyCode = capturedKeyCode
                self.modifiers = capturedModifiers
                self.usesFn = capturedUsesFn
                self.isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureNSView, context: Context) {
        nsView.isRecording = isRecording
    }
}

class HotKeyCaptureNSView: NSView {
    var onKeyCapture: ((UInt32, UInt32, Bool) -> Void)?
    var isRecording = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
                startFnMonitor()
            } else {
                stopFnMonitor()
                modifierOnlyWorkItem?.cancel()
            }
        }
    }

    private var fnMonitor: Any?
    private var fnPressed = false
    private let fnKeyCode: Int = 0x3F

    private var modifierOnlyWorkItem: DispatchWorkItem?
    private var hasKeyDown = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        hasKeyDown = true
        modifierOnlyWorkItem?.cancel()

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }

        let usesFn = fnPressed

        guard modifiers != 0 || usesFn else { return }

        let keyCode = UInt32(event.keyCode)
        onKeyCapture?(keyCode, modifiers, usesFn)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }

        hasKeyDown = false

        if event.keyCode == fnKeyCode {
            fnPressed = event.modifierFlags.contains(.function)
        }
        if event.modifierFlags.contains(.function) {
            fnPressed = true
        }

        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCtrl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)
        let hasAnyStandardModifier = hasCmd || hasShift || hasCtrl || hasOption

        let currentFn = fnPressed || event.modifierFlags.contains(.function)

        modifierOnlyWorkItem?.cancel()

        if currentFn && hasAnyStandardModifier && !hasKeyDown {
            let capturedCmd = hasCmd
            let capturedShift = hasShift
            let capturedCtrl = hasCtrl
            let capturedOption = hasOption
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                var modifiers: UInt32 = 0
                if capturedCmd { modifiers |= UInt32(cmdKey) }
                if capturedShift { modifiers |= UInt32(shiftKey) }
                if capturedCtrl { modifiers |= UInt32(controlKey) }
                if capturedOption { modifiers |= UInt32(optionKey) }
                self.fnPressed = true
                self.onKeyCapture?(0, modifiers, true)
            }
            modifierOnlyWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        if event.keyCode == fnKeyCode && !event.modifierFlags.contains(.function) {
            fnPressed = false
        }
    }

    private func startFnMonitor() {
        fnMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            if event.keyCode == self.fnKeyCode {
                self.fnPressed = event.modifierFlags.contains(.function)
            }
            if event.modifierFlags.contains(.function) {
                self.fnPressed = true
            }
            return event
        }
    }

    private func stopFnMonitor() {
        if let monitor = fnMonitor {
            NSEvent.removeMonitor(monitor)
            fnMonitor = nil
        }
    }

    deinit {
        stopFnMonitor()
    }
}
