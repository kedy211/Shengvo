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
        hosting.view.frame = NSRect(x: 0, y: 0, width: 160, height: 44)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting.view
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false

        // Position at cursor location
        let mouseLocation = NSEvent.mouseLocation
        let windowWidth: CGFloat = 160
        let windowHeight: CGFloat = 44
        let xOffset: CGFloat = 20
        let yOffset: CGFloat = 16

        var x = mouseLocation.x + xOffset
        var y = mouseLocation.y + yOffset

        // Clamp to visible screen area
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            if x + windowWidth > screenFrame.maxX {
                x = mouseLocation.x - xOffset - windowWidth
            }
            if y + windowHeight > screenFrame.maxY {
                y = mouseLocation.y - yOffset - windowHeight
            }
            if x < screenFrame.minX {
                x = screenFrame.minX
            }
            if y < screenFrame.minY {
                y = screenFrame.minY
            }
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.orderFront(nil)
        self.window = window
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
        HStack(spacing: 10) {
            if viewModel.state == .recording {
                Image("inputicon")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                WaveView(level: viewModel.audioLevel, phase: wavePhase)
                    .frame(width: 70, height: 24)
            } else if viewModel.state == .processing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)

                Text("处理中...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .frame(minHeight: 24, maxHeight: 24)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(width: 160, height: 44)
        .onReceive(timer) { _ in
            if viewModel.state == .recording {
                wavePhase += 0.35
            }
        }
    }
}

// MARK: - Wave View

struct WaveView: View {
    let level: Float
    let phase: Double

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let maxHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let offset = Double(index) * 0.5
                let boosted = pow(CGFloat(max(0.05, level)), 0.6)
                let wave = 0.5 + 0.5 * sin(phase + offset)
                let height = maxHeight * boosted * CGFloat(wave)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: barWidth, height: max(3, height))
            }
        }
    }
}

