import XCTest
@testable import TomatoCore

final class TokenMeterTests: XCTestCase {
    func testThousandsSeparator() {
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(0), "0")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(7), "7")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(42), "42")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(999), "999")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(1_000), "1,000")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(1_204), "1,204")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(12_403), "12,403")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(123_456), "123,456")
        XCTAssertEqual(TokenMeter.insertThousandsSeparator(1_234_567), "1,234,567")
    }
}
