import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let rawText: String
    let timestamp: Date
    let targetApp: String?
    let wasProcessedByLLM: Bool

    init(text: String, rawText: String, timestamp: Date = Date(), targetApp: String? = nil, wasProcessedByLLM: Bool = false) {
        self.id = UUID()
        self.text = text
        self.rawText = rawText
        self.timestamp = timestamp
        self.targetApp = targetApp
        self.wasProcessedByLLM = wasProcessedByLLM
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
}
