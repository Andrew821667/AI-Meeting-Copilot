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

        let launch = try resolveBackendLaunch()

        let socket = "/tmp/ai-meeting-copilot-\(ProcessInfo.processInfo.processIdentifier).sock"
        if FileManager.default.fileExists(atPath: socket) {
            try? FileManager.default.removeItem(atPath: socket)
        }

        let process = Process()
        let exportsDir = ((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("exports"))
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments + ["--socket", socket, "--exports-dir", exportsDir]

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
                return BackendLaunch(executablePath: "/usr/bin/env", arguments: ["python3", packagedScript])
            }
        }

        // 3) Dev fallback (python script from workspace).
        let backendPath = resolveBackendScriptPath()
        guard FileManager.default.fileExists(atPath: backendPath) else {
            throw BackendProcessError.backendScriptNotFound
        }

        return BackendLaunch(executablePath: "/usr/bin/env", arguments: ["python3", backendPath])
    }

    private func resolveBackendScriptPath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["AIMC_BACKEND_PATH"] {
            return explicit
        }

        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent("backend/main.py")
    }
}
