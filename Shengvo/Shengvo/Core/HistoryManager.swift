import Foundation

class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.shengvo.history", qos: .userInitiated)
    private var entries: [HistoryEntry] = []

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Shengvo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private init() {
        load()
    }

    func addEntry(_ entry: HistoryEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
            self.save()
        }
    }

    func deleteEntry(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.removeAll { $0.id == id }
            self.save()
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
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
