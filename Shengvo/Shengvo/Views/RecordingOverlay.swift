import SwiftUI
import AppKit

class RecordingOverlay {
    private var window: NSWindow?
    private var hostingView: NSHostingController<OverlayContentView>?
    private let viewModel = OverlayViewModel()

    func showRecording() {
        viewModel.state = .recording
        showWindow()
    }

    func showProcessing() {
        viewModel.state = .processing
    }

    func hide() {
        DispatchQueue.main.async {
            self.window?.orderOut(nil)
            self.window = nil
            self.hostingView = nil
        }
    }

    func updateLevel(_ level: Float) {
        viewModel.audioLevel = level
    }

    private func showWindow() {
        guard window == nil else { return }

        let contentView = OverlayContentView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: contentView)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 128, height: 35)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 128, height: 35),
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
        let windowWidth: CGFloat = 128
        let bottomMargin: CGFloat = 40

        let x: CGFloat
        let y: CGFloat
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            x = screenFrame.midX - windowWidth / 2
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
        HStack(spacing: 8) {
            if viewModel.state == .recording {
                Image("inputicon")
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                WaveView(level: viewModel.audioLevel, phase: wavePhase)
                    .frame(width: 56, height: 19)
            } else if viewModel.state == .processing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
                    .frame(width: 13, height: 13)

                Text("处理中...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .frame(minHeight: 19, maxHeight: 19)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Color.black.opacity(0.45)
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
        )
        .frame(width: 128, height: 35)
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

    private let barCount = 4
    private let barWidth: CGFloat = 2
    private let maxHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
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
