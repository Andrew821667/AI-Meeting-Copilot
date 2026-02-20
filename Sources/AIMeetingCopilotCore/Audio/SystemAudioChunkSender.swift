import Foundation
import CoreMedia

/// Accumulates system audio CMSampleBuffers into 2-second chunks,
/// base64-encodes the PCM float32 data, and sends them to the backend
/// via UDS for online speaker diarization.
public final class SystemAudioChunkSender: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SystemAudioChunkSender", qos: .utility)
    private let chunkDurationSec: Double = 2.0
    private let sampleRate: Int = 16_000
    private let samplesPerChunk: Int

    private var buffer: [Float] = []
    private var chunkIndex: Int = 0
    private var isRunning = false

    /// Called on the internal queue with base64-encoded PCM and chunk index.
    /// Implementer should forward to UDSEventClient.
    public var onChunkReady: ((_ pcmBase64: String, _ chunkIndex: Int) -> Void)?

    /// Callback when backend returns a speaker label for a chunk.
    public var onSpeakerLabel: ((_ label: String, _ speakerCount: Int) -> Void)?

    public init() {
        samplesPerChunk = Int(chunkDurationSec) * sampleRate
    }

    public func start() {
        queue.sync {
            buffer.removeAll(keepingCapacity: true)
            chunkIndex = 0
            isRunning = true
        }
    }

    public func stop() {
        queue.sync {
            isRunning = false
            // Flush remaining buffer if it has enough data (at least 0.5s)
            if buffer.count >= sampleRate / 2 {
                flushBuffer()
            }
            buffer.removeAll()
        }
    }

    /// Append a CMSampleBuffer from ScreenCaptureKit system audio.
    /// Must be 16 kHz mono float32 (matches ScreenAudioInput config).
    public func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawPtr in
            guard let baseAddr = rawPtr.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddr)
        }

        let floatCount = length / MemoryLayout<Float>.size
        let floats = data.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.baseAddress?.assumingMemoryBound(to: Float.self), count: floatCount))
        }

        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.buffer.append(contentsOf: floats)

            while self.buffer.count >= self.samplesPerChunk {
                self.flushBuffer()
            }
        }
    }

    private func flushBuffer() {
        let chunkSamples = Array(buffer.prefix(samplesPerChunk))
        buffer.removeFirst(min(samplesPerChunk, buffer.count))

        let data = chunkSamples.withUnsafeBytes { Data($0) }
        let base64 = data.base64EncodedString()

        let idx = chunkIndex
        chunkIndex += 1
        onChunkReady?(base64, idx)
    }
}
