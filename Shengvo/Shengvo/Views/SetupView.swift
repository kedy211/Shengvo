import SwiftUI
import AVFoundation

struct SetupView: View {
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var step: SetupStep = .welcome
    @State private var micGranted = false
    @State private var accessGranted = false
    @State private var isChecking = false

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                welcomeStep
            case .modelDownload:
                modelDownloadStep
            case .microphone:
                microphoneStep
            case .accessibility:
                accessibilityStep
            case .done:
                doneStep
            }
        }
        .frame(width: 420, height: 340)
        .padding(32)
        .onAppear {
            checkExistingPermissions()
        }
    }

    // MARK: - Steps

    private var modelStepIcon: String {
        switch modelManager.downloadState {
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .notStarted: return "arrow.down.circle"
        }
    }

    private var modelStepColor: Color {
        switch modelManager.downloadState {
        case .ready: return .green
        case .failed: return .orange
        case .downloading: return .blue
        case .notStarted: return .blue
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 20) {
            Image(systemName: modelStepIcon)
                .font(.system(size: 60))
                .foregroundColor(modelStepColor)

            Text("语音识别模型")
                .font(.title2)
                .fontWeight(.semibold)

            if case .downloading = modelManager.downloadState {
                Text("正在下载 Whisper 模型…")
                    .foregroundColor(.secondary)
                ProgressView()
                    .scaleEffect(0.8)
                Text("约 78MB，首次启动时自动缓存")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if case .failed(let msg) = modelManager.downloadState {
                Text("下载失败")
                    .foregroundColor(.secondary)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            } else if modelManager.isModelReady {
                Text("已就绪")
                    .foregroundColor(.secondary)
            } else {
                Text("需要下载 Whisper 语音识别模型\n约 78MB，仅首次需要")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            if modelManager.isModelReady {
                Button("下一步") {
                    step = .microphone
                }
                .buttonStyle(.borderedProminent)
            } else if case .downloading = modelManager.downloadState {
                // 下载中不显示按钮
                EmptyView()
            } else if case .failed = modelManager.downloadState {
                HStack(spacing: 12) {
                    Button("重试") {
                        downloadModel()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("跳过") {
                        step = .microphone
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button("下载模型") {
                        downloadModel()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("跳过") {
                        step = .microphone
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            if !modelManager.isModelReady {
                modelManager.downloadState = .notStarted
            }
        }
    }

    private func downloadModel() {
        Task {
            do {
                _ = try await modelManager.prepareModel()
            } catch {
                // 错误状态已由 ModelManager.downloadState 反映
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("欢迎使用 晟语")
                .font(.title2)
                .fontWeight(.semibold)

            Text("开始前需要完成以下设置：\n1. 下载语音识别模型（约78MB）\n2. 麦克风权限 — 录制语音\n3. 辅助功能权限 — 自动粘贴文字")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("开始设置") {
                step = .modelDownload
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: micGranted ? "checkmark.circle.fill" : "mic.circle")
                .font(.system(size: 60))
                .foregroundColor(micGranted ? .green : .blue)

            Text("麦克风权限")
                .font(.title2)
                .fontWeight(.semibold)

            Text(micGranted ? "已授权" : "需要麦克风权限来录制语音")
                .foregroundColor(.secondary)

            if micGranted {
                Button("下一步") {
                    step = .accessibility
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("授权麦克风") {
                    requestMicPermission()
                }
                .buttonStyle(.borderedProminent)

                Button("跳过") {
                    step = .accessibility
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: accessGranted ? "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(accessGranted ? .green : .blue)

            Text("辅助功能权限")
                .font(.title2)
                .fontWeight(.semibold)

            Text(accessGranted ? "已授权" : "需要辅助功能权限来自动粘贴文字到光标处")
                .foregroundColor(.secondary)

            if accessGranted {
                Button("完成") {
                    step = .done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onComplete()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("打开系统偏好设置") {
                    openAccessibilitySettings()
                    // Start polling for permission
                    startAccessibilityPolling()
                }
                .buttonStyle(.borderedProminent)

                Button("跳过") {
                    step = .done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("设置完成")
                .font(.title2)
                .fontWeight(.semibold)

            Text("按 ⌘+⇧+V 开始录音")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Permission Logic

    private func checkExistingPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        accessGranted = AXIsProcessTrustedWithOptions(options)

        // If both granted, skip to done
        if micGranted && accessGranted {
            step = .done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
            }
        }
    }

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.micGranted = granted
            }
        }
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func startAccessibilityPolling() {
        isChecking = true
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if trusted {
                DispatchQueue.main.async {
                    self.accessGranted = true
                    self.isChecking = false
                }
                timer.invalidate()
            }
        }
    }
}

// MARK: - Setup Step Enum

enum SetupStep {
    case welcome
    case modelDownload
    case microphone
    case accessibility
    case done
}
