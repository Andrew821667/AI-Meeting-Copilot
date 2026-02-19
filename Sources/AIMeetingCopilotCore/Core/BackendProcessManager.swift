import Foundation

public enum BackendProcessError: LocalizedError {
    case backendScriptNotFound(String)
    case pythonExecutableNotFound
    case processFailedToStart(String)
    case socketNotReady(String)

    public var errorDescription: String? {
        switch self {
        case .backendScriptNotFound(let path):
            return "Не найден backend скрипт: \(path)"
        case .pythonExecutableNotFound:
            return "Не найден Python 3 для запуска backend"
        case .processFailedToStart(let details):
            if details.isEmpty {
                return "Backend процесс не стартовал"
            }
            return "Backend процесс не стартовал: \(details)"
        case .socketNotReady(let details):
            return "Backend не открыл UDS-сокет: \(details)"
        }
    }
}

public actor BackendProcessManager {
    private var process: Process?
    private var socketPath: String?

    public init() {}

    public func start() async throws -> String {
        if let socketPath {
            return socketPath
        }

        let launch = try resolveBackendLaunch()

        let socket = "/tmp/ai-meeting-copilot-\(ProcessInfo.processInfo.processIdentifier).sock"
        if FileManager.default.fileExists(atPath: socket) {
            try? FileManager.default.removeItem(atPath: socket)
        }

        let process = Process()
        let exportsDir = resolveExportsDirectory()
        try? FileManager.default.createDirectory(atPath: exportsDir, withIntermediateDirectories: true, attributes: nil)
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments + ["--socket", socket, "--exports-dir", exportsDir]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw BackendProcessError.processFailedToStart(error.localizedDescription)
        }

        self.process = process
        self.socketPath = socket

        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socket) {
                return socket
            }
            if !process.isRunning {
                let details = Self.readPipeOutput(pipe: outputPipe)
                throw BackendProcessError.processFailedToStart(details)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let details = Self.readPipeOutput(pipe: outputPipe)
        throw BackendProcessError.socketNotReady(details.isEmpty ? socket : details)
    }

    public func stop() {
        process?.terminate()
        process = nil

        if let socketPath {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        socketPath = nil
    }

    private struct BackendLaunch {
        let executablePath: String
        let arguments: [String]
    }

    private func resolveBackendLaunch() throws -> BackendLaunch {
        // 1) Explicit full executable path (packaged backend binary or script wrapper).
        if let explicitExecutable = ProcessInfo.processInfo.environment["AIMC_BACKEND_EXECUTABLE"],
           FileManager.default.fileExists(atPath: explicitExecutable) {
            return BackendLaunch(executablePath: explicitExecutable, arguments: [])
        }

        // 2) App bundle resource backend binary (distribution mode).
        if let resourceRoot = Bundle.main.resourceURL?.path {
            let packagedBinary = (resourceRoot as NSString).appendingPathComponent("backend/backend_runner")
            if FileManager.default.fileExists(atPath: packagedBinary) {
                return BackendLaunch(executablePath: packagedBinary, arguments: [])
            }
            let packagedScript = (resourceRoot as NSString).appendingPathComponent("backend/main.py")
            if FileManager.default.fileExists(atPath: packagedScript) {
                let python = try resolvePythonExecutable()
                return BackendLaunch(executablePath: python, arguments: [packagedScript])
            }
        }

        // 3) Dev fallback (python script from workspace).
        let backendPath = resolveBackendScriptPath()
        guard FileManager.default.fileExists(atPath: backendPath) else {
            throw BackendProcessError.backendScriptNotFound(backendPath)
        }

        let python = try resolvePythonExecutable()
        return BackendLaunch(executablePath: python, arguments: [backendPath])
    }

    private func resolveBackendScriptPath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_BACKEND_PATH"] {
            return explicit
        }

        // Поиск относительно исполняемого файла (dev-режим из Xcode/swift run)
        if let executableURL = Bundle.main.executableURL {
            let projectCandidates = [
                // swift run: .build/debug/AIMeetingCopilot → ../../backend/main.py
                executableURL.deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("backend/main.py").path,
                // Xcode: DerivedData/.../Build/Products/Debug/AIMeetingCopilot → исходники
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent("backend/main.py").path,
            ]
            for candidate in projectCandidates {
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }

        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent("backend/main.py")
    }

    private func resolveExportsDirectory() -> String {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_EXPORTS_DIR"], !explicit.isEmpty {
            return explicit
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let root = appSupport.appendingPathComponent("AIMeetingCopilot", isDirectory: true)
            return root.appendingPathComponent("exports", isDirectory: true).path
        }

        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("exports")
    }

    private func resolvePythonExecutable() throws -> String {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_PYTHON_EXECUTABLE"],
           FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        throw BackendProcessError.pythonExecutableNotFound
    }

    private static func readPipeOutput(pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return "" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
