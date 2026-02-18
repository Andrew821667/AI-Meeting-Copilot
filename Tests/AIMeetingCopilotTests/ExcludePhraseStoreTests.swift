import XCTest
@testable import AIMeetingCopilotCore

final class ExcludePhraseStoreTests: XCTestCase {
    func testNormalizePhrase() {
        let normalized = ExcludePhraseStore.normalize("  Штраф, Дедлайн!!!  ")
        XCTAssertEqual(normalized, "штраф дедлайн")
    }

    func testAddLoadRemove() {
        let dbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("exclude-\(UUID().uuidString).sqlite3")
        let store = ExcludePhraseStore(dbPath: dbPath)

        XCTAssertTrue(store.add(profileID: "negotiation", phrase: "последнее предложение"))
        XCTAssertEqual(store.load(profileID: "negotiation"), ["последнее предложение"])

        XCTAssertTrue(store.remove(profileID: "negotiation", phrase: "последнее предложение"))
        XCTAssertEqual(store.load(profileID: "negotiation"), [])
    }
}
