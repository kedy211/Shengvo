import AppKit
import Foundation

class ClipboardManager {
    static let shared = ClipboardManager()

    private init() {}

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Strategy A: Unicode CGEvent (no clipboard)

    func injectViaUnicodeEvent(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .privateState)
        let utf16 = Array(text.utf16)
        let chunkSize = 20

        for offset in stride(from: 0, to: utf16.count, by: chunkSize) {
            let chunk = Array(utf16[offset..<min(offset + chunkSize, utf16.count)])
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) else {
                return false
            }

            chunk.withUnsafeBufferPointer { ptr in
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
            }

            keyDown.post(tap: .cghidEventTap)
            usleep(5000)
            keyUp.post(tap: .cghidEventTap)
            usleep(5000)
        }

        print("[Input] Unicode events sent (\(text.count) chars)")
        return true
    }

    // MARK: - Strategy B: Clipboard paste with restore

    func pasteViaClipboardWithRestore(text: String) {
        guard checkAccessibility() else {
            showAccessibilityAlert()
            return
        }

        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        var savedItems: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                let saved = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        saved.setData(data, forType: type)
                    }
                }
                savedItems.append(saved)
            }
        }
        let savedChangeCount = pasteboard.changeCount

        // Set our text
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSString])

        // Send Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)

            guard let cmdDn = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
                  let vDn   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let vUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
                  let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
                return
            }

            cmdDn.post(tap: .cghidEventTap)
            usleep(15000)

            vDn.flags = .maskCommand
            vDn.post(tap: .cghidEventTap)
            usleep(30000)

            vUp.flags = .maskCommand
            vUp.post(tap: .cghidEventTap)
            usleep(15000)

            cmdUp.post(tap: .cghidEventTap)

            print("[Input] Cmd+V sequence sent")

            // Restore original clipboard after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if pasteboard.changeCount != savedChangeCount || !savedItems.isEmpty {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(savedItems)
                    print("[Input] Clipboard restored")
                }
            }
        }
    }

    // MARK: - Alert

    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "无法粘贴"
            alert.informativeText = "需要辅助功能权限才能自动粘贴。\n\n请在 系统偏好设置 → 隐私与安全性 → 辅助功能 中添加 晟语，然后重启应用。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统偏好设置")
            alert.addButton(withTitle: "好的")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    // MARK: - Convenience

    /// Paste text:
    /// 1. Unicode CGEvent — no clipboard, no pasteboard (preferred)
    /// 2. Clipboard paste + restore original content (fallback)
    func pasteText(_ text: String) {
        if injectViaUnicodeEvent(text) {
            return
        }
        pasteViaClipboardWithRestore(text: text)
    }

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSString])
        print("[Input] Copied to clipboard")
    }

    func copyAndPaste(text: String) {
        copyToClipboard(text: text)
        pasteText(text)
    }
}
