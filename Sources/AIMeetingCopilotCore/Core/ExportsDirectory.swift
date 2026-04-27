import Foundation

enum ExportsDirectory {
    static func resolve() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_EXPORTS_DIR"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
                .appendingPathComponent("AIMeetingCopilot", isDirectory: true)
                .appendingPathComponent("exports", isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
    }

    static func resolvePath() -> String {
        return resolve().path
    }
}
