import Foundation

public final class SessionHistoryStore {
    public init() {}

    public func loadHistory() -> [SessionHistoryItem] {
        let exportsDir = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("exports")
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
}
