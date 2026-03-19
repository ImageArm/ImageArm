import XCTest
@testable import ImageArm

final class FileSizeFormatterTests: XCTestCase {

    func testFormatZero() {
        let result = FileSizeFormatter.format(0)
        XCTAssertFalse(result.isEmpty)
    }

    func testFormatKilobytes() {
        let result = FileSizeFormatter.format(1024)
        XCTAssertTrue(result.contains("K") || result.contains("k"))
    }

    func testFormatMegabytes() {
        let result = FileSizeFormatter.format(1_048_576)
        XCTAssertTrue(result.contains("M"))
    }

    func testFormatSavingsPositive() {
        let result = FileSizeFormatter.formatSavings(5000)
        XCTAssertTrue(result.hasPrefix("-"))
    }

    func testFormatSavingsZero() {
        XCTAssertEqual(FileSizeFormatter.formatSavings(0), "0 B")
    }

    func testFormatSavingsNegative() {
        XCTAssertEqual(FileSizeFormatter.formatSavings(-100), "0 B")
    }
}
