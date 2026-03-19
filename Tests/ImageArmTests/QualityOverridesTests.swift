import XCTest
@testable import ImageArm

final class QualityOverridesTests: XCTestCase {

    // MARK: - Default (none)

    func testNoneUsesLevelDefaults() {
        let overrides = QualityOverrides.none
        XCTAssertFalse(overrides.useCustom)
        XCTAssertEqual(overrides.effectiveJPEGLossy(level: .high), true)
        XCTAssertEqual(overrides.effectiveJPEGLossy(level: .quick), false)
    }

    func testNoneJPEGQualityFromLevel() {
        let overrides = QualityOverrides.none
        XCTAssertEqual(overrides.effectiveJPEGQuality(level: .standard), OptimizationLevel.standard.jpegQuality)
    }

    func testNonePNGLossyFromLevel() {
        let overrides = QualityOverrides.none
        XCTAssertEqual(overrides.effectivePNGLossy(level: .ultra), true)
        XCTAssertEqual(overrides.effectivePNGLossy(level: .quick), false)
    }

    // MARK: - Custom overrides

    func testCustomJPEGOverride() {
        let overrides = QualityOverrides(useCustom: true, jpegLossy: true, jpegQuality: 50, pngLossy: false, pngQuality: 80)
        XCTAssertTrue(overrides.effectiveJPEGLossy(level: .quick)) // override ignores level
        XCTAssertEqual(overrides.effectiveJPEGQuality(level: .quick), 50)
    }

    func testCustomPNGOverride() {
        let overrides = QualityOverrides(useCustom: true, jpegLossy: false, jpegQuality: 85, pngLossy: true, pngQuality: 60)
        XCTAssertTrue(overrides.effectivePNGLossy(level: .quick)) // override ignores level
        let range = overrides.effectivePNGQualityRange(level: .quick)
        XCTAssertEqual(range.max, 60)
        XCTAssertEqual(range.min, 40) // max - 20
    }

    func testCustomPNGQualityRangeMinClamped() {
        let overrides = QualityOverrides(useCustom: true, jpegLossy: false, jpegQuality: 85, pngLossy: true, pngQuality: 10)
        let range = overrides.effectivePNGQualityRange(level: .quick)
        XCTAssertEqual(range.min, 0) // max(0, 10 - 20) = 0
    }

    func testNonCustomUsesLevelRange() {
        let overrides = QualityOverrides.none
        let range = overrides.effectivePNGQualityRange(level: .high)
        XCTAssertEqual(range.min, OptimizationLevel.high.pngQuantQualityRange.min)
        XCTAssertEqual(range.max, OptimizationLevel.high.pngQuantQualityRange.max)
    }
}
