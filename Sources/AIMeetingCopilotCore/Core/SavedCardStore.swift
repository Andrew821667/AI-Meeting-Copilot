import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SavedCardStore {
    private let dbPath: String

    public init() {
        let base = SavedCardStore.resolveAppSupportPath()
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        dbPath = (base as NSString).appendingPathComponent("saved_cards.sqlite3")
        initialize()
        backfillFromExportsIfNeeded(minCount: 50)
    }

    public func upsert(card: InsightCard, sessionID: String, profileID: String) {
        guard let db = openWritableDB() else { return }
        defer { sqlite3_close(db) }

        guard let encoded = try? JSONEncoder().encode(card),
              let cardJSON = String(data: encoded, encoding: .utf8)
        else { return }

        let sql = """
        INSERT INTO saved_cards (
            session_id, profile_id, card_id, agent_name, card_json, saved_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id, card_id, agent_name) DO UPDATE SET
            profile_id=excluded.profile_id,
            card_json=excluded.card_json,
            saved_at=excluded.saved_at
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        bindText(sessionID, to: statement, index: 1)
        bindText(profileID, to: statement, index: 2)
        bindText(card.id, to: statement, index: 3)
        bindText(card.agentName ?? "Оркестратор", to: statement, index: 4)
        bindText(cardJSON, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, now)

        _ = sqlite3_step(statement)
    }

    public func loadLatest(limit: Int = 50) -> [InsightCard] {
        let sql = """
        SELECT card_json
        FROM saved_cards
        ORDER BY saved_at DESC
        LIMIT ?
        """
        return loadCards(sql: sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
        }
    }

    public func loadBySession(sessionID: String) -> [InsightCard] {
        let sql = """
        SELECT card_json
        FROM saved_cards
        WHERE session_id = ?
        ORDER BY saved_at DESC
        """
        return loadCards(sql: sql) { statement in
            bindText(sessionID, to: statement, index: 1)
        }
    }

    public func loadBySessionOrImport(sessionID: String, exportPath: String) -> [InsightCard] {
        let existing = loadBySession(sessionID: sessionID)
        if !existing.isEmpty {
            return existing
        }

        let imported = importCardsFromExport(path: exportPath)
        for card in imported {
            upsert(card: card, sessionID: sessionID, profileID: card.scenario)
        }
        return loadBySession(sessionID: sessionID)
    }

    private func initialize() {
        guard let db = openWritableDB() else { return }
        defer { sqlite3_close(db) }

        let create = """
        CREATE TABLE IF NOT EXISTS saved_cards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            profile_id TEXT NOT NULL,
            card_id TEXT NOT NULL,
            agent_name TEXT NOT NULL,
            card_json TEXT NOT NULL,
            saved_at REAL NOT NULL,
            UNIQUE(session_id, card_id, agent_name)
        )
        """
        _ = sqlite3_exec(db, create, nil, nil, nil)
    }

    private func backfillFromExportsIfNeeded(minCount: Int) {
        if currentCount() >= minCount {
            return
        }

        let exports = (SavedCardStore.resolveAppSupportPath() as NSString).appendingPathComponent("exports")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: exports),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in urls where fileURL.pathExtension.lowercased() == "json" {
            guard !fileURL.lastPathComponent.hasSuffix("-report.json") else { continue }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let payload = try? JSONDecoder().decode(SessionCardsPayload.self, from: data) else { continue }

            for card in payload.cardsShown {
                upsert(card: card, sessionID: payload.sessionID, profileID: payload.profile)
            }
        }
    }

    private func importCardsFromExport(path: String) -> [InsightCard] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return []
        }
        guard let payload = try? JSONDecoder().decode(SessionCardsPayload.self, from: data) else {
            return []
        }
        return payload.cardsShown
    }

    private func currentCount() -> Int {
        guard let db = openWritableDB() else { return 0 }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM saved_cards", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func loadCards(sql: String, bind: (OpaquePointer) -> Void) -> [InsightCard] {
        guard let db = openWritableDB() else { return [] }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bind(statement)

        var cards: [InsightCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let json = String(cString: cString)
            guard let data = json.data(using: .utf8),
                  let card = try? JSONDecoder().decode(InsightCard.self, from: data)
            else { continue }
            cards.append(card)
        }
        return cards
    }

    private func openWritableDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        return db
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private struct SessionCardsPayload: Decodable {
        let sessionID: String
        let profile: String
        let cardsShown: [InsightCard]

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case profile
            case cardsShown = "cards_shown"
        }
    }

    private static func resolveAppSupportPath() -> String {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("AIMeetingCopilot", isDirectory: true).path
        }
        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("AIMeetingCopilot")
    }
}
