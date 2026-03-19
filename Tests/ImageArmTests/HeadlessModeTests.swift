import XCTest
@testable import ImageArm

/// Tests pour le parsing des arguments du mode headless
final class HeadlessModeTests: XCTestCase {

    // MARK: - Parsing des arguments

    func testHeadlessDetection() {
        let args = ["ImageArm", "--headless", "/tmp/test.png"]
        XCTAssertTrue(args.contains("--headless"))
    }

    func testHeadlessFileExtraction() {
        let args = ["ImageArm", "--headless", "/tmp/a.png", "/tmp/b.jpg", "/tmp/c.svg"]
        let files = Array(args.drop(while: { $0 != "--headless" }).dropFirst())
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0], "/tmp/a.png")
        XCTAssertEqual(files[1], "/tmp/b.jpg")
        XCTAssertEqual(files[2], "/tmp/c.svg")
    }

    func testHeadlessNoFiles() {
        let args = ["ImageArm", "--headless"]
        let files = Array(args.drop(while: { $0 != "--headless" }).dropFirst())
        XCTAssertTrue(files.isEmpty)
    }

    func testNonHeadlessMode() {
        let args = ["ImageArm"]
        XCTAssertFalse(args.contains("--headless"))
    }

    func testHeadlessWithMixedArgs() {
        let args = ["ImageArm", "--headless", "image.png", "dossier/"]
        let files = Array(args.drop(while: { $0 != "--headless" }).dropFirst())
        XCTAssertEqual(files, ["image.png", "dossier/"])
    }
}
