import SwiftUI
import Carbon

struct HotKeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var displayText: String = ""

    var body: some View {
        HStack {
            Text("快捷键:")
                .frame(width: 80, alignment: .leading)

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
            HotKeyCaptureView(isRecording: $isRecording, keyCode: $keyCode, modifiers: $modifiers)
                .frame(width: 0, height: 0)
        )
    }

    private func formatHotKey() -> String {
        var desc = ""
        if modifiers & UInt32(cmdKey) != 0 { desc += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { desc += "⇧" }
        if modifiers & UInt32(controlKey) != 0 { desc += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { desc += "⌥" }
        desc += keyCodeToString(keyCode)
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
        default: return "?"
        }
    }
}

struct HotKeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> HotKeyCaptureNSView {
        let view = HotKeyCaptureNSView()
        view.onKeyCapture = { capturedKeyCode, capturedModifiers in
            DispatchQueue.main.async {
                self.keyCode = capturedKeyCode
                self.modifiers = capturedModifiers
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
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    var isRecording = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }

        // Must have at least one modifier
        guard modifiers != 0 else { return }

        let keyCode = UInt32(event.keyCode)
        onKeyCapture?(keyCode, modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        // Track modifier key changes for display
    }
}
