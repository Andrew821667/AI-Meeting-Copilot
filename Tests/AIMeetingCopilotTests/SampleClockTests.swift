import XCTest
@testable import AIMeetingCopilotCore

final class SampleClockTests: XCTestCase {
    func testMonotonicBySampleCount() {
        let clock = SampleClock(sessionStartTime: 100)

        let ts1 = clock.advance(frames: 16000, sampleRate: 16000)
        let ts2 = clock.advance(frames: 8000, sampleRate: 16000)

        XCTAssertEqual(ts1, 101, accuracy: 0.0001)
        XCTAssertEqual(ts2, 101.5, accuracy: 0.0001)
        XCTAssertGreaterThan(ts2, ts1)
    }
}
