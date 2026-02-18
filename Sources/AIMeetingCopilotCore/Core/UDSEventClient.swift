import Foundation
import Network

public enum UDSClientError: Error {
    case connectionFailed
    case disconnected
    case invalidResponse
}

public final class UDSEventClient {
    public var onInsightCard: ((InsightCard) -> Void)?
    public var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "ai.meeting.copilot.uds")
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    public init() {}

    public func connect(path: String) async throws {
        disconnect()

        let endpoint = NWEndpoint.unix(path: path)
        let parameters = NWParameters(tls: nil)
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                    self?.onError?("UDS failed: \(error.localizedDescription)")
                case .cancelled:
                    self?.onError?("UDS cancelled")
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }

        receiveLoop()
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
    }

    public func send<T: Codable>(type: String, payload: T) async throws {
        struct Envelope<P: Codable>: Codable {
            let type: String
            let payload: P
        }

        guard let connection else {
            throw UDSClientError.disconnected
        }

        let data = try JSONEncoder().encode(Envelope(type: type, payload: payload)) + Data("\n".utf8)

        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            })
        }
    }

    private func receiveLoop() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.onError?("UDS receive error: \(error.localizedDescription)")
                return
            }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.drainBufferedLines()
            }

            if isComplete {
                self.onError?("UDS connection completed")
                return
            }

            self.receiveLoop()
        }
    }

    private func drainBufferedLines() {
        while let newlineRange = receiveBuffer.firstRange(of: Data([0x0A])) {
            let line = receiveBuffer[..<newlineRange.lowerBound]
            receiveBuffer.removeSubrange(...newlineRange.lowerBound)

            guard !line.isEmpty else { continue }
            handleIncomingLine(Data(line))
        }
    }

    private func handleIncomingLine(_ line: Data) {
        struct Envelope: Codable {
            let type: String
            let payload: InsightCard
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
            onError?("UDS decode error")
            return
        }

        guard envelope.type == "insight_card" else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onInsightCard?(envelope.payload)
        }
    }
}
