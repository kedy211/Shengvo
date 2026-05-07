import AppKit

final class SoundManager {
    static let shared = SoundManager()

    private let startSound: NSSound?
    private let stopSound: NSSound?

    private init() {
        startSound = NSSound(named: "Tink")
        stopSound = NSSound(named: "Tink")
    }

    func playStartRecording() {
        startSound?.play()
    }

    func playStopRecording() {
        stopSound?.play()
    }
}
