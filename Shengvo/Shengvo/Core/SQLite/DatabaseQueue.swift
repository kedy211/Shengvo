import Foundation
// sqlite3 functions available via bridging header

final class DatabaseQueue {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.shengvo.sqlite", qos: .userInitiated)
    private let dbPath: String

    init(path: String) {
        self.dbPath = path
        queue.sync {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if sqlite3_open(path, &db) != SQLITE_OK {
                print("[SQLite] Failed to open database at \(path): \(self.lastError())")
                db = nil
            } else {
                sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
                sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
            }
        }
    }

    deinit {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
            }
        }
    }

    private func lastError() -> String {
        guard let db = db else { return "no connection" }
        return String(cString: sqlite3_errmsg(db))
    }

    func execute(_ sql: String, _ params: [Any] = []) {
        queue.sync {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                print("[SQLite] Prepare error: \(self.lastError()) — \(sql)")
                return
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite] Step error: \(self.lastError())")
            }
        }
    }

    func executeReturning<T>(_ sql: String, _ params: [Any] = [], _ rowMapper: ([String: Any]) -> T?) -> [T] {
        queue.sync {
            guard let db = self.db else { return [] }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                print("[SQLite] Prepare error: \(self.lastError()) — \(sql)")
                return []
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)

            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let colCount = sqlite3_column_count(stmt)
                for i in 0..<colCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row[name] = sqlite3_column_int64(stmt, i)
                    case SQLITE_FLOAT:
                        row[name] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        row[name] = String(cString: sqlite3_column_text(stmt, i))
                    case SQLITE_NULL:
                        row[name] = nil
                    default:
                        row[name] = nil
                    }
                }
                if let mapped = rowMapper(row) {
                    results.append(mapped)
                }
            }
            return results
        }
    }

    func executeScalar(_ sql: String, _ params: [Any] = []) -> Int64 {
        queue.sync {
            guard let db = self.db else { return 0 }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                return 0
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
    }

    func executeInTransaction(_ block: @escaping () -> Void) {
        queue.async { [weak self] in
            self?.execute("BEGIN TRANSACTION")
            block()
            self?.execute("COMMIT")
        }
    }

    func sync<T>(_ block: () -> T) -> T {
        queue.sync(execute: block)
    }

    // MARK: - Parameter binding

    private func bind(_ stmt: OpaquePointer?, _ params: [Any]) {
        guard let stmt = stmt else { return }
        for (idx, param) in params.enumerated() {
            let col = Int32(idx + 1)
            if param is NSNull {
                sqlite3_bind_null(stmt, col)
            } else if let v = param as? String {
                sqlite3_bind_text(stmt, col, (v as NSString).utf8String, -1, nil)
            } else if let v = param as? Int {
                sqlite3_bind_int64(stmt, col, Int64(v))
            } else if let v = param as? Int64 {
                sqlite3_bind_int64(stmt, col, v)
            } else if let v = param as? Double {
                sqlite3_bind_double(stmt, col, v)
            } else if let v = param as? Bool {
                sqlite3_bind_int64(stmt, col, v ? 1 : 0)
            } else {
                let str = "\(param)"
                sqlite3_bind_text(stmt, col, (str as NSString).utf8String, -1, nil)
            }
        }
    }
}
