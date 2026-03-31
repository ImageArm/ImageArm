import XCTest
@testable import ImageArm

/// Tests TDD pour la simplification du pipeline d'optimisation.
/// Basé sur les benchmarks comparatifs (2026-03-31) :
/// - PNG : pngcrush 0% victoires → retirer
/// - PNG : GPU Metal 0% victoires, +68% taille → retirer du pipeline PNG
/// - JPEG : GPU Metal 40% victoires → garder
/// - JPEG : jpegtran 60% victoires → garder
final class PipelineSimplificationTests: XCTestCase {

    // =========================================================================
    // MARK: - OptimizationLevel : pngcrush retiré
    // =========================================================================

    func testPngcrushRemovedAtAllLevels() {
        // Benchmark: pngcrush = 0 victoire sur 50 images → retiré
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(level.usePngcrush,
                           "usePngcrush doit être false pour \(level) — pngcrush n'apporte aucun gain (benchmark: 0/50 victoires)")
        }
    }

    func testPngcrushBruteRemovedAtAllLevels() {
        for level in OptimizationLevel.allCases {
            XCTAssertFalse(level.pngcrushBrute,
                           "pngcrushBrute doit être false pour \(level)")
        }
    }

    // =========================================================================
    // MARK: - OptimizationLevel : GPU PNG retiré
    // =========================================================================

    func testGPUNotUsedForPNG() {
        // Benchmark: GPU Metal PNG = 0 victoire, +68% taille → retiré du pipeline PNG
        // Le GPU reste utilisé pour JPEG/HEIF/AVIF, mais pas pour PNG
        // totalSteps pour PNG ne doit plus compter le GPU
        let highSteps = OptimizationLevel.high.totalSteps(for: .png)
        let ultraSteps = OptimizationLevel.ultra.totalSteps(for: .png)

        // Pipeline PNG simplifié high/ultra : pngquant + oxipng = 2 étapes
        XCTAssertEqual(highSteps, 2,
                       "PNG high doit avoir 2 étapes (pngquant + oxipng), pas de GPU ni pngcrush")
        XCTAssertEqual(ultraSteps, 2,
                       "PNG ultra doit avoir 2 étapes (pngquant + oxipng), pas de GPU ni pngcrush")
    }

    func testPNGStepsQuickAndStandard() {
        // Quick/Standard : oxipng seul (lossless, pas de pngquant)
        let quickSteps = OptimizationLevel.quick.totalSteps(for: .png)
        let standardSteps = OptimizationLevel.standard.totalSteps(for: .png)

        XCTAssertEqual(quickSteps, 1, "PNG quick doit avoir 1 étape (oxipng seul)")
        XCTAssertEqual(standardSteps, 1, "PNG standard doit avoir 1 étape (oxipng seul)")
    }

    // =========================================================================
    // MARK: - OptimizationLevel : JPEG GPU conservé
    // =========================================================================

    func testGPUStillUsedForJPEG() {
        // Benchmark: GPU JPEG = 40% victoires → garder
        let highSteps = OptimizationLevel.high.totalSteps(for: .jpeg)
        let ultraSteps = OptimizationLevel.ultra.totalSteps(for: .jpeg)

        // Pipeline JPEG high/ultra : GPU + jpegtran = 2 étapes
        XCTAssertEqual(highSteps, 2,
                       "JPEG high doit avoir 2 étapes (GPU + jpegtran)")
        XCTAssertEqual(ultraSteps, 2,
                       "JPEG ultra doit avoir 2 étapes (GPU + jpegtran)")
    }

    func testGPUStillUsedForHEIF() {
        // HEIF/AVIF : GPU natif seul, pas impacté par les changements PNG
        let highSteps = OptimizationLevel.high.totalSteps(for: .heif)
        XCTAssertGreaterThanOrEqual(highSteps, 1,
                                     "HEIF doit toujours utiliser le GPU")
    }

    func testGPUStillUsedForAVIF() {
        let highSteps = OptimizationLevel.high.totalSteps(for: .avif)
        XCTAssertGreaterThanOrEqual(highSteps, 1,
                                     "AVIF doit toujours utiliser le GPU")
    }

    // =========================================================================
    // MARK: - ToolManager : pngcrush retiré de la liste
    // =========================================================================

    func testToolManagerDoesNotListPngcrush() {
        // pngcrush ne doit plus apparaître dans les outils supportés
        let tm = ToolManager()
        let toolNames = tm.allTools().map(\.name)
        XCTAssertFalse(toolNames.contains("pngcrush"),
                       "pngcrush ne doit plus être dans la liste des outils — benchmark: 0/50 victoires")
    }
}
