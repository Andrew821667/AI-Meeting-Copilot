import Foundation
import AVFoundation
import CoreMedia
import os.log

/// Записывает микрофонное и системное аудио в отдельные WAV-файлы.
/// Потокобезопасен — все операции I/O выполняются на последовательной очереди.
public final class AudioRecorder: @unchecked Sendable {

    private let queue = DispatchQueue(label: "AudioRecorder", qos: .utility)
    private static let log = Logger(subsystem: "ai.meeting.copilot", category: "AudioRecorder")

    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var micPath: URL?
    private var systemPath: URL?

    /// Целевой формат записи: 16kHz mono Float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var micConverter: AVAudioConverter?
    private var isRecording = false

    public init() {}

    // MARK: - Lifecycle

    /// Начать запись. Создаёт два WAV-файла в указанной директории.
    public func startRecording(sessionID: String, exportsDir: URL) {
        queue.sync {
            guard !isRecording else { return }

            let audioDir = exportsDir.appendingPathComponent("audio", isDirectory: true)
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

            let micURL = audioDir.appendingPathComponent("\(sessionID)-mic.wav")
            let sysURL = audioDir.appendingPathComponent("\(sessionID)-system.wav")

            do {
                micFile = try AVAudioFile(forWriting: micURL, settings: targetFormat.settings)
                systemFile = try AVAudioFile(forWriting: sysURL, settings: targetFormat.settings)
                micPath = micURL
                systemPath = sysURL
                micConverter = nil
                isRecording = true
            } catch {
                micFile = nil
                systemFile = nil
                isRecording = false
            }
        }
    }

    /// Остановить запись и вернуть пути к файлам.
    public func stopRecording() -> (micPath: String?, systemPath: String?) {
        queue.sync {
            guard isRecording else { return (nil, nil) }
            isRecording = false

            micFile = nil
            systemFile = nil
            micConverter = nil

            let mic = micPath?.path
            let sys = systemPath?.path
            micPath = nil
            systemPath = nil
            return (mic, sys)
        }
    }

    // MARK: - Mic Audio (AVAudioPCMBuffer)

    /// Записать буфер микрофона. Автоматически конвертирует в 16kHz mono если нужно.
    public func appendMicBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, self.isRecording, let file = self.micFile else { return }

            let sourceFormat = buffer.format

            // Если формат совпадает с целевым — пишем напрямую
            if sourceFormat.sampleRate == self.targetFormat.sampleRate
                && sourceFormat.channelCount == self.targetFormat.channelCount
                && sourceFormat.commonFormat == self.targetFormat.commonFormat
                && sourceFormat.isInterleaved == self.targetFormat.isInterleaved {
                do {
                    try file.write(from: buffer)
                } catch {
                    Self.log.error("mic write failed (passthrough): \(error.localizedDescription)")
                }
                return
            }

            // Создаём конвертер при первом вызове или если формат изменился
            if self.micConverter == nil || self.micConverter?.inputFormat != sourceFormat {
                self.micConverter = AVAudioConverter(from: sourceFormat, to: self.targetFormat)
                if self.micConverter == nil {
                    Self.log.error("mic AVAudioConverter init failed: \(String(describing: sourceFormat)) -> \(String(describing: self.targetFormat))")
                }
            }

            guard let converter = self.micConverter else { return }

            let ratio = self.targetFormat.sampleRate / sourceFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0,
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputFrameCount) else {
                return
            }

            var error: NSError?
            var inputConsumed = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                Self.log.error("mic convert error: \(error.localizedDescription) status=\(status.rawValue)")
                return
            }
            guard outputBuffer.frameLength > 0 else { return }
            do {
                try file.write(from: outputBuffer)
            } catch {
                Self.log.error("mic write failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - System Audio (CMSampleBuffer)

    /// Записать буфер системного аудио из ScreenCaptureKit.
    public func appendSystemSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self, self.isRecording, let file = self.systemFile else { return }

            guard let pcmBuffer = Self.convertCMSampleBufferToPCM(sampleBuffer, targetFormat: self.targetFormat) else {
                return
            }

            do {
                try file.write(from: pcmBuffer)
            } catch {
                Self.log.error("system write failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Conversion Helpers

    private static func convertCMSampleBufferToPCM(
        _ sampleBuffer: CMSampleBuffer,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        guard let avFormat = AVAudioFormat(streamDescription: asbd) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let rawPtr = dataPointer else { return nil }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Копируем данные
        if let floatData = inputBuffer.floatChannelData {
            let bytesPerFrame = Int(avFormat.streamDescription.pointee.mBytesPerFrame)
            let channelCount = Int(avFormat.channelCount)
            if avFormat.isInterleaved {
                // Interleaved → deinterleave to first channel
                let src = UnsafeRawPointer(rawPtr).bindMemory(to: Float.self, capacity: frameCount * channelCount)
                for i in 0..<frameCount {
                    floatData[0][i] = src[i * channelCount]
                }
            } else {
                memcpy(floatData[0], rawPtr, min(totalLength, frameCount * bytesPerFrame))
            }
        }

        // Если формат уже совпадает — возвращаем напрямую
        if avFormat.sampleRate == targetFormat.sampleRate && avFormat.channelCount == targetFormat.channelCount {
            return inputBuffer
        }

        // Конвертация
        guard let converter = AVAudioConverter(from: avFormat, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / avFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var inputConsumed = false
        converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }
}
