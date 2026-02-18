import Foundation

public enum BackendProcessError: Error {
    case backendScriptNotFound
    case processFailedToStart
    case socketNotReady(String)
}

public actor BackendProcessManager {
    private var process: Process?
    private var socketPath: String?

    public init() {}

    public func start() async throws -> String {
        if let socketPath {
            return socketPath
        }

        let backendPath = resolveBackendScriptPath()
        guard FileManager.default.fileExists(atPath: backendPath) else {
            throw BackendProcessError.backendScriptNotFound
        }

        let socket = "/tmp/ai-meeting-copilot-\(ProcessInfo.processInfo.processIdentifier).sock"
        if FileManager.default.fileExists(atPath: socket) {
            try? FileManager.default.removeItem(atPath: socket)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let exportsDir = ((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("exports"))
        process.arguments = ["python3", backendPath, "--socket", socket, "--exports-dir", exportsDir]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw BackendProcessError.processFailedToStart
        }

        self.process = process
        self.socketPath = socket

        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socket) {
                return socket
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw BackendProcessError.socketNotReady(socket)
    }

    public func stop() {
        process?.terminate()
        process = nil

        if let socketPath {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        socketPath = nil
    }

    private func resolveBackendScriptPath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_BACKEND_PATH"] {
            return explicit
        }

        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent("backend/main.py")
    }
}
