import Foundation

class AppLogger {
    static let shared = AppLogger()

    private let logDirectory: URL
    private let dateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private let queue = DispatchQueue(label: "com.voiceinput.logger", qos: .utility)

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDirectory = home.appendingPathComponent("Library/Logs/Shengvo")
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter = ISO8601DateFormatter()
        ensureDirectory()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func log(category: String, message: String, fields: [String: Any] = [:]) {
        guard AppConfig.shared.logEnabled else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureDirectory()

            let fileName = "shengvo-\(self.dateFormatter.string(from: Date())).log"
            let fileURL = self.logDirectory.appendingPathComponent(fileName)

            var record: [String: Any] = [
                "ts": self.isoFormatter.string(from: Date()),
                "cat": category,
                "msg": message
            ]
            for (key, value) in fields {
                record[key] = value
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: record),
               let jsonLine = String(data: jsonData, encoding: .utf8) {
                let line = jsonLine + "\n"
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data(line.utf8))
                    try? handle.close()
                } else {
                    try? line.data(using: .utf8)?.write(to: fileURL)
                }
            }
        }
    }

    func logASR(mode: String, inputSize: Int, output: String, durationMs: Int) {
        log(category: "ASR", message: "识别完成", fields: [
            "mode": mode,
            "input_size_bytes": inputSize,
            "output_text": output,
            "duration_ms": durationMs
        ])
    }

    func logLLM(systemPrompt: String, userText: String, output: String, durationMs: Int) {
        log(category: "LLM", message: "处理完成", fields: [
            "system_prompt": systemPrompt,
            "input_text": userText,
            "output_text": output,
            "duration_ms": durationMs
        ])
    }

    func logTiming(event: String, durationMs: Int) {
        log(category: "Timing", message: event, fields: [
            "duration_ms": durationMs
        ])
    }
}
