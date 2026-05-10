import Foundation

class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 500
    private let db: DatabaseQueue

    private static var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Shengvo")
    }

    private var audioDirURL: URL {
        let dir = Self.baseDir.appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var dbURL: URL {
        let dir = Self.baseDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.db")
    }

    private var oldJSONURL: URL {
        Self.baseDir.appendingPathComponent("history.json")
    }

    private init() {
        db = DatabaseQueue(path: Self.baseDir.appendingPathComponent("history.db").path)
        createTableIfNeeded()
        migrateFromJSONIfNeeded()
    }

    // MARK: - Schema

    private func createTableIfNeeded() {
        db.execute("""
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                timestamp REAL NOT NULL,
                target_app TEXT,
                was_llm_processed INTEGER DEFAULT 0,
                audio_filename TEXT,
                asr_mode TEXT DEFAULT '',
                asr_duration_ms INTEGER DEFAULT 0,
                llm_duration_ms INTEGER DEFAULT 0,
                total_duration_ms INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_entries_timestamp ON entries(timestamp DESC);
        """)
    }

    // MARK: - JSON Migration

    private func migrateFromJSONIfNeeded() {
        guard FileManager.default.fileExists(atPath: oldJSONURL.path) else { return }

        let count = db.executeScalar("SELECT COUNT(*) FROM entries")
        guard count == 0 else {
            // DB already has data, just rename the old JSON as backup
            try? FileManager.default.moveItem(at: oldJSONURL, to: oldJSONURL.appendingPathExtension("bak"))
            return
        }

        guard let data = try? Data(contentsOf: oldJSONURL),
              let oldEntries = try? JSONDecoder().decode([LegacyHistoryEntry].self, from: data),
              !oldEntries.isEmpty else {
            return
        }

        print("[History] Migrating \(oldEntries.count) entries from JSON to SQLite...")
        db.executeInTransaction { [weak self] in
            guard let self = self else { return }
            for entry in oldEntries {
                self.db.execute("""
                    INSERT OR IGNORE INTO entries
                        (id, text, raw_text, timestamp, target_app, was_llm_processed, audio_filename)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, [
                    entry.id.uuidString,
                    entry.text,
                    entry.rawText,
                    entry.timestamp.timeIntervalSinceReferenceDate,
                    entry.targetApp as Any? ?? NSNull(),
                    entry.wasProcessedByLLM ? 1 : 0,
                    entry.audioFilename as Any? ?? NSNull()
                ])
            }
        }

        // Backup the JSON
        let backupURL = oldJSONURL.appendingPathExtension("bak")
        try? FileManager.default.moveItem(at: oldJSONURL, to: backupURL)
        print("[History] Migration complete. JSON backed up to \(backupURL.lastPathComponent)")
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

    func deleteAudio(named filename: String) {
        let url = audioDirURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Entry management

    func addEntry(_ entry: HistoryEntry) {
        db.execute("""
            INSERT INTO entries
                (id, text, raw_text, timestamp, target_app, was_llm_processed, audio_filename,
                 asr_mode, asr_duration_ms, llm_duration_ms, total_duration_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            entry.id.uuidString,
            entry.text,
            entry.rawText,
            entry.timestamp.timeIntervalSinceReferenceDate,
            entry.targetApp as Any? ?? NSNull(),
            entry.wasProcessedByLLM ? 1 : 0,
            entry.audioFilename as Any? ?? NSNull(),
            entry.asrMode,
            entry.asrDurationMs,
            entry.llmDurationMs,
            entry.totalDurationMs
        ])

        // Enforce 500 cap
        let count = db.executeScalar("SELECT COUNT(*) FROM entries")
        if count > maxEntries {
            let excess = count - Int64(maxEntries)
            let oldIds = db.executeReturning(
                "SELECT id, audio_filename FROM entries ORDER BY timestamp ASC LIMIT ?", [Int(excess)]
            ) { row -> (String, String?)? in
                guard let id = row["id"] as? String else { return nil }
                return (id, row["audio_filename"] as? String)
            }
            for (_, audioFn) in oldIds {
                if let fn = audioFn { deleteAudio(named: fn) }
            }
            db.execute("DELETE FROM entries WHERE id IN (SELECT id FROM entries ORDER BY timestamp ASC LIMIT ?)", [Int(excess)])
        }
    }

    func deleteEntry(id: UUID) {
        let entry = db.executeReturning(
            "SELECT audio_filename FROM entries WHERE id = ?", [id.uuidString]
        ) { row -> String? in
            row["audio_filename"] as? String
        }.first

        if let fn = entry { deleteAudio(named: fn) }
        db.execute("DELETE FROM entries WHERE id = ?", [id.uuidString])
    }

    func clearAll() {
        let allFilenames = db.executeReturning(
            "SELECT audio_filename FROM entries WHERE audio_filename IS NOT NULL AND audio_filename != ''"
        ) { row -> String? in
            row["audio_filename"] as? String
        }
        for fn in allFilenames.compactMap({ $0 }) {
            deleteAudio(named: fn)
        }
        db.execute("DELETE FROM entries")
    }

    func getAllEntries() -> [HistoryEntry] {
        db.executeReturning(
            "SELECT * FROM entries ORDER BY timestamp DESC LIMIT ?", [maxEntries]
        ) { HistoryEntry(row: $0) }
    }

    func getEntriesForExport() -> [HistoryEntry] {
        db.executeReturning(
            "SELECT * FROM entries ORDER BY timestamp DESC"
        ) { HistoryEntry(row: $0) }
    }
}

// MARK: - Legacy model for JSON migration

private struct LegacyHistoryEntry: Codable {
    let id: UUID
    let text: String
    let rawText: String
    let timestamp: Date
    let targetApp: String?
    let wasProcessedByLLM: Bool
    let audioFilename: String?
}
