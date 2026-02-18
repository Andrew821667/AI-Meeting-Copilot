import Foundation

public enum CaptureMode: String, Codable, CaseIterable {
    case off = "CAPTURE OFF"
    case screenCaptureKit = "CAPTURE ON (SCK)"
    case blackHole = "CAPTURE ON (BlackHole)"
    case micOnly = "CAPTURE MIC"
}

public enum MicEventType: String, Codable {
    case speechStart = "speech_start"
    case speechEnd = "speech_end"
    case speechState = "speech_state"
}

public struct MicEvent: Codable {
    public let schemaVersion: Int
    public let seq: UInt64
    public let eventType: MicEventType
    public let timestamp: Double
    public let confidence: Float
    public let duration: Double

    public init(
        schemaVersion: Int = 1,
        seq: UInt64,
        eventType: MicEventType,
        timestamp: Double,
        confidence: Float,
        duration: Double = 0
    ) {
        self.schemaVersion = schemaVersion
        self.seq = seq
        self.eventType = eventType
        self.timestamp = timestamp
        self.confidence = confidence
        self.duration = duration
    }
}

public struct TranscriptSegment: Codable, Identifiable {
    public var id: String { utteranceId + (isFinal ? ":final" : ":partial") }

    public let schemaVersion: Int
    public let seq: UInt64
    public let utteranceId: String
    public let isFinal: Bool
    public let speaker: String
    public let text: String
    public let tsStart: Double
    public let tsEnd: Double
    public let speakerConfidence: Float

    public init(
        schemaVersion: Int = 1,
        seq: UInt64,
        utteranceId: String,
        isFinal: Bool,
        speaker: String,
        text: String,
        tsStart: Double,
        tsEnd: Double,
        speakerConfidence: Float
    ) {
        self.schemaVersion = schemaVersion
        self.seq = seq
        self.utteranceId = utteranceId
        self.isFinal = isFinal
        self.speaker = speaker
        self.text = text
        self.tsStart = tsStart
        self.tsEnd = tsEnd
        self.speakerConfidence = speakerConfidence
    }
}

public struct SystemStateEvent: Codable {
    public let schemaVersion: Int
    public let seq: UInt64
    public let timestamp: Double
    public let batteryLevel: Float
    public let thermalState: String

    public init(
        schemaVersion: Int = 1,
        seq: UInt64,
        timestamp: Double,
        batteryLevel: Float,
        thermalState: String
    ) {
        self.schemaVersion = schemaVersion
        self.seq = seq
        self.timestamp = timestamp
        self.batteryLevel = batteryLevel
        self.thermalState = thermalState
    }
}

public struct AudioLevelEvent: Codable {
    public let schemaVersion: Int
    public let seq: UInt64
    public let timestamp: Double
    public let micRms: Float
    public let systemRms: Float

    public init(
        schemaVersion: Int = 1,
        seq: UInt64,
        timestamp: Double,
        micRms: Float,
        systemRms: Float
    ) {
        self.schemaVersion = schemaVersion
        self.seq = seq
        self.timestamp = timestamp
        self.micRms = micRms
        self.systemRms = systemRms
    }
}
