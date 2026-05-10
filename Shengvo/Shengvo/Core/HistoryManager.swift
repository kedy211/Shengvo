import Foundation

class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.shengvo.history", qos: .userInitiated)
    private var entries: [HistoryEntry] = []

    private var storageURL: URL {
        let dir = audioDirURL.deletingLastPathComponent()
        return dir.appendingPathComponent("history.json")
    }

    private var audioDirURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Shengvo/audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        load()
    }

    // MARK: - Audio file storage

    func saveAudio(_ data: Data, for entryId: UUID) -> String {
        let filename = "\(entryId.uuidString).wav"
        let fileURL = audioDirURL.appendingPathComponent(filename)
        try? data.write(to: fileURL, options: .atomic)
        return filename
    }

    func audioURL(for filename: String) -> URL? {
        let url = audioDirURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func deleteAudioFile(named filename: String?) {
        guard let filename = filename else { return }
        let url = audioDirURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// 公开的音频删除，供 ASR 失败等场景使用
    func deleteAudio(named filename: String) {
        queue.async { [weak self] in
            self?.deleteAudioFile(named: filename)
        }
    }

    // MARK: - Entry management

    func addEntry(_ entry: HistoryEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                let removed = self.entries.suffix(from: self.maxEntries)
                for e in removed {
                    self.deleteAudioFile(named: e.audioFilename)
                }
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
            self.save()
        }
    }

    func deleteEntry(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let entry = self.entries.first(where: { $0.id == id }) {
                self.deleteAudioFile(named: entry.audioFilename)
            }
            self.entries.removeAll { $0.id == id }
            self.save()
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for entry in self.entries {
                self.deleteAudioFile(named: entry.audioFilename)
            }
            self.entries.removeAll()
            self.save()
        }
    }

    func getAllEntries() -> [HistoryEntry] {
        queue.sync { entries }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
