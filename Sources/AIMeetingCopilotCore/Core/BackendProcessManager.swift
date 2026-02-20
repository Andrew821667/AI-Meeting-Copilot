import Foundation

public enum BackendProcessError: LocalizedError {
    case backendScriptNotFound(String)
    case pythonExecutableNotFound
    case venvSetupFailed(String)
    case processFailedToStart(String)
    case socketNotReady(String)

    public var errorDescription: String? {
        switch self {
        case .backendScriptNotFound(let path):
            return "Не найден backend скрипт: \(path)"
        case .pythonExecutableNotFound:
            return "Не найден Python 3 для запуска backend"
        case .venvSetupFailed(let details):
            return "Не удалось создать venv: \(details)"
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

        let launch = try await resolveBackendLaunch()

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
        process.standardInput = FileHandle.nullDevice

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

    // MARK: - Backend Launch Resolution

    private struct BackendLaunch {
        let executablePath: String
        let arguments: [String]
    }

    private func resolveBackendLaunch() async throws -> BackendLaunch {
        // 1) Явный путь к исполняемому файлу бэкенда (env var).
        if let explicitExecutable = ProcessInfo.processInfo.environment["AIMC_BACKEND_EXECUTABLE"],
           FileManager.default.fileExists(atPath: explicitExecutable) {
            return BackendLaunch(executablePath: explicitExecutable, arguments: [])
        }

        // 2) Скомпилированный бинарник бэкенда в ресурсах бандла (distribution).
        if let resourceRoot = Bundle.main.resourceURL?.path {
            let packagedBinary = (resourceRoot as NSString).appendingPathComponent("backend/backend_runner")
            if FileManager.default.fileExists(atPath: packagedBinary) {
                return BackendLaunch(executablePath: packagedBinary, arguments: [])
            }
        }

        // 3) Dev-режим: находим корень проекта → backend/main.py → venv python.
        let projectRoot = try resolveProjectRoot()
        let backendDir = (projectRoot as NSString).appendingPathComponent("backend")
        let backendScript = (backendDir as NSString).appendingPathComponent("main.py")

        guard FileManager.default.fileExists(atPath: backendScript) else {
            throw BackendProcessError.backendScriptNotFound(backendScript)
        }

        let venvPython = (backendDir as NSString).appendingPathComponent(".venv/bin/python3")

        // Автосоздание venv если его нет.
        if !FileManager.default.isExecutableFile(atPath: venvPython) {
            try await setupVenv(backendDir: backendDir)
        }

        guard FileManager.default.isExecutableFile(atPath: venvPython) else {
            // Fallback на системный python если venv не удалось создать.
            let python = try resolvePythonExecutable()
            return BackendLaunch(executablePath: python, arguments: [backendScript])
        }

        return BackendLaunch(executablePath: venvPython, arguments: [backendScript])
    }

    // MARK: - Project Root Discovery

    private func resolveProjectRoot() throws -> String {
        // Env var override.
        if let explicit = ProcessInfo.processInfo.environment["AIMC_PROJECT_ROOT"],
           FileManager.default.fileExists(atPath: (explicit as NSString).appendingPathComponent("Package.swift")) {
            return explicit
        }

        // Поиск вверх от исполняемого файла — ищем Package.swift.
        if let executableURL = Bundle.main.executableURL {
            var dir = executableURL.deletingLastPathComponent()
            for _ in 0..<10 {
                let candidate = dir.appendingPathComponent("Package.swift").path
                if FileManager.default.fileExists(atPath: candidate) {
                    return dir.path
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }

        // Поиск вверх от CWD.
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("Package.swift").path
            if FileManager.default.fileExists(atPath: candidate) {
                return dir.path
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        // Последняя попытка: AIMC_BACKEND_PATH.
        if let backendPath = ProcessInfo.processInfo.environment["AIMC_BACKEND_PATH"],
           FileManager.default.fileExists(atPath: backendPath) {
            return ((backendPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        }

        throw BackendProcessError.backendScriptNotFound(
            "Не удалось найти корень проекта (Package.swift). "
            + "Укажите AIMC_PROJECT_ROOT или AIMC_BACKEND_PATH."
        )
    }

    // MARK: - Venv Auto-Setup

    private func setupVenv(backendDir: String) async throws {
        let python = try resolvePythonExecutable()
        let venvPath = (backendDir as NSString).appendingPathComponent(".venv")
        let requirementsPath = ((backendDir as NSString)
            .deletingLastPathComponent as NSString)
            .appendingPathComponent("requirements.txt")

        // python3 -m venv backend/.venv
        let venvProcess = Process()
        venvProcess.executableURL = URL(fileURLWithPath: python)
        venvProcess.arguments = ["-m", "venv", venvPath]
        venvProcess.standardInput = FileHandle.nullDevice
        let venvPipe = Pipe()
        venvProcess.standardOutput = venvPipe
        venvProcess.standardError = venvPipe

        do {
            try venvProcess.run()
            venvProcess.waitUntilExit()
        } catch {
            throw BackendProcessError.venvSetupFailed(error.localizedDescription)
        }

        guard venvProcess.terminationStatus == 0 else {
            let output = Self.readPipeOutput(pipe: venvPipe)
            throw BackendProcessError.venvSetupFailed("venv exit \(venvProcess.terminationStatus): \(output)")
        }

        // pip install -r requirements.txt (если файл есть)
        guard FileManager.default.fileExists(atPath: requirementsPath) else { return }

        let pipPath = (venvPath as NSString).appendingPathComponent("bin/pip")
        let pipProcess = Process()
        pipProcess.executableURL = URL(fileURLWithPath: pipPath)
        pipProcess.arguments = ["install", "-r", requirementsPath]
        pipProcess.standardInput = FileHandle.nullDevice
        let pipPipe = Pipe()
        pipProcess.standardOutput = pipPipe
        pipProcess.standardError = pipPipe

        do {
            try pipProcess.run()
            pipProcess.waitUntilExit()
        } catch {
            throw BackendProcessError.venvSetupFailed("pip: \(error.localizedDescription)")
        }

        if pipProcess.terminationStatus != 0 {
            let output = Self.readPipeOutput(pipe: pipPipe)
            throw BackendProcessError.venvSetupFailed("pip exit \(pipProcess.terminationStatus): \(output)")
        }
    }

    // MARK: - Helpers

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
