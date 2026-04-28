import Foundation

public struct MemorySettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var mode: String  // "plain" | "rag"

    public init(enabled: Bool = true, mode: String = "plain") {
        self.enabled = enabled
        self.mode = mode
    }
}

public struct MemoryFileInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var size_bytes: Int
    public var chars: Int
    public var modified_ts: Double

    public var id: String { name }

    public init(name: String, size_bytes: Int, chars: Int, modified_ts: Double) {
        self.name = name
        self.size_bytes = size_bytes
        self.chars = chars
        self.modified_ts = modified_ts
    }
}

public struct MemoryState: Codable, Equatable, Sendable {
    public var settings: MemorySettings
    public var files: [MemoryFileInfo]
    public var total_chars: Int
    public var limit_chars: Int
    public var truncated: Bool
    public var folder_path: String
    public var rag_available: Bool

    public init(
        settings: MemorySettings = MemorySettings(),
        files: [MemoryFileInfo] = [],
        total_chars: Int = 0,
        limit_chars: Int = 30_000,
        truncated: Bool = false,
        folder_path: String = "",
        rag_available: Bool = false
    ) {
        self.settings = settings
        self.files = files
        self.total_chars = total_chars
        self.limit_chars = limit_chars
        self.truncated = truncated
        self.folder_path = folder_path
        self.rag_available = rag_available
    }
}
