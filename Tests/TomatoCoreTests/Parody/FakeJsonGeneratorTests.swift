import XCTest
@testable import TomatoCore

final class FakeJsonGeneratorTests: XCTestCase {
    func testCompletedJsonParsesAndFieldTypes() throws {
        let id = "focus_a1b2c3d4"
        let createdAt = Date(timeIntervalSince1970: 1_719_848_820)
        let json = FakeJsonGenerator.completed(
            id: id,
            createdAt: createdAt,
            durationMs: 1_500_000,
            tokensUsed: 12_403
        )
        let data = try XCTUnwrap(json.data(using: .utf8))
        let raw = try JSONSerialization.jsonObject(with: data)
        let obj = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(obj["id"] as? String, id)
        XCTAssertEqual(obj["object"] as? String, "focus_session")
        XCTAssertEqual(obj["created_at"] as? Int, 1_719_848_820)
        XCTAssertEqual(obj["duration_ms"] as? Int, 1_500_000)
        XCTAssertEqual(obj["tokens_used"] as? Int, 12_403)
        XCTAssertEqual(obj["model"] as? String, "tomato-1.0")
        XCTAssertEqual(obj["status"] as? String, "completed")
    }
}
