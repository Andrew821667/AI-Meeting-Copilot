import Foundation
import SQLite3

public final class SessionHistoryStore {
    public init() {}

    public func loadHistory() -> [SessionHistoryItem] {
        let exportsDir = resolveExportsDirectory()
        let sqlitePath = (exportsDir as NSString).appendingPathComponent("sessions.sqlite3")

        if FileManager.default.fileExists(atPath: sqlitePath), let fromSQLite = loadHistoryFromSQLite(sqlitePath) {
            return fromSQLite
        }

        return loadHistoryFromExports(exportsDir)
    }

    private func loadHistoryFromSQLite(_ sqlitePath: String) -> [SessionHistoryItem]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(sqlitePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT session_id, profile_id, started_at, ended_at, total_cards, fallback_cards, export_json_path
        FROM session_history
        ORDER BY ended_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var history: [SessionHistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let sessionID = sqliteString(statement, index: 0) ?? UUID().uuidString
            let profileID = sqliteString(statement, index: 1) ?? "unknown"
            let startedAtSeconds = sqlite3_column_double(statement, 2)
            let endedAtSeconds = sqlite3_column_double(statement, 3)
            let totalCards = Int(sqlite3_column_int64(statement, 4))
            let fallbackCards = Int(sqlite3_column_int64(statement, 5))
            let exportPath = sqliteString(statement, index: 6) ?? ""

            history.append(
                SessionHistoryItem(
                    id: sessionID,
                    profileID: profileID,
                    startedAt: Date(timeIntervalSince1970: startedAtSeconds),
                    endedAt: Date(timeIntervalSince1970: endedAtSeconds),
                    totalCards: totalCards,
                    fallbackCards: fallbackCards,
                    exportPath: exportPath
                )
            )
        }
        return history
    }

    private func loadHistoryFromExports(_ exportsDir: String) -> [SessionHistoryItem] {
        let directoryURL = URL(fileURLWithPath: exportsDir)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var history: [SessionHistoryItem] = []
        for fileURL in items where fileURL.pathExtension.lowercased() == "json" {
            guard !fileURL.lastPathComponent.hasSuffix("-report.json") else { continue }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            guard let sessionID = object["session_id"] as? String else { continue }
            let profileID = (object["profile"] as? String) ?? "unknown"
            let startedAtSeconds = (object["started_at"] as? TimeInterval) ?? 0
            let endedAtSeconds = (object["ended_at"] as? TimeInterval) ?? 0
            let metrics = (object["metrics"] as? [String: Any]) ?? [:]
            let totalCards = Int((metrics["total_cards"] as? NSNumber)?.doubleValue ?? 0)
            let fallbackCards = Int((metrics["fallback_cards"] as? NSNumber)?.doubleValue ?? 0)

            history.append(
                SessionHistoryItem(
                    id: sessionID,
                    profileID: profileID,
                    startedAt: Date(timeIntervalSince1970: startedAtSeconds),
                    endedAt: Date(timeIntervalSince1970: endedAtSeconds),
                    totalCards: totalCards,
                    fallbackCards: fallbackCards,
                    exportPath: fileURL.path
                )
            )
        }
        return history.sorted(by: { $0.endedAt > $1.endedAt })
    }

    private func sqliteString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func resolveExportsDirectory() -> String {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let root = appSupport.appendingPathComponent("AIMeetingCopilot", isDirectory: true)
            return root.appendingPathComponent("exports", isDirectory: true).path
        }
        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("exports")
    }
}
