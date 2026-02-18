import Foundation

@MainActor
public enum ASRProviderFactory {
    public static func make(optionID: String) -> ASRProvider {
        switch optionID {
        case ASRProviderOption.qwen3ASR.id:
            return Qwen3ASRProvider()
        case ASRProviderOption.whisperKit.id:
            return WhisperKitProvider()
        default:
            return WhisperKitProvider()
        }
    }
}
