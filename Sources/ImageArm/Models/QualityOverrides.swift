import Foundation

struct QualityOverrides: Sendable {
    let useCustom: Bool
    let jpegLossy: Bool
    let jpegQuality: Int
    let pngLossy: Bool
    let pngQuality: Int

    static let none = QualityOverrides(useCustom: false, jpegLossy: false, jpegQuality: 85, pngLossy: false, pngQuality: 80)

    /// Returns effective JPEG lossy setting (override or level default)
    func effectiveJPEGLossy(level: OptimizationLevel) -> Bool {
        useCustom ? jpegLossy : level.jpegLossy
    }

    func effectiveJPEGQuality(level: OptimizationLevel) -> Int {
        useCustom ? jpegQuality : level.jpegQuality
    }

    func effectivePNGLossy(level: OptimizationLevel) -> Bool {
        useCustom ? pngLossy : level.pngLossy
    }

    func effectivePNGQualityRange(level: OptimizationLevel) -> (min: Int, max: Int) {
        if useCustom {
            let maxQ = pngQuality
            let minQ = max(0, maxQ - 20)
            return (minQ, maxQ)
        }
        return level.pngQuantQualityRange
    }
}
