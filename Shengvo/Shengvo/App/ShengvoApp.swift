import SwiftUI
import AppKit
import AVFoundation
import Carbon
import UserNotifications

@main
struct ShengvoApp: App {
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
    private var currentAudioFilename: String?
    private var asrDurationMs: Int = 0
    private var llmDurationMs: Int = 0
    private var asrModeUsed: String = ""

    // Re-paste
    private var repasteHotKeyManager: HotKeyManager?
    private var lastPastedText: String = ""
    private var repasteMenuItem: NSMenuItem?

    // WebSocket streaming ASR
    private var streamingWS: BigModelWS?
    private var streamingTimer: Timer?
    private var streamingActive = false

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChange),
            name: .settingsDidChange,
            object: nil
        )

        // Check permissions first — show setup if needed
        if needsSetup() {
            showSetupWindow()
        }

        // Only register hotkey if accessibility is already granted;
        // otherwise handleSettingsChange will do it after user grants permissions.
        if AXIsProcessTrusted() {
            setupHotKey()
            setupRepasteHotKey()
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
        menu.addItem({ [weak self] in
            let item = NSMenuItem(title: "重新粘贴上一条", action: #selector(repasteLastAction), keyEquivalent: "")
            self?.repasteMenuItem = item
            self?.updateRepasteMenuItem()
            return item
        }())
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
        applyHotKeyConfig()
    }

    private func applyHotKeyConfig() {
        let config = AppConfig.shared

        if config.hotKeySingleKey != nil {
            // Single modifier key: always use CGEvent tap
            hotKeyManager.startEventTap(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                mode: config.hotKeyMode,
                singleKey: config.hotKeySingleKey,
                onKeyDown: { [weak self] in
                    self?.startRecording()
                },
                onKeyUp: { [weak self] in
                    if self?.audioRecorder.isRecording == true {
                        self?.stopRecordingAndProcess()
                    }
                }
            )
        } else if config.hotKeyUsesFn {
            // fn + standard modifiers via CGEvent tap (legacy support)
            hotKeyManager.startEventTap(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                mode: config.hotKeyMode,
                singleKey: "fn",
                onKeyDown: { [weak self] in
                    if config.hotKeyMode == "hold" {
                        self?.startRecording()
                    } else {
                        self?.toggleRecording()
                    }
                },
                onKeyUp: { [weak self] in
                    if config.hotKeyMode == "hold" {
                        if self?.audioRecorder.isRecording == true {
                            self?.stopRecordingAndProcess()
                        }
                    }
                }
            )
        } else {
            // Standard modifier combination via Carbon HotKey
            hotKeyManager.registerHotKey(
                keyCode: config.hotKeyKeyCode,
                modifiers: config.hotKeyModifiers,
                onTrigger: { [weak self] in
                    self?.toggleRecording()
                }
            )
        }
    }

    // MARK: - Re-paste HotKey

    private func setupRepasteHotKey() {
        let config = AppConfig.shared
        repasteHotKeyManager = HotKeyManager()
        repasteHotKeyManager?.registerHotKey(
            keyCode: config.repasteHotKeyKeyCode,
            modifiers: config.repasteHotKeyModifiers,
            onTrigger: { [weak self] in
                self?.repasteLastResult()
            }
        )
        updateRepasteMenuItem()
    }

    private func repasteLastResult() {
        guard !lastPastedText.isEmpty else { return }
        ClipboardManager.shared.pasteText(lastPastedText)
    }

    @objc private func repasteLastAction() {
        repasteLastResult()
    }

    private func updateRepasteMenuItem() {
        let config = AppConfig.shared
        let keyStr = carbonKeyCodeToKeyEquivalent(config.repasteHotKeyKeyCode)
        let mask = carbonModifiersToNSEvent(config.repasteHotKeyModifiers)
        repasteMenuItem?.keyEquivalent = keyStr
        repasteMenuItem?.keyEquivalentModifierMask = mask
    }

    private func carbonKeyCodeToKeyEquivalent(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_Space: return " "
        case kVK_Return: return "↩"
        default: return ""
        }
    }

    private func carbonModifiersToNSEvent(_ modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        return flags
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
        if let app = NSWorkspace.shared.frontmostApplication {
            targetAppName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
        } else {
            targetAppName = nil
        }
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        print("[App] Target app: \(targetAppName ?? "unknown")")

        updateStatusIcon(state: .recording)
        updateMenuStatus("录音中...")
        SoundManager.shared.playStartRecording()
        audioRecorder.startRecording()
        overlay.showRecording()
        startLevelTimer()
        startESC_monitor()

        // 启动流式 ASR（如果启用）
        let config = AppConfig.shared
        if config.asrMode == "cloud" && config.asrStreamingEnabled
            && !config.asrAppID.isEmpty && !config.asrAccessToken.isEmpty {
            startStreaming()
        }
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

            if self.streamingActive {
                self.finishStreaming(audioData: audioData)
            } else {
                self.processAudio(audioData)
            }
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
        escMonitors = [localMonitor, globalMonitor].compactMap { $0 }
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
        stopStreaming()
        audioRecorder.cancelRecording()
        resetState()
    }

    // MARK: - Streaming ASR

    private func startStreaming() {
        let config = AppConfig.shared
        let ws = BigModelWS(resourceID: config.asrStreamingResourceID)

        ws.onPartialResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.overlay.updatePartialText(text)
            }
        }

        ws.connect(appID: config.asrAppID, accessToken: config.asrAccessToken)
        streamingWS = ws
        streamingActive = true

        // 200ms 定时器，非破坏性读取音频分片并发送
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.streamingActive else { return }
            if let chunk = self.audioRecorder.readStreamingChunk(sampleCount: 3200) {
                self.streamingWS?.sendAudioChunk(pcmSamples: chunk, isLast: false)
            }
        }

        print("[App] Streaming ASR started")
    }

    private func finishStreaming(audioData: Data) {
        streamingTimer?.invalidate()
        streamingTimer = nil
        streamingActive = false

        // 发送剩余样本
        let remaining = audioRecorder.readAllRemainingSamples()

        // 保存 WAV 用于历史记录和 REST 回退
        let entryId = UUID()
        currentAudioFilename = HistoryManager.shared.saveAudio(audioData, for: entryId)

        let startTime = CFAbsoluteTimeGetCurrent()
        let ws = streamingWS
        streamingWS = nil

        ws?.finish(remainingSamples: remaining, timeout: 5.0) { [weak self] result in
            guard let self = self else { return }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let totalElapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime

            switch result {
            case .success(let text):
                let elapsedMs = Int(elapsed * 1000)
                self.asrDurationMs = elapsedMs
                self.asrModeUsed = "cloud_streaming"
                print("[Timing] ASR 完成(cloud_streaming): \(String(format: "%.2f", elapsed))s, 总耗时: \(String(format: "%.2f", totalElapsed))s")
                print("[Timing] 识别结果: \(text)")
                AppLogger.shared.logASR(mode: "cloud_streaming", inputSize: audioData.count, output: text, durationMs: elapsedMs)
                self.lastRawText = text
                // ASR 阶段完成 → 进度动画至 40%，然后进入 LLM
                self.overlay.updateProgress(progress: 0.4, phaseLabel: "正在识别...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.processTextWithLLM(text)
                }

            case .failure(let error):
                print("[App] Streaming ASR failed: \(error), falling back to REST")
                // 回退到现有 REST 轮询
                self.asrService.recognize(audioData: audioData, onProgress: { [weak self] asrProgress in
                    self?.overlay.updateProgress(progress: asrProgress * 0.4, phaseLabel: "正在识别...")
                }) { [weak self] result in
                    guard let self = self else { return }

                    let fallbackElapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let fallbackTotal = CFAbsoluteTimeGetCurrent() - self.processStartTime

                    switch result {
                    case .success(let (text, engineUsed)):
                        let elapsedMs = Int(fallbackElapsed * 1000)
                        self.asrDurationMs = elapsedMs
                        self.asrModeUsed = engineUsed
                        print("[Timing] ASR 完成(\(engineUsed), fallback): \(String(format: "%.2f", fallbackElapsed))s, 总耗时: \(String(format: "%.2f", fallbackTotal))s")
                        print("[Timing] 识别结果: \(text)")
                        AppLogger.shared.logASR(mode: engineUsed, inputSize: audioData.count, output: text, durationMs: elapsedMs)
                        self.processTextWithLLM(text)

                    case .failure(let asrError):
                        print("[Timing] ASR fallback 也失败: \(asrError)")
                        if let fn = self.currentAudioFilename {
                            HistoryManager.shared.deleteAudio(named: fn)
                        }
                        self.currentAudioFilename = nil
                        self.resetState()
                        self.showError("识别失败: \(asrError.localizedDescription)")
                    }
                }
            }
        }
    }

    private func stopStreaming() {
        streamingTimer?.invalidate()
        streamingTimer = nil
        streamingWS?.cancel()
        streamingWS = nil
        streamingActive = false
    }

    // MARK: - Processing

    private func processAudio(_ audioData: Data) {
        updateMenuStatus("语音识别中...")
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[Timing] 开始 ASR 识别...")

        // 提前创建 entryId 并保存音频文件
        let entryId = UUID()
        currentAudioFilename = HistoryManager.shared.saveAudio(audioData, for: entryId)

        // 非轮询引擎用 Timer 估算进度
        let engine = AppConfig.shared.asrMode
        var fallbackTimer: Timer?
        if engine != "cloud" {
            let estimatedSec = estimateASRDuration(engine: engine)
            let fallbackStart = CFAbsoluteTimeGetCurrent()
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] t in
                let elapsed = CFAbsoluteTimeGetCurrent() - fallbackStart
                let p = min(0.95, elapsed / estimatedSec) * 0.4
                self?.overlay.updateProgress(progress: p, phaseLabel: "正在识别...")
            }
        }

        asrService.recognize(audioData: audioData, onProgress: { [weak self] asrProgress in
            self?.overlay.updateProgress(progress: asrProgress * 0.4, phaseLabel: "正在识别...")
        }) { [weak self] result in
            fallbackTimer?.invalidate()

            guard let self = self else { return }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let totalElapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime

            switch result {
            case .success(let (text, engineUsed)):
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                self.asrDurationMs = elapsedMs
                self.asrModeUsed = engineUsed
                if engineUsed != AppConfig.shared.asrMode {
                    self.updateMenuStatus("已使用备选引擎")
                }
                print("[Timing] ASR 完成(\(engineUsed)): \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))s, 总耗时: \(String(format: "%.2f", totalElapsed))s")
                print("[Timing] 识别结果: \(text)")
                AppLogger.shared.logASR(mode: engineUsed, inputSize: audioData.count, output: text, durationMs: elapsedMs)
                self.processTextWithLLM(text)
            case .failure(let error):
                print("[Timing] ASR 失败: \(String(format: "%.2f", elapsed))s, 错误: \(error)")
                // ASR 失败，删除已保存的音频文件
                if let fn = self.currentAudioFilename {
                    HistoryManager.shared.deleteAudio(named: fn)
                }
                self.currentAudioFilename = nil
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
            overlay.updateProgress(progress: 1.0, phaseLabel: "完成")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.pasteText(text, wasProcessedByLLM: false)
            }
            return
        }

        // Skip LLM for short text
        if text.count <= config.llmMinChars {
            print("[Timing] 文本过短(\(text.count)字 ≤ \(config.llmMinChars)字)，跳过 LLM")
            overlay.updateProgress(progress: 1.0, phaseLabel: "完成")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.pasteText(text, wasProcessedByLLM: false)
            }
            return
        }

        updateMenuStatus("文本整理中...")
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[Timing] 开始 LLM 处理...")

        // 启动 LLM 阶段进度计时器（基于历史耗时估算）
        let estimatedSec = estimateLLMDuration()
        let llmStart = CFAbsoluteTimeGetCurrent()
        let llmTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            let elapsed = CFAbsoluteTimeGetCurrent() - llmStart
            let llmProgress = min(0.95, elapsed / estimatedSec)
            self?.overlay.updateProgress(progress: 0.4 + llmProgress * 0.6, phaseLabel: "正在整理...")
        }

        // 多轮上下文：如果启用，传入最近 N 轮历史
        let priorTurns: [(raw: String, polished: String)]
        if config.conversationContextEnabled, llmService.conversationContext.count > 0 {
            // 限制轮数不超过配置的最大值
            let allTurns = llmService.conversationContext.orderedTurns
            priorTurns = Array(allTurns.suffix(config.conversationContextMaxTurns))
            print("[LLM] Multi-turn enabled: using \(priorTurns.count) prior turns (max \(config.conversationContextMaxTurns))")
        } else {
            priorTurns = []
        }

        llmService.processText(text, targetApp: targetAppName, priorTurns: priorTurns) { [weak self] result in
            guard let self = self else { return }

            llmTimer.invalidate()

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let totalElapsed = CFAbsoluteTimeGetCurrent() - self.processStartTime

            switch result {
            case .success(let processedText):
                let elapsedMs = Int(elapsed * 1000)
                self.llmDurationMs = elapsedMs
                print("[Timing] LLM 完成: \(String(format: "%.2f", elapsed))s, 总耗时: \(String(format: "%.2f", totalElapsed))s")
                print("[Timing] 处理结果: \(processedText)")

                // 多轮上下文：记录本轮对话
                if config.conversationContextEnabled {
                    self.llmService.conversationContext.addTurn(raw: text, polished: processedText)
                }

                // 进度条跳至 100%，延迟让 spring 动画播放
                self.overlay.updateProgress(progress: 1.0, phaseLabel: "完成")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.pasteText(processedText, wasProcessedByLLM: true)
                }
            case .failure(let error):
                print("[Timing] LLM 失败: \(String(format: "%.2f", elapsed))s, 错误: \(error), 使用原始文本")
                self.llmDurationMs = 0
                self.overlay.updateProgress(progress: 1.0, phaseLabel: "完成")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.pasteText(text, wasProcessedByLLM: false)
                }
            }
        }
    }

    private func pasteText(_ text: String, wasProcessedByLLM: Bool) {
        lastPastedText = text
        let startTime = CFAbsoluteTimeGetCurrent()
        let totalElapsed = CFAbsoluteTimeGetCurrent() - processStartTime
        print("[Timing] 总处理耗时: \(String(format: "%.2f", totalElapsed))s")
        print("[App] 准备粘贴: \(text.prefix(50))...")
        print("[App] Accessibility: \(clipboardManager.checkAccessibility() ? "GRANTED" : "NOT GRANTED")")

        // Save to history
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - processStartTime) * 1000)
        let entry = HistoryEntry(
            text: text,
            rawText: lastRawText,
            timestamp: Date(),
            targetApp: targetAppName,
            wasProcessedByLLM: wasProcessedByLLM,
            audioFilename: currentAudioFilename,
            asrMode: asrModeUsed,
            asrDurationMs: asrDurationMs,
            llmDurationMs: llmDurationMs,
            totalDurationMs: totalMs
        )
        currentAudioFilename = nil
        HistoryManager.shared.addEntry(entry)

        // Reset state before paste (so recording can start again)
        resetState()

        // Inject text via Accessibility API; fallback to clipboard Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardManager.shared.pasteText(text)
            let pasteTime = CFAbsoluteTimeGetCurrent() - startTime
            print("[Timing] 粘贴完成: \(String(format: "%.2f", pasteTime))s")
        }

        if AppConfig.shared.showNotifications {
            showNotification(title: "文本已粘贴", body: String(text.prefix(50)) + (text.count > 50 ? "..." : ""))
        }
    }

    private func resetState() {
        isProcessing = false
        asrDurationMs = 0
        llmDurationMs = 0
        asrModeUsed = ""
        streamingActive = false
        updateStatusIcon(state: .idle)
        updateMenuStatus("就绪")
        overlay.updatePartialText("")
        overlay.hide()
    }

    private func logFrontmost(_ tag: String) {
        // Keep for future debugging
    }

    /// 非轮询引擎的 ASR 估算耗时（秒）
    private func estimateASRDuration(engine: String) -> TimeInterval {
        switch engine {
        case "local": return 8.0
        case "qwen_cloud": return 3.0
        case "apple": return 2.0
        default: return 5.0
        }
    }

    /// 基于历史数据的 LLM 估算耗时（秒），无历史时默认 4s
    private func estimateLLMDuration() -> TimeInterval {
        let avg = HistoryManager.shared.averageLLMDuration(limit: 20)
        return avg > 0 ? avg : 4.0
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
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "晟语 设置"
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
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

        if hotKeyManager == nil {
            hotKeyManager = HotKeyManager()
        } else {
            hotKeyManager.unregisterAll()
        }

        applyHotKeyConfig()

        // Re-register re-paste hotkey
        repasteHotKeyManager?.unregisterAll()
        setupRepasteHotKey()

        print("[App] Hotkey updated: \(config.hotKeyDescription), Re-paste: \(config.repasteHotKeyDescription)")
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
        repasteHotKeyManager?.unregisterAll()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Enums

enum RecordingState {
    case idle
    case recording
    case processing
}
