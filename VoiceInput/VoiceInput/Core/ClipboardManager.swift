import AppKit
import Foundation

class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Direct text injection (preferred)

    /// Attempt to inject text directly into the focused element via Accessibility API.
    /// Returns true on success, false if clipboard fallback is needed.
    func injectTextDirectly(_ text: String) -> Bool {
        guard checkAccessibility() else {
            print("[Input] Accessibility NOT granted, fallback to clipboard")
            return false
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("[Input] No frontmost application")
            return false
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            print("[Input] Cannot get focused element (error: \(result.rawValue)), fallback to clipboard")
            return false
        }

        let axElement = element as! AXUIElement

        // Try kAXValueAttribute first (works for standard NSTextField, NSTextView, most native apps)
        var setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        if setResult == .success {
            print("[Input] Direct text injection succeeded via kAXValueAttribute")
            return true
        }

        // Try kAXSelectedTextAttribute (works for some editors when text is selected)
        setResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if setResult == .success {
            print("[Input] Direct text injection succeeded via kAXSelectedTextAttribute")
            return true
        }

        print("[Input] Direct injection failed (value: \(setResult.rawValue)), fallback to clipboard")
        return false
    }

    // MARK: - Clipboard-based fallback

    func pasteViaClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard checkAccessibility() else {
            print("[Input] Accessibility NOT granted - cannot paste")
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

        // Try osascript first, fallback to CGEvent
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
                print("[Input] Clipboard paste succeeded via osascript")
            } else {
                print("[Input] osascript failed: \(errorStr)")
                pasteViaCGEvent()
            }
        } catch {
            print("[Input] osascript error: \(error)")
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
        print("[Input] CGEvent paste sent")
    }

    // MARK: - Convenience

    /// Paste text: try direct AX injection first, fall back to clipboard Cmd+V.
    func pasteText(_ text: String) {
        if injectTextDirectly(text) {
            return
        }
        pasteViaClipboard(text: text)
    }

    /// Just copy to clipboard (for manual user paste).
    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[Input] Copied \(text.count) chars to clipboard")
    }

    /// Copy to clipboard then paste (for history panel paste).
    func copyAndPaste(text: String) {
        copyToClipboard(text: text)
        pasteText(text)
    }
}
