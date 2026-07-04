import Foundation

public struct ProfileRuntimeSettings: Codable, Equatable, Sendable {
    public var threshold: Double
    public var cooldownSec: Double
    public var maxCardsPer10Min: Int
    public var minPauseSec: Double
    public var minContextMin: Int
    public var forceAnswerMode: Bool
    public var micAudioPath: String?
    public var systemAudioPath: String?
    public var meetingSubMode: String?
    public var llmProvider: String?
    public var deepseekModel: String?
    public var orchestratorAgentEnabled: Bool
    public var psychologistAgentEnabled: Bool

    public init(
        threshold: Double,
        cooldownSec: Double,
        maxCardsPer10Min: Int,
        minPauseSec: Double,
        minContextMin: Int,
        forceAnswerMode: Bool = false,
        micAudioPath: String? = nil,
        systemAudioPath: String? = nil,
        meetingSubMode: String? = nil,
        llmProvider: String? = nil,
        deepseekModel: String? = nil,
        orchestratorAgentEnabled: Bool = true,
        psychologistAgentEnabled: Bool = false
    ) {
        self.threshold = threshold
        self.cooldownSec = cooldownSec
        self.maxCardsPer10Min = maxCardsPer10Min
        self.minPauseSec = minPauseSec
        self.minContextMin = minContextMin
        self.forceAnswerMode = forceAnswerMode
        self.micAudioPath = micAudioPath
        self.systemAudioPath = systemAudioPath
        self.meetingSubMode = meetingSubMode
        self.llmProvider = llmProvider
        self.deepseekModel = deepseekModel
        self.orchestratorAgentEnabled = orchestratorAgentEnabled
        self.psychologistAgentEnabled = psychologistAgentEnabled
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case cooldownSec = "cooldown_sec"
        case maxCardsPer10Min = "max_cards_per_10min"
        case minPauseSec = "min_pause_sec"
        case minContextMin = "min_context_min"
        case forceAnswerMode = "force_answer_mode"
        case micAudioPath = "mic_audio_path"
        case systemAudioPath = "system_audio_path"
        case meetingSubMode = "meeting_sub_mode"
        case llmProvider = "llm_provider"
        case deepseekModel = "deepseek_model"
        case orchestratorAgentEnabled = "orchestrator_agent_enabled"
        case psychologistAgentEnabled = "psychologist_agent_enabled"
    }

    // Кастомный decode: старые сохранённые настройки не содержат новых полей.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decode(Double.self, forKey: .threshold)
        cooldownSec = try c.decode(Double.self, forKey: .cooldownSec)
        maxCardsPer10Min = try c.decode(Int.self, forKey: .maxCardsPer10Min)
        minPauseSec = try c.decode(Double.self, forKey: .minPauseSec)
        minContextMin = try c.decode(Int.self, forKey: .minContextMin)
        forceAnswerMode = try c.decodeIfPresent(Bool.self, forKey: .forceAnswerMode) ?? false
        micAudioPath = try c.decodeIfPresent(String.self, forKey: .micAudioPath)
        systemAudioPath = try c.decodeIfPresent(String.self, forKey: .systemAudioPath)
        meetingSubMode = try c.decodeIfPresent(String.self, forKey: .meetingSubMode)
        llmProvider = try c.decodeIfPresent(String.self, forKey: .llmProvider)
        deepseekModel = try c.decodeIfPresent(String.self, forKey: .deepseekModel)
        orchestratorAgentEnabled = try c.decodeIfPresent(Bool.self, forKey: .orchestratorAgentEnabled) ?? true
        psychologistAgentEnabled = try c.decodeIfPresent(Bool.self, forKey: .psychologistAgentEnabled) ?? false
    }

    public static func defaults(for profileID: String) -> ProfileRuntimeSettings {
        switch profileID {
        case "negotiation":
            return .init(threshold: 0.60, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 2)
        case "interview_candidate":
            return .init(threshold: 0.70, cooldownSec: 90, maxCardsPer10Min: 3, minPauseSec: 1.5, minContextMin: 0)
        case "interview_interviewer":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 1)
        case "consulting":
            return .init(threshold: 0.70, cooldownSec: 90, maxCardsPer10Min: 3, minPauseSec: 1.5, minContextMin: 1)
        case "sales":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 1)
        case "tech_sync":
            return .init(threshold: 0.65, cooldownSec: 90, maxCardsPer10Min: 5, minPauseSec: 1.5, minContextMin: 1)
        default:
            return .init(threshold: 0.60, cooldownSec: 90, maxCardsPer10Min: 4, minPauseSec: 1.5, minContextMin: 2)
        }
    }
}
