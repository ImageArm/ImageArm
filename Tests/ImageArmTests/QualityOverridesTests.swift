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
        let overrides = QualityOverrides(useCustom: true, jpegLossy: true, jpegQuality: 50, pngLossy: false, pngQuality: 80, preserveTimestamps: true, preserveMetadata: true)
        XCTAssertTrue(overrides.effectiveJPEGLossy(level: .quick)) // override ignores level
        XCTAssertEqual(overrides.effectiveJPEGQuality(level: .quick), 50)
    }

    func testCustomPNGOverride() {
        let overrides = QualityOverrides(useCustom: true, jpegLossy: false, jpegQuality: 85, pngLossy: true, pngQuality: 60, preserveTimestamps: true, preserveMetadata: true)
        XCTAssertTrue(overrides.effectivePNGLossy(level: .quick)) // override ignores level
        let range = overrides.effectivePNGQualityRange(level: .quick)
        XCTAssertEqual(range.max, 60)
        XCTAssertEqual(range.min, 40) // max - 20
    }

    func testCustomPNGQualityRangeMinClamped() {
        let overrides = QualityOverrides(useCustom: true, jpegLossy: false, jpegQuality: 85, pngLossy: true, pngQuality: 10, preserveTimestamps: true, preserveMetadata: true)
        let range = overrides.effectivePNGQualityRange(level: .quick)
        XCTAssertEqual(range.min, 0) // max(0, 10 - 20) = 0
    }

    func testNonCustomUsesLevelRange() {
        let overrides = QualityOverrides.none
        let range = overrides.effectivePNGQualityRange(level: .high)
        XCTAssertEqual(range.min, OptimizationLevel.high.pngQuantQualityRange.min)
        XCTAssertEqual(range.max, OptimizationLevel.high.pngQuantQualityRange.max)
    }

    // MARK: - Métadonnées (preserveMetadata)

    func testPreserveMetadataNeverStripsWhateverTheLevel() {
        let overrides = QualityOverrides(useCustom: false, jpegLossy: false, jpegQuality: 85, pngLossy: false, pngQuality: 80, preserveTimestamps: true, preserveMetadata: true)
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(overrides.effectiveStripMetadata(level: level), "\(level) ne doit pas stripper quand preserveMetadata = true")
        }
    }

    func testNoPreserveMetadataFollowsLevel() {
        let overrides = QualityOverrides(useCustom: false, jpegLossy: false, jpegQuality: 85, pngLossy: false, pngQuality: 80, preserveTimestamps: true, preserveMetadata: false)
        XCTAssertFalse(overrides.effectiveStripMetadata(level: .quick)) // quick ne strippe jamais
        XCTAssertTrue(overrides.effectiveStripMetadata(level: .standard))
        XCTAssertTrue(overrides.effectiveStripMetadata(level: .high))
        XCTAssertTrue(overrides.effectiveStripMetadata(level: .ultra))
    }

    func testNoneDefaultsToPreservingMetadata() {
        XCTAssertTrue(QualityOverrides.none.preserveMetadata)
        XCTAssertTrue(QualityOverrides.none.preserveTimestamps)
        XCTAssertFalse(QualityOverrides.none.effectiveStripMetadata(level: .ultra))
    }
}
