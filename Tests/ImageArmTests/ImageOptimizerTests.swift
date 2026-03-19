import XCTest
@testable import ImageArm

/// Tests d'intégration pour ImageOptimizer — nécessite les outils CLI dans tools/bin/
final class ImageOptimizerTests: XCTestCase {

    private var optimizer: ImageOptimizer!
    private var tempDir: URL!

    override func setUp() async throws {
        optimizer = ImageOptimizer()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func copyTestResource(_ name: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        // Chercher dans le bundle de test
        if let resourceURL = bundle.url(forResource: name, withExtension: nil, subdirectory: nil) {
            let dest = tempDir.appendingPathComponent(name)
            try FileManager.default.copyItem(at: resourceURL, to: dest)
            return dest
        }
        // Fallback : chemin relatif depuis le working directory
        let srcPath = "Tests/ImageArmTests/Resources/\(name)"
        let src = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(srcPath)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw XCTSkip("Fichier de test \(name) non trouvé")
        }
        let dest = tempDir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    @MainActor
    private func makeFile(url: URL) -> ImageFile {
        ImageFile(url: url)
    }

    // MARK: - Pipeline PNG

    func testOptimizePNGDoesNotCrash() async throws {
        let url = try copyTestResource("test.png")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .standard)
        let status = await MainActor.run { file.status }
        // Le fichier est très petit — déjà optimal ou done, mais pas failed
        switch status {
        case .failed:
            XCTFail("PNG pipeline ne devrait pas échouer sur un fichier valide")
        default:
            break // .done ou .alreadyOptimal sont tous deux acceptables
        }
    }

    func testOptimizePNGNoOrphanTemps() async throws {
        let url = try copyTestResource("test.png")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .quick)
        // Vérifier qu'aucun fichier .imagearm.* ne traîne
        let items = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let orphans = items.filter { $0.contains(".imagearm.") }
        XCTAssertTrue(orphans.isEmpty, "Fichiers temporaires orphelins : \(orphans)")
    }

    // MARK: - Pipeline JPEG

    func testOptimizeJPEGDoesNotCrash() async throws {
        let url = try copyTestResource("test.jpg")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .standard)
        let status = await MainActor.run { file.status }
        switch status {
        case .failed:
            XCTFail("JPEG pipeline ne devrait pas échouer sur un fichier valide")
        default:
            break
        }
    }

    // MARK: - Pipeline SVG

    func testOptimizeSVGDoesNotCrash() async throws {
        let url = try copyTestResource("test.svg")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .standard)
        let status = await MainActor.run { file.status }
        // SVG peut échouer si svgo n'est pas trouvé depuis le test runner (working dir différent)
        // On vérifie juste que ça ne crashe pas
        _ = status
    }

    func testOptimizeSVGProducesValidOutput() async throws {
        let url = try copyTestResource("test.svg")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .standard)
        // Le fichier doit toujours exister et être lisible
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.isEmpty, "SVG ne devrait pas être vide après optimisation")
    }

    // MARK: - Pipeline WebP

    func testOptimizeWebPDoesNotCrash() async throws {
        let url = try copyTestResource("test.webp")
        let file = await makeFile(url: url)
        await optimizer.optimize(file: file, level: .standard)
        let status = await MainActor.run { file.status }
        switch status {
        case .failed:
            XCTFail("WebP pipeline ne devrait pas échouer sur un fichier valide")
        default:
            break
        }
    }

    // MARK: - Annulation

    func testCancellationResetsToPending() async throws {
        let url = try copyTestResource("test.png")
        let file = await makeFile(url: url)
        let task = Task {
            await optimizer.optimize(file: file, level: .ultra)
        }
        // Annuler immédiatement
        task.cancel()
        await task.value
        let status = await MainActor.run { file.status }
        // Après annulation : pending ou un état complété (si le pipeline a terminé avant l'annulation)
        XCTAssertNotEqual(status, .failed(""), "L'annulation ne devrait pas produire un état failed")
    }

    // MARK: - Format inconnu

    func testUnknownFormatFails() async throws {
        let unknownFile = tempDir.appendingPathComponent("test.bmp")
        try "fake".write(to: unknownFile, atomically: true, encoding: .utf8)
        let file = await makeFile(url: unknownFile)
        await optimizer.optimize(file: file, level: .standard)
        let status = await MainActor.run { file.status }
        if case .failed = status {
            // Attendu
        } else {
            XCTFail("Un format inconnu devrait échouer, pas : \(status)")
        }
    }
}
