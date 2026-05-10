import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let rawText: String
    let timestamp: Date
    let targetApp: String?
    let wasProcessedByLLM: Bool
    let audioFilename: String?
    let asrMode: String
    let asrDurationMs: Int
    let llmDurationMs: Int
    let totalDurationMs: Int

    init(
        text: String,
        rawText: String,
        timestamp: Date = Date(),
        targetApp: String? = nil,
        wasProcessedByLLM: Bool = false,
        audioFilename: String? = nil,
        asrMode: String = "",
        asrDurationMs: Int = 0,
        llmDurationMs: Int = 0,
        totalDurationMs: Int = 0
    ) {
        self.id = UUID()
        self.text = text
        self.rawText = rawText
        self.timestamp = timestamp
        self.targetApp = targetApp
        self.wasProcessedByLLM = wasProcessedByLLM
        self.audioFilename = audioFilename
        self.asrMode = asrMode
        self.asrDurationMs = asrDurationMs
        self.llmDurationMs = llmDurationMs
        self.totalDurationMs = totalDurationMs
    }

    /// 从 SQLite row 创建（兼容迁移自 JSON 的旧数据：缺少新字段时使用默认值）
    init?(row: [String: Any]) {
        guard let idStr = row["id"] as? String,
              let id = UUID(uuidString: idStr),
              let text = row["text"] as? String,
              let rawText = row["raw_text"] as? String,
              let ts = row["timestamp"] as? Double else { return nil }

        self.id = id
        self.text = text
        self.rawText = rawText
        self.timestamp = Date(timeIntervalSinceReferenceDate: ts)
        self.targetApp = row["target_app"] as? String
        self.wasProcessedByLLM = (row["was_llm_processed"] as? Int64 ?? 0) != 0
        self.audioFilename = row["audio_filename"] as? String
        self.asrMode = row["asr_mode"] as? String ?? ""
        self.asrDurationMs = Int(row["asr_duration_ms"] as? Int64 ?? 0)
        self.llmDurationMs = Int(row["llm_duration_ms"] as? Int64 ?? 0)
        self.totalDurationMs = Int(row["total_duration_ms"] as? Int64 ?? 0)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var truncatedText: String {
        let lines = text.components(separatedBy: .newlines)
        let preview = lines.prefix(3).joined(separator: "\n")
        return preview.count > 200 ? String(preview.prefix(200)) + "..." : preview
    }

    var asrModeLabel: String {
        switch asrMode {
        case "local": return "Whisper"
        case "cloud": return "火山引擎"
        case "qwen_cloud": return "Qwen"
        case "apple": return "Apple"
        default: return asrMode
        }
    }
}
