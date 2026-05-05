import SwiftUI
import AppKit
import AVFoundation
import UserNotifications

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var hotKeyManager: HotKeyManager!
    private let audioRecorder = AudioRecorder()
    private let asrService = ASRService()
    private let llmService = LLMService()
    private let clipboardManager = ClipboardManager.shared
    private let overlay = RecordingOverlay()

    private var isProcessing = false
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var levelTimer: Timer?
    private var processStartTime: CFAbsoluteTime = 0
    private var recordingStartTime: CFAbsoluteTime = 0
    private var escMonitors: [Any] = []
    private var targetAppName: String?
    private var lastRawText: String = ""

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChange),
            name: .settingsDidChange,
            object: nil
        )

        // Check if setup is needed
        if needsSetup() {
            showSetupWindow()
        }
    }

    // MARK: - Status Bar

    private func statusBarIcon() -> NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if let icon = NSApp.applicationIconImage {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSImage(named: NSImage.applicationIconName)
    }

    private func roundedStatusBarIcon(asTemplate: Bool = false) -> NSImage? {
        guard let source = statusBarIcon() else { return nil }

        let size = NSSize(width: 18, height: 18)
        let radius: CGFloat = 4.0

        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        image.isTemplate = asTemplate
        return image
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = roundedStatusBarIcon()
        }

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "状态: 就绪", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "自定义识别词...", action: #selector(openCustomWords), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "历史记录...", action: #selector(openHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateStatusIcon(state: RecordingState) {
        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            button.image = self.roundedStatusBarIcon()
            button.contentTintColor = nil
        }
    }

    // MARK: - HotKey

    private func setupHotKey() {
        hotKeyManager = HotKeyManager()
        let config = AppConfig.shared

        if config.hotKeyUsesFn {
            // Use CGEvent tap for fn key combinations
            hotKeyManager.startFnEventTap(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                onTrigger: { [weak self] _, _ in
                    self?.toggleRecording()
                }
            )
        } else {
            // Use Carbon for standard modifier combinations
            hotKeyManager.registerHotKey(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                onTrigger: { [weak self] in
                    self?.toggleRecording()
                }
            )
        }
    }

    // MARK: - Recording Flow

    private func toggleRecording() {
        if isProcessing { return }

        if audioRecorder.isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        // Detect frontmost app
        targetAppName = detectFrontmostApp()
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        print("[App] Target app: \(targetAppName ?? "unknown")")

        updateStatusIcon(state: .recording)
        updateMenuStatus("录音中...")
        SoundManager.shared.playStartRecording()
        audioRecorder.startRecording()
        overlay.showRecording()
        startLevelTimer()
        startESC_monitor()
    }

    private func stopRecordingAndProcess() {
        stopESC_monitor()
        updateStatusIcon(state: .processing)
        updateMenuStatus("处理中...")
        SoundManager.shared.playStopRecording()
        isProcessing = true
        stopLevelTimer()
        overlay.showProcessing()
        processStartTime = CFAbsoluteTimeGetCurrent()

        let recordingDuration = processStartTime - recordingStartTime
        let minDuration = AppConfig.shared.minRecordingDuration
        print("[App] Recording duration: \(String(format: "%.2f", recordingDuration))s, min: \(minDuration)s")

        audioRecorder.stopRecording { [weak self] audioData in
            guard let self = self else { return }

            // Skip if recording was too short
            if recordingDuration < minDuration {
                print("[App] Recording too short (\(String(format: "%.2f", recordingDuration))s < \(minDuration)s), skipping")
                self.resetState()
                return
            }

            guard let audioData = audioData else {
                self.resetState()
                self.showError("录音数据为空")
                return
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime
            print("[Timing] 录音停止 → 数据就绪: \(String(format: "%.2f", elapsed))s, 音频大小: \(audioData.count) bytes")

            self.processAudio(audioData)
        }
    }

    // MARK: - Audio Level Monitoring

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let level = self.audioRecorder.getCurrentLevel()
            self.overlay.updateLevel(level)
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - ESC Key Monitor

    private func startESC_monitor() {
        // Use local monitor for events in our app windows
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.cancelRecording()
                return nil
            }
            return event
        }
        // Use global monitor for events in other apps
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                DispatchQueue.main.async {
                    self?.cancelRecording()
                }
            }
        }
        escMonitors = [localMonitor, globalMonitor]
        print("[App] ESC monitor started (local + global)")
    }

    private func stopESC_monitor() {
        for monitor in escMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escMonitors.removeAll()
        print("[App] ESC monitor stopped")
    }

    private func cancelRecording() {
        print("[App] Recording cancelled by ESC")
        stopESC_monitor()
        stopLevelTimer()
        audioRecorder.cancelRecording()
        resetState()
    }

    // MARK: - Frontmost App Detection

    private func detectFrontmostApp() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
            return appName
        }
        return nil
    }

    // MARK: - Processing

    private func processAudio(_ audioData: Data) {
        updateMenuStatus("语音识别中...")
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[Timing] 开始 ASR 识别...")

        asrService.recognize(audioData: audioData) { [weak self] result in
            guard let self = self else { return }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let totalElapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime

            switch result {
            case .success(let text):
                print("[Timing] ASR 完成: \(String(format: "%.2f", elapsed))s, 总耗时: \(String(format: "%.2f", totalElapsed))s")
                print("[Timing] 识别结果: \(text)")
                self.processTextWithLLM(text)
            case .failure(let error):
                print("[Timing] ASR 失败: \(String(format: "%.2f", elapsed))s, 错误: \(error)")
                self.resetState()
                self.showError("识别失败: \(error.localizedDescription)")
            }
        }
    }

    private func processTextWithLLM(_ text: String) {
        lastRawText = text
        let config = AppConfig.shared
        guard config.llmEnabled else {
            print("[Timing] LLM 已禁用，跳过处理")
            pasteText(text, wasProcessedByLLM: false)
            return
        }

        // Skip LLM for short text
        if text.count <= config.llmMinChars {
            print("[Timing] 文本过短(\(text.count)字 ≤ \(config.llmMinChars)字)，跳过 LLM")
            pasteText(text, wasProcessedByLLM: false)
            return
        }

        updateMenuStatus("文本整理中...")
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[Timing] 开始 LLM 处理...")

        llmService.processText(text, targetApp: targetAppName) { [weak self] result in
            guard let self = self else { return }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let totalElapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime

            switch result {
            case .success(let processedText):
                print("[Timing] LLM 完成: \(String(format: "%.2f", elapsed))s, 总耗时: \(String(format: "%.2f", totalElapsed))s")
                print("[Timing] 处理结果: \(processedText)")
                self.pasteText(processedText, wasProcessedByLLM: true)
            case .failure(let error):
                print("[Timing] LLM 失败: \(String(format: "%.2f", elapsed))s, 错误: \(error), 使用原始文本")
                self.pasteText(text, wasProcessedByLLM: false)
            }
        }
    }

    private func pasteText(_ text: String, wasProcessedByLLM: Bool) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let totalElapsed = CFAbsoluteTimeGetCurrent() - processStartTime
        print("[Timing] 总处理耗时: \(String(format: "%.2f", totalElapsed))s")
        print("[App] 准备粘贴: \(text.prefix(50))...")
        print("[App] Accessibility: \(clipboardManager.checkAccessibility() ? "GRANTED" : "NOT GRANTED")")

        // Save to history
        let entry = HistoryEntry(
            text: text,
            rawText: lastRawText,
            timestamp: Date(),
            targetApp: targetAppName,
            wasProcessedByLLM: wasProcessedByLLM
        )
        HistoryManager.shared.addEntry(entry)

        // Copy to clipboard
        clipboardManager.copyToClipboard(text: text)

        // Reset state
        resetState()

        // Paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.clipboardManager.pasteFromClipboard()
            let pasteTime = CFAbsoluteTimeGetCurrent() - startTime
            print("[Timing] 粘贴完成: \(String(format: "%.2f", pasteTime))s")
        }

        if AppConfig.shared.showNotifications {
            showNotification(title: "文本已粘贴", body: String(text.prefix(50)) + (text.count > 50 ? "..." : ""))
        }
    }

    private func resetState() {
        isProcessing = false
        updateStatusIcon(state: .idle)
        updateMenuStatus("就绪")
        overlay.hide()
    }

    // MARK: - UI Helpers

    private func updateMenuStatus(_ status: String) {
        DispatchQueue.main.async {
            self.menu.item(at: 0)?.title = "状态: \(status)"
        }
    }

    private func showError(_ message: String) {
        if AppConfig.shared.showNotifications {
            showNotification(title: "错误", body: message)
        }
    }

    private func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Settings

    @objc private func openCustomWords() {
        SettingsView.pendingTab = .customWords
        NotificationCenter.default.post(name: .switchSettingsTab, object: SettingsTab.customWords)
        openSettings()
    }

    @objc private func openHistory() {
        SettingsView.pendingTab = .history
        NotificationCenter.default.post(name: .switchSettingsTab, object: SettingsTab.history)
        openSettings()
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "晟语 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 620, height: 560))
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Setup Flow

    private func needsSetup() -> Bool {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let accessTrusted = AXIsProcessTrustedWithOptions(options)
        return micStatus != .authorized || !accessTrusted
    }

    private func showSetupWindow() {
        let setupView = SetupView {
            self.setupWindow?.orderOut(nil)
            self.setupWindow = nil
        }
        let hostingController = NSHostingController(rootView: setupView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "晟语 设置向导"
        window.styleMask = [.titled]
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Change Handler

    @objc private func handleSettingsChange() {
        let config = AppConfig.shared

        hotKeyManager.unregisterAll()

        if config.hotKeyUsesFn {
            hotKeyManager.startFnEventTap(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                onTrigger: { [weak self] _, _ in
                    self?.toggleRecording()
                }
            )
        } else {
            hotKeyManager.updateHotKey(keyCode: config.hotKeyKeyCode, modifiers: config.hotKeyModifiers)
        }

        print("[App] Hotkey updated: \(config.hotKeyDescription)")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow { settingsWindow = nil }
        }
    }

    // MARK: - Quit

    @objc private func quitApp() {
        hotKeyManager?.unregisterAll()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Enums

enum RecordingState {
    case idle
    case recording
    case processing
}
