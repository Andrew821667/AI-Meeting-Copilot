import Foundation

public struct HallucinationFilter {
    public var enabled: Bool
    public var patterns: [String]

    public init(
        enabled: Bool = true,
        patterns: [String] = [
            "Thank you for watching",
            "Субтитры",
            "Подпишитесь на канал",
            #"(.)\1{4,}"#,
            #"^\s*$"#
        ]
    ) {
        self.enabled = enabled
        self.patterns = patterns
    }

    public func apply(text: String, vadDetectedSpeech: Bool) -> String? {
        guard enabled else { return text }
        guard vadDetectedSpeech else { return nil }

        for pattern in patterns {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return nil
            }
        }
        return text
    }
}
