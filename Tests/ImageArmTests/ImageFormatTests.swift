import XCTest
@testable import ImageArm

final class ImageFormatTests: XCTestCase {

    // MARK: - Détection de format

    func testDetectPNG() {
        let url = URL(fileURLWithPath: "/tmp/test.png")
        XCTAssertEqual(ImageFormat.detect(from: url), .png)
    }

    func testDetectJPEG() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/photo.jpg")), .jpeg)
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/photo.jpeg")), .jpeg)
    }

    func testDetectHEIF() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/photo.heic")), .heif)
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/photo.heif")), .heif)
    }

    func testDetectSVG() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/icon.svg")), .svg)
    }

    func testDetectWebP() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/image.webp")), .webp)
    }

    func testDetectUnknown() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/doc.pdf")), .unknown)
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/file.txt")), .unknown)
    }

    func testDetectCaseInsensitive() {
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/IMAGE.PNG")), .png)
        XCTAssertEqual(ImageFormat.detect(from: URL(fileURLWithPath: "/tmp/PHOTO.HEIC")), .heif)
    }

    // MARK: - Display name

    func testDisplayName() {
        XCTAssertEqual(ImageFormat.png.displayName, "PNG")
        XCTAssertEqual(ImageFormat.jpeg.displayName, "JPEG")
        XCTAssertEqual(ImageFormat.heif.displayName, "HEIF")
        XCTAssertEqual(ImageFormat.svg.displayName, "SVG")
        XCTAssertEqual(ImageFormat.webp.displayName, "WEBP")
    }

    // MARK: - Badge color

    func testBadgeColorExists() {
        for format in ImageFormat.allCases {
            _ = format.badgeColor // ne doit pas crasher
        }
    }
}
