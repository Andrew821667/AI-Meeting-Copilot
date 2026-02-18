import XCTest
@testable import AIMeetingCopilotCore

@MainActor
final class ASRProviderFactoryTests: XCTestCase {
    func testFactoryReturnsWhisperByDefault() {
        let provider = ASRProviderFactory.make(optionID: "unknown")
        XCTAssertTrue(provider is WhisperKitProvider)
    }

    func testFactoryReturnsQwenProvider() {
        let provider = ASRProviderFactory.make(optionID: ASRProviderOption.qwen3ASR.id)
        XCTAssertTrue(provider is Qwen3ASRProvider)
    }
}
