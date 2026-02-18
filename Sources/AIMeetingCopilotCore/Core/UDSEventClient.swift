import Foundation
import Network

public enum UDSClientError: Error {
    case connectionFailed
    case disconnected
}

private struct UDSOutboundEnvelope<P: Codable>: Codable {
    let type: String
    let payload: P
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func runOnce(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        body()
    }
}

public final class UDSEventClient: @unchecked Sendable {
    public var onInsightCard: ((InsightCard) -> Void)?
    public var onSessionSummary: ((SessionSummary) -> Void)?
    public var onSessionAck: ((String) -> Void)?
    public var onRuntimeWarning: ((String) -> Void)?
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    gate.runOnce {
                        continuation.resume()
                    }
                case .failed(let error):
                    gate.runOnce {
                        continuation.resume(throwing: error)
                    }
                    self?.onError?("Ошибка UDS-соединения: \(error.localizedDescription)")
                case .cancelled:
                    self?.onError?("UDS-соединение закрыто")
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

    public func send<T: Codable & Sendable>(type: String, payload: T) async throws {
        guard let connection else {
            throw UDSClientError.disconnected
        }

        let envelope = UDSOutboundEnvelope(type: type, payload: payload)
        let data = try JSONEncoder().encode(envelope) + Data("\n".utf8)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
                self.onError?("Ошибка чтения UDS: \(error.localizedDescription)")
                return
            }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.drainBufferedLines()
            }

            if isComplete {
                self.onError?("UDS-соединение завершено")
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
        struct Header: Decodable {
            let type: String
        }

        guard let header = try? JSONDecoder().decode(Header.self, from: line) else {
            onError?("Ошибка декодирования сообщения UDS")
            return
        }

        switch header.type {
        case "insight_card":
            struct Envelope: Decodable {
                let type: String
                let payload: InsightCard
            }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
                onError?("Ошибка декодирования карточки")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onInsightCard?(envelope.payload)
            }

        case "session_summary":
            struct Envelope: Decodable {
                let type: String
                let payload: SessionSummary
            }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
                onError?("Ошибка декодирования сводки сессии")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onSessionSummary?(envelope.payload)
            }

        case "session_ack":
            struct AckPayload: Decodable { let event: String }
            struct Envelope: Decodable {
                let type: String
                let payload: AckPayload
            }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
                onError?("Ошибка декодирования подтверждения сессии")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onSessionAck?(envelope.payload.event)
            }

        case "runtime_warning":
            struct WarningPayload: Decodable { let message: String }
            struct Envelope: Decodable {
                let type: String
                let payload: WarningPayload
            }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
                onError?("Ошибка декодирования runtime warning")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onRuntimeWarning?(envelope.payload.message)
            }

        default:
            break
        }
    }
}
