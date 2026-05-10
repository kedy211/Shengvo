import SwiftUI
import AVFoundation

// MARK: - Sidebar Item

enum SettingsTab: String, CaseIterable {
    case general = "通用"
    case asr = "语音识别"
    case llm = "LLM 处理"
    case prompt = "系统提示词"
    case customWords = "自定义识别词"
    case history = "历史记录"
    case about = "关于"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .asr: return "mic.fill"
        case .llm: return "brain"
        case .prompt: return "text.quote"
        case .customWords: return "text.word.spacing"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    static var pendingTab: SettingsTab?

    @State private var config = AppConfig.shared
    @State private var selectedTab: SettingsTab
    @State private var micGranted = false
    @State private var accessGranted = false
    @State private var customWords: [String] = AppConfig.shared.customWords
    @State private var historyEntries: [HistoryEntry] = []
    @State private var audioPlayer: AVAudioPlayer?

    init() {
        let initial = Self.pendingTab ?? .general
        Self.pendingTab = nil
        _selectedTab = State(initialValue: initial)
    }

    private let tabSwitchPublisher = NotificationCenter.default.publisher(for: .switchSettingsTab)

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(180)
                .background(.ultraThinMaterial)
        } detail: {
            detailContent
        }
        .onAppear {
            refreshPermissions()
            refreshHistory()
        }
        .onReceive(tabSwitchPublisher) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button("保存") {
                        saveAll()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            generalSettings
        case .asr:
            asrSettings
        case .llm:
            llmSettings
        case .prompt:
            promptSettings
        case .customWords:
            customWordsSettings
        case .history:
            historySettings
        case .about:
            aboutSettings
        }
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hotkey
                SectionHeader(title: "快捷键")
                HotKeyRecorderView(
                    keyCode: $config.hotKeyKeyCode,
                    modifiers: $config.hotKeyModifiers,
                    usesFn: $config.hotKeyUsesFn,
                    hotKeyMode: Binding<String>(
                        get: { config.hotKeyMode },
                        set: { config.hotKeyMode = $0 }
                    ),
                    hotKeySingleKey: Binding<String?>(
                        get: { config.hotKeySingleKey },
                        set: { config.hotKeySingleKey = $0 }
                    )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 16)

                // Options
                SectionHeader(title: "选项")
                SettingToggleRow(title: "开机自启动", isOn: $config.launchAtLogin)
                SettingToggleRow(title: "显示通知", isOn: $config.showNotifications)
                SettingToggleRow(title: "启用日志", subtitle: "记录识别和处理的完整过程到 ~/Library/Logs/Shengvo/", isOn: $config.logEnabled)
                SettingDoubleField(
                    title: "最短录音时长",
                    unit: "秒",
                    value: $config.minRecordingDuration,
                    range: 0.1...10.0,
                    step: 0.1,
                    format: "%.1f"
                )

                Divider().padding(.horizontal, 16)

                // Permissions
                SectionHeader(title: "权限状态")

                permissionRow(
                    icon: "mic.fill",
                    title: "麦克风权限",
                    granted: micGranted,
                    action: {
                        if micGranted {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        } else {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in
                                DispatchQueue.main.async { refreshPermissions() }
                            }
                        }
                    }
                )

                permissionRow(
                    icon: "keyboard.fill",
                    title: "辅助功能权限",
                    granted: accessGranted,
                    action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                )
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private func permissionRow(icon: String, title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(granted ? .green : .red)
                .font(.system(size: 14))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            Spacer()

            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text(granted ? "已授权" : "未授权")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            Button("管理") { action() }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - ASR Settings

    private var asrSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "语音识别引擎")

                HStack(spacing: 12) {
                    Text("识别引擎")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                    Spacer()
                    Picker("", selection: $config.asrMode) {
                        Text("本地 (Whisper)").tag("local")
                        Text("火山引擎").tag("cloud")
                        Text("阿里云 Qwen").tag("qwen_cloud")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if config.asrMode == "local" {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Whisper base (q8_0 量化, 首次自动下载 ~78MB)")
                            .font(.system(size: 13, weight: .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                if config.asrMode == "cloud" {
                    SettingTextField(title: "App ID", placeholder: "火山引擎 App ID", text: $config.asrAppID)
                    SettingTextField(title: "Access Token", placeholder: "Access Token", text: $config.asrAccessToken, isSecure: true)
                    SettingTextField(title: "Secret Key", placeholder: "Secret Key", text: $config.asrSecretKey, isSecure: true)
                }

                if config.asrMode == "qwen_cloud" {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Qwen3-ASR-Flash，28 语种+16 方言，标点+噪声过滤，≈0.013 元/分钟")
                            .font(.system(size: 13, weight: .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    SettingTextField(title: "API Key", placeholder: "sk-xxx", text: $config.asrQwenAPIKey, isSecure: true)
                }

                Divider().padding(.horizontal, 16)

                // Fallback Chain
                SectionHeader(title: "故障转移")

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("主引擎失败时，按顺序尝试以下备选引擎")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Fallback chain list
                VStack(spacing: 4) {
                    // Primary engine (always shown, non-removable)
                    fallbackChainRow(label: "主引擎", engine: config.asrModeLabel, isPrimary: true, onMoveUp: nil, onMoveDown: nil, onRemove: nil)

                    ForEach(Array(config.asrFallbackChain.enumerated()), id: \.offset) { index, engine in
                        fallbackChainRow(
                            label: "备选 \(index + 1)",
                            engine: engineLabel(engine),
                            isPrimary: false,
                            onMoveUp: index > 0 ? { moveFallback(from: index, to: index - 1) } : nil,
                            onMoveDown: index < config.asrFallbackChain.count - 1 ? { moveFallback(from: index, to: index + 1) } : nil,
                            onRemove: { config.asrFallbackChain.remove(at: index) }
                        )
                    }

                    // Add button
                    if config.asrFallbackChain.count < 3 {
                        Menu {
                            if !config.asrFallbackChain.contains("local") && config.asrMode != "local" {
                                Button("本地 Whisper") { config.asrFallbackChain.append("local") }
                            }
                            if !config.asrFallbackChain.contains("cloud") && config.asrMode != "cloud" {
                                Button("火山引擎") { config.asrFallbackChain.append("cloud") }
                            }
                            if !config.asrFallbackChain.contains("qwen_cloud") && config.asrMode != "qwen_cloud" {
                                Button("阿里云 Qwen") { config.asrFallbackChain.append("qwen_cloud") }
                            }
                            if !config.asrFallbackChain.contains("apple") && config.asrAllowAppleFallback {
                                Button("Apple Speech") { config.asrFallbackChain.append("apple") }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 12))
                                Text("添加备选引擎")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 16)

                // Apple Speech toggle
                SettingToggleRow(
                    title: "允许 Apple Speech 作为最终兜底",
                    subtitle: "所有备选引擎失败后，使用系统内置语音识别。注意：音频会发送至 Apple 服务器。",
                    isOn: $config.asrAllowAppleFallback
                )
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private func fallbackChainRow(label: String, engine: String, isPrimary: Bool, onMoveUp: (() -> Void)?, onMoveDown: (() -> Void)?, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(engine)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPrimary ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.06))
                )

            Spacer()

            if !isPrimary {
                HStack(spacing: 4) {
                    if let onMoveUp = onMoveUp {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    if let onMoveDown = onMoveDown {
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    if let onRemove = onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func moveFallback(from: Int, to: Int) {
        guard to >= 0, to < config.asrFallbackChain.count else { return }
        config.asrFallbackChain.swapAt(from, to)
    }

    private func engineLabel(_ engine: String) -> String {
        switch engine {
        case "local": return "Whisper 本地"
        case "cloud": return "火山引擎"
        case "qwen_cloud": return "阿里云 Qwen"
        case "apple": return "Apple Speech"
        default: return engine
        }
    }

    // MARK: - LLM Settings

    private var llmSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "大语言模型 (LLM)")

                SettingToggleRow(title: "启用文本整理", subtitle: "语音识别后自动调用 LLM 优化文本", isOn: $config.llmEnabled)

                if config.llmEnabled {
                    SettingTextField(title: "Base URL", placeholder: "https://ark.cn-beijing.volces.com/api/v3", text: $config.llmBaseURL)
                    SettingTextField(title: "API Key", placeholder: "API Key", text: $config.llmAPIKey, isSecure: true)
                    SettingTextField(title: "模型名称", placeholder: "doubao-pro-32k", text: $config.llmModel)

                    SettingNumberField(
                        title: "跳过 LLM 的字数阈值",
                        unit: "字",
                        value: $config.llmMinChars,
                        range: 0...1000
                    )

                    reasoningEffortRow

                    Divider().padding(.horizontal, 16)

                    // System prompt preview (read-only, short)
                    SectionHeader(title: "当前系统提示词")
                    let promptText = config.effectiveSystemPrompt
                    let preview = String(promptText.prefix(100))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview + (promptText.count > 100 ? "..." : ""))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Spacer()
                            Text("共 \(promptText.count) 字 · 完整内容见「系统提示词」标签页")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)

                    Divider().padding(.horizontal, 16)

                    // Multi-turn Context
                    SectionHeader(title: "多轮上下文")

                    SettingToggleRow(
                        title: "启用多轮上下文",
                        subtitle: "连续口述时，将前几次的内容作为上下文传给 LLM，提升连贯性",
                        isOn: $config.conversationContextEnabled
                    )

                    if config.conversationContextEnabled {
                        HStack(spacing: 12) {
                            Text("最大上下文轮数")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.primary)

                            Spacer()

                            HStack(spacing: 4) {
                                ForEach(1...5, id: \.self) { n in
                                    Button {
                                        config.conversationContextMaxTurns = n
                                    } label: {
                                        Text("\(n)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(config.conversationContextMaxTurns == n ? .white : .primary)
                                            .frame(width: 28, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(config.conversationContextMaxTurns == n
                                                          ? Color.accentColor
                                                          : Color.primary.opacity(0.08))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("保留最近 \(config.conversationContextMaxTurns) 轮口述上下文。每轮会额外消耗 tokens，建议 2-3 轮即可。")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Prompt Settings

    private var promptSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "系统提示词")

                Text("系统提示词决定 LLM 如何润色你的语音文本。可编辑全部内容，或恢复默认。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                SettingToggleRow(
                    title: "启用自定义系统提示词",
                    subtitle: "开启后可编辑完整的系统提示词，覆盖默认的模块化提示词",
                    isOn: Binding<Bool>(
                        get: { config.customSystemPromptOverride != nil },
                        set: { enabled in
                            if enabled {
                                config.customSystemPromptOverride = config.effectiveSystemPrompt
                            } else {
                                config.customSystemPromptOverride = nil
                            }
                        }
                    )
                )

                if config.customSystemPromptOverride != nil {
                    SettingTextEditor(
                        title: "自定义提示词",
                        subtitle: "直接编辑系统提示词。清空内容并关闭上方开关可恢复默认。热词会自动追加到提示词末尾。",
                        placeholder: "输入系统提示词...",
                        text: Binding<String>(
                            get: { config.customSystemPromptOverride ?? "" },
                            set: { config.customSystemPromptOverride = $0 }
                        )
                    )

                    HStack {
                        Spacer()
                        Button("重置为默认提示词") {
                            config.customSystemPromptOverride = nil
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // Default prompt preview
                if config.customSystemPromptOverride == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("当前默认提示词（只读预览）")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(PromptManager.systemPrompt(mode: .polish).count) 字")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.secondary)
                        }

                        ScrollView {
                            Text(PromptManager.systemPrompt(mode: .polish))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private var reasoningEffortRow: some View {
        HStack(spacing: 12) {
            Text("推理强度")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            Spacer()

            Picker("", selection: $config.llmReasoningEffort) {
                Text("minimal").tag("minimal")
                Text("low").tag("low")
                Text("medium").tag("medium")
                Text("high").tag("high")
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 40)
    }

    // MARK: - Custom Words Settings

    private var customWordsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "自定义识别词")

                Text("添加专业术语和专有名词，LLM 会据此纠正识别错误")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                // Input area
                CustomWordInputView(customWords: $customWords)

                // Word list
                if customWords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("暂无自定义词汇")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        Text("添加专有名词、术语等，提升识别准确率")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(customWords.enumerated()), id: \.offset) { index, word in
                            wordRow(word: word, index: index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    HStack {
                        Spacer()
                        Button("清空全部") {
                            customWords.removeAll()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private func wordRow(word: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(word)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.08))
                )

            Spacer()

            Button {
                customWords.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - History Settings

    private var historySettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "历史记录")

                if historyEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        Text("语音输入的文字会自动保存到这里")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    HStack {
                        Text("共 \(historyEntries.count) 条记录，双击可粘贴")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)

                        Spacer()

                        Button("导出全部") {
                            stopAudio()
                            let exportEntries = HistoryManager.shared.getEntriesForExport()
                            ExportService.shared.exportEntries(exportEntries) { success, path in
                                if success, let path = path {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.borderless)

                        Button("清空全部") {
                            stopAudio()
                            HistoryManager.shared.clearAll()
                            historyEntries = []
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)

                    LazyVStack(spacing: 6) {
                        ForEach(historyEntries) { entry in
                            historyRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private func historyRow(entry: HistoryEntry) -> some View {
        let hasAudio = entry.audioFilename != nil
        let isThisPlaying = audioPlayer?.isPlaying == true && audioPlayer?.url?.lastPathComponent == entry.audioFilename

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.relativeTime)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)

                if let app = entry.targetApp {
                    Text(app)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                        )
                }

                HStack(spacing: 4) {
                    // ASR engine tag
                    if !entry.asrMode.isEmpty {
                        Text(entry.asrModeLabel)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                    if entry.wasProcessedByLLM {
                        Text("LLM")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                }

                // Timing info
                if entry.totalDurationMs > 0 {
                    Text("\(entry.totalDurationMs)ms")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(width: 90, alignment: .leading)

            Text(entry.truncatedText)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                if hasAudio {
                    Button {
                        if isThisPlaying {
                            stopAudio()
                        } else {
                            playAudio(entry: entry)
                        }
                    } label: {
                        Image(systemName: isThisPlaying ? "stop.fill" : "play.circle")
                            .font(.system(size: 12))
                            .foregroundColor(isThisPlaying ? .orange : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(isThisPlaying ? "停止播放" : "播放录音")
                }

                Button {
                    ClipboardManager.shared.copyToClipboard(text: entry.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制")

                Button {
                    if isThisPlaying { stopAudio() }
                    HistoryManager.shared.deleteEntry(id: entry.id)
                    historyEntries.removeAll { $0.id == entry.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .onTapGesture(count: 2) {
            ClipboardManager.shared.copyAndPaste(text: entry.text)
        }
    }

    // MARK: - About Settings

    private let githubURL = "https://github.com/kedy211/Shengvo"

    /// 从 Info.plist 读取应用版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var aboutSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // App icon and name
                VStack(spacing: 12) {
                    AboutAppIcon()
                        .frame(width: 64, height: 64)

                    Text("晟语 Shengvo")
                        .font(.system(size: 18, weight: .semibold))

                    Text("macOS 语音输入法")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)

                    Text("语音识别 + 大模型文本整理，一键将语音转化为精准文字")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)

                Divider().padding(.horizontal, 16)

                // Features
                SectionHeader(title: "功能特性")
                VStack(alignment: .leading, spacing: 4) {
                    aboutFeature("语音识别", "支持本地 Whisper / 云端火山引擎 ASR 双引擎")
                    aboutFeature("LLM 文本整理", "自动修正同音错字、补充标点、去除口语冗余")
                    aboutFeature("应用感知", "根据当前目标应用自动调整输出风格")
                    aboutFeature("自定义识别词", "添加专有名词和术语，由 LLM 自动纠正")
                    aboutFeature("调试日志", "记录识别和处理的完整过程，支持导出调优")
                    aboutFeature("历史记录", "自动保存每次输入，支持复制和粘贴")
                    aboutFeature("全局快捷键", "默认 ⌘⇧V，可在设置中自定义")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().padding(.horizontal, 16)

                // Links
                SectionHeader(title: "资源链接")
                VStack(alignment: .leading, spacing: 6) {
                    aboutLinkRow(
                        icon: "link",
                        title: "GitHub 代码仓库",
                        subtitle: githubURL,
                        url: githubURL
                    )
                    aboutLinkRow(
                        icon: "doc.text",
                        title: "开源协议",
                        subtitle: "MPL 2.0 License",
                        url: "\(githubURL)/blob/main/LICENSE"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().padding(.horizontal, 16)

                // System info
                SectionHeader(title: "系统信息")
                VStack(alignment: .leading, spacing: 4) {
                    aboutInfoRow("系统要求", "macOS 13.0+")
                    aboutInfoRow("应用版本", "\(appVersion) (build \(appBuildNumber))")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private func aboutFeature(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func aboutLinkRow(icon: String, title: String, subtitle: String, url: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.accentColor)
            }

            Spacer()

            Button {
                if let nsurl = URL(string: url) {
                    NSWorkspace.shared.open(nsurl)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开")
        }
        .padding(.vertical, 4)
    }

    private func aboutInfoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func refreshHistory() {
        historyEntries = HistoryManager.shared.getAllEntries()
    }

    private func playAudio(entry: HistoryEntry) {
        guard let filename = entry.audioFilename,
              let url = HistoryManager.shared.audioURL(for: filename) else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[History] Audio playback error: \(error)")
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        accessGranted = AXIsProcessTrustedWithOptions(options)
    }

    private func saveAll() {
        config.customWords = customWords
        config.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

// MARK: - Custom Word Input View

struct CustomWordInputView: View {
    @Binding var customWords: [String]
    @State private var newWord: String = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("输入词汇，按回车添加", text: $newWord)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .onSubmit {
                    addWord()
                }

            Button("添加") {
                addWord()
            }
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(newWord.trimmingCharacters(in: .whitespaces).isEmpty
                         ? Color.accentColor.opacity(0.4)
                         : Color.accentColor)
            )
            .buttonStyle(.plain)
            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !customWords.contains(word) else { return }
        customWords.append(word)
        newWord = ""
    }
}

// MARK: - About App Icon (NSViewRepresentable)

struct AboutAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true

        // Load the best available app icon
        let icon = NSApp.applicationIconImage
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 64, height: 64)
        imageView.image = icon

        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

// MARK: - Notification

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
    static let switchSettingsTab = Notification.Name("switchSettingsTab")
}
