import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class ExcludePhraseStore {
    private let dbPath: String

    public init(dbPath: String? = nil) {
        if let dbPath {
            self.dbPath = dbPath
        } else {
            self.dbPath = ExportsDirectory.resolve()
                .appendingPathComponent("feedback.sqlite3")
                .path
        }
        ensureDatabase()
    }

    public func load(profileID: String) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return []
        }
        defer { sqlite3_close(db) }
        ensureTable(db)

        let sql = """
        SELECT phrase
        FROM excluded_phrases
        WHERE profile_id = ?
        ORDER BY created_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (profileID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            values.append(String(cString: cString))
        }
        return values
    }

    @discardableResult
    public func add(profileID: String, phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalize(trimmed)
        guard normalized.count >= 3 else {
            return false
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return false
        }
        defer { sqlite3_close(db) }
        ensureTable(db)

        let sql = """
        INSERT INTO excluded_phrases (
            profile_id, phrase, normalized_phrase, created_at
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(profile_id, normalized_phrase) DO UPDATE SET
            phrase=excluded.phrase,
            created_at=excluded.created_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (profileID as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (trimmed as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (normalized as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)

        return sqlite3_step(statement) == SQLITE_DONE
    }

    @discardableResult
    public func remove(profileID: String, phrase: String) -> Bool {
        let normalized = Self.normalize(phrase)
        guard normalized.count >= 3 else {
            return false
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return false
        }
        defer { sqlite3_close(db) }
        ensureTable(db)

        let sql = """
        DELETE FROM excluded_phrases
        WHERE profile_id = ? AND normalized_phrase = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (profileID as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (normalized as NSString).utf8String, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    public static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased().replacingOccurrences(of: "ё", with: "е")
        let cleaned = lowered.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || CharacterSet.whitespaces.contains(scalar) {
                return String(scalar)
            }
            return " "
        }.joined()
        let collapsed = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed
    }

    private func ensureDatabase() {
        let directory = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db {
            ensureTable(db)
            sqlite3_close(db)
        }
    }

    private func ensureTable(_ db: OpaquePointer) {
        let sql = """
        CREATE TABLE IF NOT EXISTS excluded_phrases (
            profile_id TEXT NOT NULL,
            phrase TEXT NOT NULL,
            normalized_phrase TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY(profile_id, normalized_phrase)
        )
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
