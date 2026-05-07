import SwiftUI
import AVFoundation

// MARK: - Sidebar Item

enum SettingsTab: String, CaseIterable {
    case general = "通用"
    case models = "模型设置"
    case customWords = "自定义识别词"
    case history = "历史记录"
    case about = "关于"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
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
        } detail: {
            detailContent
        }
        .frame(width: 620, height: 560)
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
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            generalSettings
        case .models:
            modelSettings
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
                    usesFn: $config.hotKeyUsesFn
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
        .background(Color(nsColor: .controlBackgroundColor))
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

    // MARK: - Model Settings

    private var modelSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ASR Section
                SectionHeader(title: "语音识别 (ASR)")

                // ASR Mode Picker
                HStack(spacing: 12) {
                    Text("识别引擎")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                    Spacer()
                    Picker("", selection: $config.asrMode) {
                        Text("本地 (Whisper)").tag("local")
                        Text("云端 (火山引擎)").tag("cloud")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(height: 40)

                if config.asrMode == "local" {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Whisper base (q8_0 量化, ~95MB)")
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

                Divider().padding(.horizontal, 16)

                // LLM Section
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

                    // Reasoning Effort
                    reasoningEffortRow

                    Divider().padding(.horizontal, 16)

                    // System Prompt
                    SectionHeader(title: " ")
                    SettingTextEditor(
                        title: "系统提示词",
                        subtitle: "自定义 LLM 处理文本的行为规则",
                        placeholder: "输入系统提示词...",
                        text: $config.llmSystemPrompt
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
        .background(Color(nsColor: .controlBackgroundColor))
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

                        Button("清空全部") {
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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func historyRow(entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
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

                if entry.wasProcessedByLLM {
                    Text("LLM")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
            }
            .frame(width: 80, alignment: .leading)

            Text(entry.truncatedText)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
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
                .fill(Color.primary.opacity(0.04))
        )
        .onTapGesture(count: 2) {
            ClipboardManager.shared.copyAndPaste(text: entry.text)
        }
    }

    // MARK: - About Settings

    private let githubURL = "https://github.com/kedy211/Shengvo"

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
                    aboutInfoRow("应用版本", "1.0")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
                        .fill(Color(nsColor: .textBackgroundColor))
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
