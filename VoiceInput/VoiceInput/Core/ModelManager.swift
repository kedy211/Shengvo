import Foundation

enum ModelDownloadState {
    case notStarted
    case downloading(progress: Double)
    case ready
    case failed(error: String)
}

class ModelManager: ObservableObject {
    static let shared = ModelManager()

    private let modelFileName = "ggml-base-q8_0.bin"
    private let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q8_0.bin")!

    @Published var downloadState: ModelDownloadState = .notStarted

    private var supportDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.voiceinput.app")
    }

    var modelPath: String? {
        let localURL = supportDir.appendingPathComponent(modelFileName)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL.path
        }
        if let bundlePath = Bundle.main.path(forResource: "ggml-base-q8_0", ofType: "bin") {
            return bundlePath
        }
        return nil
    }

    var isModelReady: Bool {
        modelPath != nil
    }

    func prepareModel() async throws -> String {
        if let path = modelPath {
            await MainActor.run { downloadState = .ready }
            return path
        }

        await MainActor.run { downloadState = .downloading(progress: 0) }
        return try await startDownload()
    }

    private func startDownload() async throws -> String {
        let (tempURL, _) = try await URLSession.shared.download(from: modelURL)

        return try await MainActor.run {
            do {
                try FileManager.default.createDirectory(at: self.supportDir, withIntermediateDirectories: true)
                let destURL = self.supportDir.appendingPathComponent(self.modelFileName)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                self.downloadState = .ready
                return destURL.path
            } catch {
                let msg = "保存模型失败: \(error.localizedDescription)"
                self.downloadState = .failed(error: msg)
                throw ModelError.downloadFailed(msg)
            }
        }
    }
}

enum ModelError: LocalizedError {
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return msg
        }
    }
}
