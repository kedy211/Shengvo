import SwiftUI
import AVFoundation

struct SetupView: View {
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
            case .microphone:
                microphoneStep
            case .accessibility:
                accessibilityStep
            case .done:
                doneStep
            }
        }
        .frame(width: 420, height: 320)
        .padding(32)
        .onAppear {
            checkExistingPermissions()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("欢迎使用 晟语")
                .font(.title2)
                .fontWeight(.semibold)

            Text("开始前需要授予两个权限：\n1. 麦克风 — 录制语音\n2. 辅助功能 — 自动粘贴文字")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("开始设置") {
                step = .microphone
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
    case microphone
    case accessibility
    case done
}
