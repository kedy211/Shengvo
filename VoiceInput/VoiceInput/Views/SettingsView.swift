import SwiftUI
import AVFoundation

struct SettingsView: View {
    @State private var config = AppConfig.shared
    @State private var selectedTab = "general"
    @State private var micGranted = false
    @State private var accessGranted = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("通用").tag("general")
                Text("自定义识别词").tag("words")
                Text("模型设置").tag("models")
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            ScrollView {
                switch selectedTab {
                case "general":
                    generalSettings
                case "words":
                    customWordsSettings
                case "models":
                    modelSettings
                default:
                    generalSettings
                }
            }
            .padding()

            Divider()

            // Save button
            HStack {
                Spacer()
                Button("保存") {
                    config.save()
                    NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 550, height: 600)
        .onAppear {
            refreshPermissions()
        }
    }

    // MARK: - Tab 1: General Settings

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通用设置")
                .font(.title3)
                .fontWeight(.medium)

            // Hotkey
            GroupBox(label: Text("快捷键")) {
                VStack(alignment: .leading, spacing: 12) {
                    HotKeyRecorderView(
                        keyCode: $config.hotKeyKeyCode,
                        modifiers: $config.hotKeyModifiers,
                        usesFn: $config.hotKeyUsesFn
                    )
                }
                .padding(8)
            }

            // Options
            GroupBox(label: Text("选项")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机自启动", isOn: $config.launchAtLogin)
                    Toggle("显示通知", isOn: $config.showNotifications)

                    LabeledField(label: "最短录音时长 (秒)") {
                        HStack {
                            TextField("1.0", value: $config.minRecordingDuration, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("秒以内直接跳过，不提交识别")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
            }

            // Permissions
            GroupBox(label: Text("权限状态")) {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(8)
            }
        }
    }

    private func permissionRow(icon: String, title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(granted ? .green : .red)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(granted ? "已授权" : "未授权")
                .font(.caption)
                .foregroundColor(granted ? .green : .red)

            Button("管理") {
                action()
            }
            .controlSize(.small)

            Button("刷新") {
                refreshPermissions()
            }
            .controlSize(.small)
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        accessGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Tab 2: Custom Words

    private var customWordsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自定义识别词")
                .font(.title3)
                .fontWeight(.medium)

            Text("添加专有名词、术语等，提升语音识别准确率。")
                .font(.caption)
                .foregroundColor(.secondary)

            CustomWordsView(customWords: $config.customWords)
        }
    }

    // MARK: - Tab 3: Model Settings

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型设置")
                .font(.title3)
                .fontWeight(.medium)

            // ASR Section
            GroupBox(label: Text("语音识别 (ASR)")) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "App ID") {
                        TextField("火山引擎 App ID", text: $config.asrAppID)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField(label: "Access Token") {
                        SecureField("Access Token", text: $config.asrAccessToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField(label: "Secret Key") {
                        SecureField("Secret Key", text: $config.asrSecretKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }

            // LLM Section
            GroupBox(label: Text("大语言模型 (LLM)")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用文本整理", isOn: $config.llmEnabled)

                    if config.llmEnabled {
                        LabeledField(label: "Base URL") {
                            TextField("https://ark.cn-beijing.volces.com/api/v3", text: $config.llmBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        LabeledField(label: "API Key") {
                            SecureField("API Key", text: $config.llmAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        LabeledField(label: "模型名称") {
                            TextField("doubao-pro-32k", text: $config.llmModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        LabeledField(label: "跳过 LLM 的字数阈值") {
                            HStack {
                                TextField("10", value: $config.llmMinChars, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("字以内直接粘贴原始文本，不调用 LLM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        LabeledField(label: "推理强度 (Reasoning Effort)") {
                            Picker("", selection: $config.llmReasoningEffort) {
                                Text("minimal").tag("minimal")
                                Text("low").tag("low")
                                Text("medium").tag("medium")
                                Text("high").tag("high")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 280)
                        }
                    }
                }
                .padding(8)
            }

            // Prompt Section
            if config.llmEnabled {
                GroupBox(label: Text("系统提示词")) {
                    TextEditor(text: $config.llmSystemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.visible)
                        .frame(minHeight: 180)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Helper Views

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}
