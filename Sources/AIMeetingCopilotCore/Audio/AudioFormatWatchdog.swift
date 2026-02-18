import Foundation
import AVFoundation

public final class AudioFormatWatchdog {
    private var expectedSampleRate: Double?
    private var expectedChannels: AVAudioChannelCount?

    public var onFormatChanged: ((AVAudioFormat) -> Void)?

    public init() {}

    public func observe(format: AVAudioFormat) {
        if expectedSampleRate == nil {
            expectedSampleRate = format.sampleRate
            expectedChannels = format.channelCount
            return
        }

        guard let expectedSampleRate, let expectedChannels else { return }
        if format.sampleRate != expectedSampleRate || format.channelCount != expectedChannels {
            self.expectedSampleRate = format.sampleRate
            self.expectedChannels = format.channelCount
            onFormatChanged?(format)
        }
    }
}
