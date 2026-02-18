import Foundation
import QuartzCore
import CoreMedia

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public enum SystemAudioCaptureError: Error {
    case permissionDenied
    case sourceUnavailable
}

public final class SystemAudioCaptureService: NSObject {
    public var onAudioLevel: ((AudioLevelEvent) -> Void)?
    public var onCaptureModeChanged: ((CaptureMode, String) -> Void)?

    private let seqGenerator: SequenceNumberGenerator
    private var timer: DispatchSourceTimer?
    private let stateQueue = DispatchQueue(label: "ai.meeting.copilot.system-audio.state")
    private let outputQueue = DispatchQueue(label: "ai.meeting.copilot.system-audio.output")
    private var isRunning = false
    private var mode: CaptureMode = .off
    private var startedAt: TimeInterval = 0
    private var lastSystemRms: Float = 0
    private var lastAudioSampleAt: TimeInterval = 0
    private var captureTask: Task<Void, Never>?
    private var lowSignalStreakSec = 0
    private var fallbackActivated = false

#if canImport(ScreenCaptureKit)
    @available(macOS 13.0, *)
    private var screenStream: SCStream?
#endif

    public init(seqGenerator: SequenceNumberGenerator = SequenceNumberGenerator(startAt: 10_000)) {
        self.seqGenerator = seqGenerator
        super.init()
    }

    public func startCapture(mode: CaptureMode, sessionStartTime: TimeInterval) {
        stopCapture()
        self.mode = mode
        self.startedAt = sessionStartTime
        self.lastSystemRms = 0
        self.lastAudioSampleAt = 0
        self.lowSignalStreakSec = 0
        self.fallbackActivated = false
        isRunning = true
        startLevelEmitter()

        if mode == .screenCaptureKit {
            startScreenCaptureKitStream()
        } else if mode == .blackHole {
            updateSystemLevel(0.18)
        }
    }

    public func stopCapture() {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil
        captureTask?.cancel()
        captureTask = nil

#if canImport(ScreenCaptureKit)
        if #available(macOS 13.0, *), let stream = screenStream {
            Task {
                try? await stream.stopCapture()
            }
            screenStream = nil
        }
#endif
        mode = .off
    }

    private func startLevelEmitter() {
        let timer = DispatchSource.makeTimerSource(queue: outputQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            let (systemRms, timestamp) = self.currentSystemLevelAndTimestamp()
            self.handleSilenceWatchdog(systemRms: systemRms)
            let event = AudioLevelEvent(
                seq: self.seqGenerator.next(),
                timestamp: timestamp,
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

    private func currentSystemLevelAndTimestamp() -> (Float, TimeInterval) {
        let ts = CACurrentMediaTime() - startedAt
        if mode == .micOnly || mode == .off {
            return (0, ts)
        }
        if mode == .blackHole {
            return (0.18, ts)
        }

        return stateQueue.sync {
            let freshness = CACurrentMediaTime() - lastAudioSampleAt
            let level: Float = freshness <= 2 ? max(lastSystemRms, 0.02) : 0
            return (level, ts)
        }
    }

    private func updateSystemLevel(_ level: Float) {
        stateQueue.sync {
            lastSystemRms = min(max(level, 0), 1)
            lastAudioSampleAt = CACurrentMediaTime()
        }
    }

    private func handleSilenceWatchdog(systemRms: Float) {
        guard mode == .screenCaptureKit else {
            lowSignalStreakSec = 0
            return
        }

        if systemRms < 0.02 {
            lowSignalStreakSec += 1
        } else {
            lowSignalStreakSec = 0
        }

        guard lowSignalStreakSec >= 10, !fallbackActivated else {
            return
        }

        fallbackActivated = true
        lowSignalStreakSec = 0
        mode = .blackHole
        updateSystemLevel(0.18)
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureModeChanged?(.blackHole, "SCK не дал сигнал 10с, активирован fallback BlackHole")
        }
    }

    private func estimateLevel(sampleBuffer: CMSampleBuffer) -> Float {
        let samples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard samples > 0 else { return 0.01 }
        let normalized = min(Float(samples) / 4096.0, 1.0)
        return max(0.03, normalized * 0.5)
    }

    private func startScreenCaptureKitStream() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }

#if canImport(ScreenCaptureKit)
            guard #available(macOS 13.0, *) else {
                self.updateSystemLevel(0)
                return
            }

            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = shareable.displays.first else {
                    throw SystemAudioCaptureError.sourceUnavailable
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = max(display.width, 2)
                config.height = max(display.height, 2)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
                try await stream.startCapture()

                self.screenStream = stream
                self.updateSystemLevel(0.04)
            } catch {
                self.updateSystemLevel(0)
            }
#else
            self.updateSystemLevel(0)
#endif
        }
    }
}

#if canImport(ScreenCaptureKit)
@available(macOS 13.0, *)
extension SystemAudioCaptureService: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRunning else { return }
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let level = estimateLevel(sampleBuffer: sampleBuffer)
        updateSystemLevel(level)
    }
}
#endif
