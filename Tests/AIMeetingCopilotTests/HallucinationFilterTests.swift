import XCTest
@testable import AIMeetingCopilotCore

final class HallucinationFilterTests: XCTestCase {
    func testDropsWhenVADGateIsFalse() {
        let filter = HallucinationFilter()
        XCTAssertNil(filter.apply(text: "Любой текст", vadDetectedSpeech: false))
    }

    func testDropsKnownPattern() {
        let filter = HallucinationFilter()
        XCTAssertNil(filter.apply(text: "Thank you for watching", vadDetectedSpeech: true))
    }

    func testPassesNormalSpeech() {
        let filter = HallucinationFilter()
        XCTAssertEqual(filter.apply(text: "Нам нужно согласовать дедлайн", vadDetectedSpeech: true), "Нам нужно согласовать дедлайн")
    }
}
