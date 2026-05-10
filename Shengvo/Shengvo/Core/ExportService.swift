import Foundation
import AppKit

class ExportService {
    static let shared = ExportService()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// 生成 CSV 字符串（UTF-8 BOM）
    func generateCSV(entries: [HistoryEntry]) -> String {
        let header = "时间,文本,原始文本,目标应用,ASR引擎,LLM处理,ASR耗时ms,LLM耗时ms,总耗时ms,音频文件"
        let rows = entries.map { entry -> String in
            let time = dateFormatter.string(from: entry.timestamp)
            let text = csvEscape(entry.text)
            let rawText = csvEscape(entry.rawText)
            let targetApp = entry.targetApp ?? ""
            let asrMode = entry.asrModeLabel
            let llmProcessed = entry.wasProcessedByLLM ? "是" : "否"
            let audioFile = entry.audioFilename ?? ""
            return "\(time),\(text),\(rawText),\(targetApp),\(asrMode),\(llmProcessed),\(entry.asrDurationMs),\(entry.llmDurationMs),\(entry.totalDurationMs),\(audioFile)"
        }
        let bom = "\u{FEFF}"
        return bom + ([header] + rows).joined(separator: "\n")
    }

    private func csvEscape(_ str: String) -> String {
        let escaped = str.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// 导出历史记录到文件夹
    func exportEntries(_ entries: [HistoryEntry], completion: @escaping (Bool, String?) -> Void) {
        guard !entries.isEmpty else {
            completion(false, "没有可导出的记录")
            return
        }

        let savePanel = NSSavePanel()
        let folderName = "Shengvo-Export-\(folderDateString())"
        savePanel.title = "导出历史记录"
        savePanel.nameFieldStringValue = folderName
        savePanel.canCreateDirectories = true
        savePanel.prompt = "导出"

        savePanel.begin { response in
            guard response == .OK, let exportURL = savePanel.url else {
                completion(false, nil)
                return
            }

            let success = self.writeExport(to: exportURL, entries: entries)
            completion(success, success ? exportURL.path : nil)
        }
    }

    private func folderDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private func writeExport(to folderURL: URL, entries: [HistoryEntry]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            // CSV index
            let csv = generateCSV(entries: entries)
            let csvURL = folderURL.appendingPathComponent("index.csv")
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)

            // Audio files + individual text files
            let audioDir = audioDirURL()
            for entry in entries {
                let baseName = entry.timestamp.isoFilename

                // Text file
                let txtContent = "[文本]\n\(entry.text)\n\n[原始识别文本]\n\(entry.rawText)\n\n[元信息]\n时间: \(dateFormatter.string(from: entry.timestamp))\n目标应用: \(entry.targetApp ?? "无")\nASR引擎: \(entry.asrModeLabel)\nLLM处理: \(entry.wasProcessedByLLM ? "是" : "否")\nASR耗时: \(entry.asrDurationMs)ms\nLLM耗时: \(entry.llmDurationMs)ms\n总耗时: \(entry.totalDurationMs)ms\n"
                let txtURL = folderURL.appendingPathComponent("\(baseName).txt")
                try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)

                // Audio file (copy)
                if let fn = entry.audioFilename {
                    let srcURL = audioDir.appendingPathComponent(fn)
                    if FileManager.default.fileExists(atPath: srcURL.path) {
                        let ext = (fn as NSString).pathExtension
                        let dstURL = folderURL.appendingPathComponent("\(baseName).\(ext)")
                        try FileManager.default.copyItem(at: srcURL, to: dstURL)
                    }
                }
            }

            return true
        } catch {
            print("[Export] Error: \(error)")
            return false
        }
    }

    private func audioDirURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Shengvo/audio")
    }
}

private extension Date {
    var isoFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = .current
        return f.string(from: self)
    }
}
