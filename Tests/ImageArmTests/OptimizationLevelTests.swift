import XCTest
@testable import ImageArm

final class OptimizationLevelTests: XCTestCase {

    // MARK: - Niveaux

    func testAllCasesCount() {
        XCTAssertEqual(OptimizationLevel.allCases.count, 4)
    }

    func testRawValues() {
        XCTAssertEqual(OptimizationLevel.quick.rawValue, 0)
        XCTAssertEqual(OptimizationLevel.standard.rawValue, 1)
        XCTAssertEqual(OptimizationLevel.high.rawValue, 2)
        XCTAssertEqual(OptimizationLevel.ultra.rawValue, 3)
    }

    // MARK: - PNG settings

    func testPNGLossy() {
        XCTAssertFalse(OptimizationLevel.quick.pngLossy)
        XCTAssertFalse(OptimizationLevel.standard.pngLossy)
        XCTAssertTrue(OptimizationLevel.high.pngLossy)
        XCTAssertTrue(OptimizationLevel.ultra.pngLossy)
    }

    func testOxipngLevel() {
        XCTAssertEqual(OptimizationLevel.quick.oxipngLevel, 2)
        XCTAssertEqual(OptimizationLevel.standard.oxipngLevel, 4)
        XCTAssertEqual(OptimizationLevel.high.oxipngLevel, 6)
        XCTAssertEqual(OptimizationLevel.ultra.oxipngLevel, 6)
    }

    func testUsePngcrush() {
        // Benchmark 2026-03-31: pngcrush retiré (0/50 victoires)
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(level.usePngcrush)
        }
    }

    func testPngcrushBrute() {
        // Benchmark 2026-03-31: pngcrush retiré
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(level.pngcrushBrute)
        }
    }

    func testPNGQuantQualityRange() {
        let ultraRange = OptimizationLevel.ultra.pngQuantQualityRange
        let quickRange = OptimizationLevel.quick.pngQuantQualityRange
        XCTAssertLessThan(ultraRange.max, quickRange.max)
        XCTAssertLessThan(ultraRange.min, quickRange.min)
    }

    // MARK: - JPEG settings

    func testJPEGLossy() {
        XCTAssertFalse(OptimizationLevel.quick.jpegLossy)
        XCTAssertFalse(OptimizationLevel.standard.jpegLossy)
        XCTAssertTrue(OptimizationLevel.high.jpegLossy)
        XCTAssertTrue(OptimizationLevel.ultra.jpegLossy)
    }

    func testJPEGQualityDecreases() {
        XCTAssertGreaterThan(OptimizationLevel.quick.jpegQuality, OptimizationLevel.ultra.jpegQuality)
    }

    func testJPEGProgressive() {
        XCTAssertFalse(OptimizationLevel.quick.jpegProgressive)
        XCTAssertTrue(OptimizationLevel.standard.jpegProgressive)
        XCTAssertTrue(OptimizationLevel.ultra.jpegProgressive)
    }

    // MARK: - HEIF settings

    func testHEIFLossy() {
        XCTAssertFalse(OptimizationLevel.quick.heifLossy)
        XCTAssertFalse(OptimizationLevel.standard.heifLossy)
        XCTAssertTrue(OptimizationLevel.high.heifLossy)
        XCTAssertTrue(OptimizationLevel.ultra.heifLossy)
    }

    func testHEIFQualityDecreases() {
        XCTAssertGreaterThan(OptimizationLevel.quick.heifQuality, OptimizationLevel.ultra.heifQuality)
    }

    // MARK: - WebP settings

    func testWebPLossless() {
        XCTAssertTrue(OptimizationLevel.quick.webpLossless)
        XCTAssertTrue(OptimizationLevel.standard.webpLossless)
        XCTAssertFalse(OptimizationLevel.high.webpLossless)
        XCTAssertFalse(OptimizationLevel.ultra.webpLossless)
    }

    // MARK: - General

    func testStripMetadata() {
        XCTAssertFalse(OptimizationLevel.quick.stripMetadata)
        XCTAssertTrue(OptimizationLevel.standard.stripMetadata)
    }

    func testUseGPU() {
        XCTAssertFalse(OptimizationLevel.quick.useGPU)
        XCTAssertTrue(OptimizationLevel.high.useGPU)
    }

    // MARK: - Loss indicator

    // `lossIndicator` passe par String(localized:) — on teste la structure,
    // pas le texte, sinon le test casse dès que la locale du runner change.
    func testLossIndicator() {
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(level.lossIndicator.isEmpty, "\(level) doit avoir un indicateur")
        }
        // quick et standard sont tous deux sans perte → même libellé
        XCTAssertEqual(OptimizationLevel.quick.lossIndicator, OptimizationLevel.standard.lossIndicator)
        // high et ultra sont avec perte, et se distinguent l'un de l'autre
        XCTAssertNotEqual(OptimizationLevel.high.lossIndicator, OptimizationLevel.quick.lossIndicator)
        XCTAssertNotEqual(OptimizationLevel.ultra.lossIndicator, OptimizationLevel.high.lossIndicator)
    }

    // MARK: - Total steps

    func testTotalStepsPNG() {
        let quickSteps = OptimizationLevel.quick.totalSteps(for: .png)
        let ultraSteps = OptimizationLevel.ultra.totalSteps(for: .png)
        XCTAssertGreaterThan(ultraSteps, quickSteps)
    }

    func testTotalStepsHEIF() {
        let quickSteps = OptimizationLevel.quick.totalSteps(for: .heif)
        let ultraSteps = OptimizationLevel.ultra.totalSteps(for: .heif)
        XCTAssertGreaterThanOrEqual(ultraSteps, quickSteps)
    }

    func testTotalStepsUnknownIsZero() {
        XCTAssertEqual(OptimizationLevel.standard.totalSteps(for: .unknown), 0)
    }
}
