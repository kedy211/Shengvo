import SwiftUI
import AppKit

class RecordingOverlay {
    private var window: NSWindow?
    private var hostingView: NSHostingController<OverlayContentView>?
    private let viewModel = OverlayViewModel()

    func showRecording() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.state = .recording
            self?.showWindow()
        }
    }

    func showProcessing() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.state = .processing
            self?.viewModel.progress = 0
            self?.viewModel.phaseLabel = "正在识别..."
        }
    }

    func updateProgress(progress: Double, phaseLabel: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.progress = progress
            self?.viewModel.phaseLabel = phaseLabel
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.audioLevel = level
        }
    }

    func updatePartialText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.partialText = text
        }
    }

    private func showWindow() {
        guard window == nil else { return }

        let contentView = OverlayContentView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: contentView)

        // Dynamic sizing: fit content, max 350pt wide
        let fitSize = hosting.view.fittingSize
        let panelWidth: CGFloat = max(128, min(350, fitSize.width))
        let panelHeight: CGFloat = max(35, fitSize.height)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting.view
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.worksWhenModal = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Position at bottom center of main display
        let bottomMargin: CGFloat = 40

        let x: CGFloat
        let y: CGFloat
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            x = screenFrame.midX - panelWidth / 2
            y = screenFrame.minY + bottomMargin
        } else {
            x = 400
            y = 40
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFront(nil)
        self.window = panel
        self.hostingView = hosting
    }
}

// MARK: - ViewModel

class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var audioLevel: Float = 0
    @Published var partialText: String = ""
    @Published var progress: Double = 0
    @Published var phaseLabel: String = ""
}

enum OverlayState {
    case hidden
    case recording
    case processing
}

// MARK: - SwiftUI View

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    @State private var wavePhase: Double = 0
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .leading) {
            // 处理阶段：进度条填充整个浮窗
            if viewModel.state == .processing {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.22)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(17, geo.size.width * viewModel.progress))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.progress)
                }
            }

            // 内容层
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    if viewModel.state == .recording {
                        Image("inputicon")
                            .resizable()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        WaveView(level: viewModel.audioLevel, phase: wavePhase)
                            .frame(width: 56, height: 19)
                    } else if viewModel.state == .processing {
                        Text(viewModel.phaseLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 78, height: 19)
                    }
                }

                if viewModel.state == .recording && !viewModel.partialText.isEmpty {
                    Text(viewModel.partialText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.cyan.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), Color.cyan.opacity(0.15), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .fixedSize()
        .onReceive(timer) { _ in
            if viewModel.state == .recording {
                wavePhase += 0.35
            }
        }
    }
}

// MARK: - Wave View

// MARK: - Visual Effect NSViewRepresentable

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WaveView: View {
    let level: Float
    let phase: Double

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                let offset = Double(index) * 0.5
                let boosted = pow(CGFloat(max(0.05, level)), 0.6)
                let wave = 0.5 + 0.5 * sin(phase + offset)
                let height = maxHeight * boosted * CGFloat(wave)

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: barWidth, height: max(2, height))
            }
        }
    }
}
