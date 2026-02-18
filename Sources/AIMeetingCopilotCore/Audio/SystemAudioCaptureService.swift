import Foundation
import QuartzCore

public enum SystemAudioCaptureError: Error {
    case permissionDenied
}

public final class SystemAudioCaptureService {
    public var onAudioLevel: ((AudioLevelEvent) -> Void)?

    private let seqGenerator: SequenceNumberGenerator
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var mode: CaptureMode = .off
    private var startedAt: TimeInterval = 0

    public init(seqGenerator: SequenceNumberGenerator = SequenceNumberGenerator(startAt: 10_000)) {
        self.seqGenerator = seqGenerator
    }

    public func startCapture(mode: CaptureMode, sessionStartTime: TimeInterval) {
        guard !isRunning else { return }
        self.mode = mode
        self.startedAt = sessionStartTime
        isRunning = true

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            let ts = CACurrentMediaTime() - self.startedAt
            let systemRms: Float = self.mode == .micOnly ? 0 : 0.18
            let event = AudioLevelEvent(
                seq: self.seqGenerator.next(),
                timestamp: ts,
                micRms: 0,
                systemRms: systemRms
            )
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(event)
            }
        }
        self.timer = timer
        timer.resume()
    }

    public func stopCapture() {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil
        mode = .off
    }
}
