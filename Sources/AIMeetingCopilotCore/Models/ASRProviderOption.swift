import Foundation

public struct ASRProviderOption: Identifiable, Hashable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let whisperKit = ASRProviderOption(
        id: "whisperkit",
        title: "WhisperKit (по умолчанию)"
    )
    public static let qwen3ASR = ASRProviderOption(
        id: "qwen3_asr",
        title: "Qwen3-ASR (экспериментально)"
    )

    public static let all: [ASRProviderOption] = [
        .whisperKit,
        .qwen3ASR,
    ]

    public static func title(for id: String) -> String {
        all.first(where: { $0.id == id })?.title ?? id
    }
}
