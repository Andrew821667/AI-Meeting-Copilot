import Foundation
import AppKit
import SwiftUI

/// Управляет окном «Память». Работает локально через FileManager + JSON
/// для настроек. Если backend подключён по UDS — отправляет туда обновления,
/// чтобы изменения подхватились в активной сессии немедленно.
@MainActor
public final class MemoryViewModel: ObservableObject {
    @Published public private(set) var state: MemoryState
    @Published public var isBusy: Bool = false
    @Published public var lastError: String?

    private weak var udsClient: UDSEventClient?

    public init() {
        let dir = Self.memoryDir()
        let settings = Self.loadSettings()
        self.state = MemoryState(
            settings: settings,
            files: Self.listFiles(in: dir),
            total_chars: 0,
            limit_chars: 30_000,
            truncated: false,
            folder_path: dir.path,
            rag_available: false
        )
        recomputeAggregates()
    }

    // MARK: - Public API

    public func attachUDSClient(_ client: UDSEventClient) {
        self.udsClient = client
    }

    public func reload() {
        let dir = Self.memoryDir()
        Self.ensureDirectory(dir)
        let files = Self.listFiles(in: dir)
        var newState = state
        newState.folder_path = dir.path
        newState.files = files
        self.state = newState
        recomputeAggregates()
        sendRefreshToBackend()
    }

    public func setEnabled(_ enabled: Bool) {
        var updated = state.settings
        updated.enabled = enabled
        applyAndPersist(updated)
    }

    public func setMode(_ mode: String) {
        var updated = state.settings
        updated.mode = mode
        applyAndPersist(updated)
    }

    public func revealInFinder() {
        let dir = Self.memoryDir()
        Self.ensureDirectory(dir)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    public func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.message = "Выберите .md или .txt файлы для памяти"
        let response = panel.runModal()
        guard response == .OK else { return }

        let dir = Self.memoryDir()
        Self.ensureDirectory(dir)
        var imported = 0
        for src in panel.urls {
            let ext = src.pathExtension.lowercased()
            guard ["md", "txt", "markdown"].contains(ext) else {
                continue
            }
            let dest = uniqueDestination(in: dir, baseName: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                imported += 1
            } catch {
                lastError = "Не удалось скопировать \(src.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if imported > 0 {
            reload()
        }
    }

    public func deleteFile(_ file: MemoryFileInfo) {
        let path = URL(fileURLWithPath: state.folder_path).appendingPathComponent(file.name)
        do {
            try FileManager.default.removeItem(at: path)
            reload()
        } catch {
            lastError = "Не удалось удалить \(file.name): \(error.localizedDescription)"
        }
    }

    public func handleStateFromBackend(_ incoming: MemoryState) {
        // Backend — авторитет по содержимому: его счётчики chars точнее (он
        // считает все варианты кодировок). Локальные настройки оставляем,
        // т.к. они уже могли быть изменены пользователем в UI.
        var merged = incoming
        merged.settings = state.settings
        self.state = merged
    }

    // MARK: - Internals

    private func applyAndPersist(_ settings: MemorySettings) {
        var updated = state
        updated.settings = settings
        self.state = updated
        do {
            try Self.saveSettings(settings)
        } catch {
            lastError = "Не удалось сохранить настройки памяти: \(error.localizedDescription)"
        }
        sendSettingsToBackend(settings)
    }

    private func recomputeAggregates() {
        var s = state
        s.total_chars = s.files.reduce(0) { $0 + $1.chars }
        s.truncated = s.total_chars > s.limit_chars
        self.state = s
    }

    private func uniqueDestination(in dir: URL, baseName: String) -> URL {
        var candidate = dir.appendingPathComponent(baseName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let stem = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        var idx = 2
        while true {
            let attempt = "\(stem) (\(idx))\(ext.isEmpty ? "" : ".")\(ext)"
            candidate = dir.appendingPathComponent(attempt)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            idx += 1
        }
    }

    private func sendSettingsToBackend(_ settings: MemorySettings) {
        guard let client = udsClient else { return }
        struct Payload: Codable { let enabled: Bool; let mode: String }
        let payload = Payload(enabled: settings.enabled, mode: settings.mode)
        Task {
            try? await client.send(type: "memory_set_settings", payload: payload)
        }
    }

    private func sendRefreshToBackend() {
        guard let client = udsClient else { return }
        struct Empty: Codable {}
        Task {
            try? await client.send(type: "memory_refresh", payload: Empty())
        }
    }

    // MARK: - Static FS helpers

    static func memoryDir() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return support
            .appendingPathComponent("AIMeetingCopilot", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
    }

    static func settingsFile() -> URL {
        memoryDir().deletingLastPathComponent().appendingPathComponent("memory_settings.json")
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func loadSettings() -> MemorySettings {
        let url = settingsFile()
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(MemorySettings.self, from: data) else {
            return MemorySettings()
        }
        return settings
    }

    static func saveSettings(_ settings: MemorySettings) throws {
        let url = settingsFile()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }

    static func listFiles(in dir: URL) -> [MemoryFileInfo] {
        ensureDirectory(dir)
        let allowedExt: Set<String> = ["md", "txt", "markdown"]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var result: [MemoryFileInfo] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            if name == "README.md" { continue }
            guard allowedExt.contains(url.pathExtension.lowercased()) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let chars = (try? String(contentsOf: url, encoding: .utf8))?.count ?? 0
            result.append(MemoryFileInfo(
                name: name,
                size_bytes: size,
                chars: chars,
                modified_ts: modified
            ))
        }
        return result
    }
}
