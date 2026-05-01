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
        hosting.view.frame = NSRect(x: 0, y: 0, width: 120, height: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
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

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 60
            let y = screenFrame.minY + 40
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

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
    @State private var rotationAngle: Double = 0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .frame(width: 80, height: 80)

            if viewModel.state == .recording {
                // Wave bars
                WaveView(level: viewModel.audioLevel, phase: wavePhase)
                    .frame(width: 50, height: 50)
                    .onAppear {
                        startWaveAnimation()
                    }

                // Pulsing ring
                PulsingRing()
                    .frame(width: 80, height: 80)

            } else if viewModel.state == .processing {
                // Spinning loading indicator
                ProcessingView()
                    .frame(width: 50, height: 50)
            }

            // Mic icon
            Image(systemName: viewModel.state == .recording ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(viewModel.state == .recording ? .red : .white)
                .offset(y: viewModel.state == .recording ? -2 : 0)
        }
        .frame(width: 120, height: 120)
        .onAppear {
            if viewModel.state == .recording {
                startWaveAnimation()
            }
        }
        .onChange(of: viewModel.state) { newState in
            if newState == .processing {
                startRotationAnimation()
            }
        }
    }

    private func startWaveAnimation() {
        withAnimation(.linear(duration: 0.15).repeatForever(autoreverses: false)) {
            wavePhase += .pi * 2
        }
    }

    private func startRotationAnimation() {
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            rotationAngle += 360
        }
    }
}

// MARK: - Wave View

struct WaveView: View {
    let level: Float
    let phase: Double

    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let maxHeight: CGFloat = 36

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let offset = Double(index) * 0.4
                let normalizedLevel = max(0.15, min(1.0, level))
                let height = maxHeight * CGFloat(normalizedLevel) * CGFloat(0.5 + 0.5 * sin(phase + offset))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: barWidth, height: max(4, height))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Pulsing Ring

struct PulsingRing: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.4), lineWidth: 2)
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0 : 0.6)
            .animation(
                Animation.easeOut(duration: 1.2)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.white, .clear]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
                .animation(
                    .linear(duration: 1).repeatForever(autoreverses: false),
                    value: rotation
                )
        }
        .frame(width: 40, height: 40)
        .onAppear {
            rotation = 360
        }
    }
}
