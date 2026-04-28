import Foundation

public struct ASRProviderOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let whisperKit = ASRProviderOption(
        id: "whisperkit",
        title: "Локальная речь (по умолчанию)"
    )
    public static let qwen3ASR = ASRProviderOption(
        id: "qwen3_asr",
        title: "Qwen3-ASR (демо)"
    )

    // Qwen3-ASR пока не реализован — это MockASRProvider с захардкоженными
    // фразами. В UI его не показываем, чтобы пользователь не наткнулся на
    // подменённый транскрипт. Сама опция (и id) сохраняются: Factory всё ещё
    // умеет её разрешать, и старые сохранённые селекшены не ломаются.
    public static let all: [ASRProviderOption] = [
        .whisperKit,
    ]

    public static let allIncludingHidden: [ASRProviderOption] = [
        .whisperKit,
        .qwen3ASR,
    ]

    public static func title(for id: String) -> String {
        allIncludingHidden.first(where: { $0.id == id })?.title ?? id
    }
}
