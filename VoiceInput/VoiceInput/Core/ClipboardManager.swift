import AppKit
import Foundation

class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[Clipboard] Copied \(text.count) chars to clipboard")
    }

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func pasteFromClipboard() {
        guard checkAccessibility() else {
            print("[Clipboard] Accessibility NOT granted - cannot paste")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "无法粘贴"
                alert.informativeText = "需要辅助功能权限才能自动粘贴。\n\n请在 系统偏好设置 → 隐私与安全性 → 辅助功能 中添加 晟语，然后重启应用。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统偏好设置")
                alert.addButton(withTitle: "好的")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            return
        }

        // Use osascript to paste
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to keystroke \"v\" using command down"]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                print("[Clipboard] Paste succeeded via osascript")
            } else {
                print("[Clipboard] osascript failed: \(errorStr)")
                // Fallback to CGEvent
                pasteViaCGEvent()
            }
        } catch {
            print("[Clipboard] osascript error: \(error)")
            pasteViaCGEvent()
        }
    }

    private func pasteViaCGEvent() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        print("[Clipboard] CGEvent paste sent")
    }

    func copyAndPaste(text: String) {
        copyToClipboard(text: text)
        pasteFromClipboard()
    }
}
