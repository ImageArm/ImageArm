import XCTest
@testable import ImageArm

/// Benchmark GPU Metal vs outils CLI pour PNG.
/// Compare les tailles de sortie du GPU quantizer avec pngquant, oxipng, pngcrush
/// en utilisant le même corpus de benchmark (Tests/fixtures/benchmark/).
///
/// Lit le CSV produit par tool-comparison.sh pour comparer les résultats.
/// Si le CSV n'existe pas, benchmark uniquement le GPU et produit un rapport standalone.
final class GPUBenchmarkTests: XCTestCase {

    private var gpu: GPUProcessor!
    private var corpusDir: URL!
    private var csvURL: URL!

    override func setUpWithError() throws {
        guard let g = GPUProcessor.shared else {
            throw XCTSkip("Metal GPU non disponible sur cette machine")
        }
        gpu = g

        // Localiser le corpus — chercher depuis le source file ou via env
        let candidates = [
            // #filePath remonte depuis Tests/ImageArmTests/
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tests/fixtures/benchmark"),
            // Variable d'env PROJECT_DIR (set par Xcode)
            ProcessInfo.processInfo.environment["PROJECT_DIR"]
                .map { URL(fileURLWithPath: $0).appendingPathComponent("Tests/fixtures/benchmark") },
            // Chemin absolu en fallback
            URL(fileURLWithPath: "/Users/julien/mobile/armimage/Tests/fixtures/benchmark"),
        ].compactMap { $0 }

        corpusDir = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        guard corpusDir != nil else {
            throw XCTSkip("Corpus de benchmark introuvable dans : \(candidates.map(\.path))")
        }
        csvURL = corpusDir.appendingPathComponent("tool-comparison-results.csv")
    }

    // MARK: - Benchmark GPU PNG quantization sur tout le corpus

    func testGPUBenchmarkPNG() throws {
        let pngFiles = try FileManager.default.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" && $0.lastPathComponent.hasPrefix("bench-png-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertGreaterThan(pngFiles.count, 0, "Aucun PNG dans le corpus")

        // Charger les résultats CLI si disponibles
        let cliResults = loadCLIResults()

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("gpu-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var results: [GPUResult] = []
        var gpuWins = 0
        var pngquantWins = 0
        var oxipngWins = 0
        var ties = 0

        print("\n═══ GPU Metal Benchmark — \(pngFiles.count) PNG ═══\n")
        print("  Fichier                    Original   GPU q65   GPU q80  pngquant  Gagnant")
        print("  " + String(repeating: "─", count: 90))

        for png in pngFiles {
            let fname = png.lastPathComponent
            let origSize = fileSize(png)

            // GPU quantize à qualité 65
            let gpuOut65 = tmpDir.appendingPathComponent("\(fname).gpu65.png")
            var gpuSize65: Int64 = origSize
            do {
                try gpu.quantizePNG(inputPath: png.path, outputPath: gpuOut65.path, quality: 65)
                gpuSize65 = fileSize(gpuOut65)
            } catch {
                // GPU échoue silencieusement sur certaines images
            }

            // GPU quantize à qualité 80
            let gpuOut80 = tmpDir.appendingPathComponent("\(fname).gpu80.png")
            var gpuSize80: Int64 = origSize
            do {
                try gpu.quantizePNG(inputPath: png.path, outputPath: gpuOut80.path, quality: 80)
                gpuSize80 = fileSize(gpuOut80)
            } catch {}

            let bestGPU = min(gpuSize65, gpuSize80)
            let bestGPULabel = gpuSize65 <= gpuSize80 ? "q65" : "q80"

            // Comparer avec les résultats CLI
            let cli = cliResults[fname]
            let pqSize = cli?.pngquantSize ?? origSize
            let oxiSize = cli?.bestOxipngSize ?? origSize

            // Déterminer le gagnant global
            let allResults: [(String, Int64)] = [
                ("GPU \(bestGPULabel)", bestGPU),
                ("pngquant", pqSize),
                ("oxipng", oxiSize),
            ]
            let winner = allResults.min(by: { $0.1 < $1.1 })!

            if winner.0.hasPrefix("GPU") { gpuWins += 1 }
            else if winner.0 == "pngquant" { pngquantWins += 1 }
            else { oxipngWins += 1 }

            // Vérifier si GPU et pngquant sont proches (< 2%)
            if bestGPU > 0 && pqSize > 0 {
                let diff = abs(Int64(bestGPU) - Int64(pqSize))
                if Double(diff) / Double(origSize) < 0.02 { ties += 1 }
            }

            results.append(GPUResult(
                file: fname,
                originalSize: origSize,
                gpuSize65: gpuSize65,
                gpuSize80: gpuSize80,
                pngquantSize: pqSize,
                oxipngSize: oxiSize,
                winner: winner.0
            ))

            let pad = fname.padding(toLength: 25, withPad: " ", startingAt: 0)
            print("  \(pad) \(origSize) \(gpuSize65) \(gpuSize80) \(pqSize)  🏆 \(winner.0)")
        }

        // Rapport
        print("\n═══ RÉSUMÉ GPU vs CLI ═══\n")
        print("  GPU Metal gagne    : \(gpuWins)/\(pngFiles.count) (\(pct(gpuWins, pngFiles.count))%)")
        print("  pngquant gagne     : \(pngquantWins)/\(pngFiles.count) (\(pct(pngquantWins, pngFiles.count))%)")
        print("  oxipng gagne       : \(oxipngWins)/\(pngFiles.count) (\(pct(oxipngWins, pngFiles.count))%)")
        print("  GPU ≈ pngquant (<2%): \(ties)/\(pngFiles.count)")
        print("")

        // Économies totales
        let totalOrig = results.reduce(Int64(0)) { $0 + $1.originalSize }
        let totalGPU = results.reduce(Int64(0)) { $0 + min($1.gpuSize65, $1.gpuSize80) }
        let totalPQ = results.reduce(Int64(0)) { $0 + $1.pngquantSize }
        let totalOxi = results.reduce(Int64(0)) { $0 + $1.oxipngSize }

        print("  Économie totale GPU     : \(formatKB(totalOrig - totalGPU)) Ko (\(pctSaving(totalGPU, totalOrig))%)")
        print("  Économie totale pngquant: \(formatKB(totalOrig - totalPQ)) Ko (\(pctSaving(totalPQ, totalOrig))%)")
        print("  Économie totale oxipng  : \(formatKB(totalOrig - totalOxi)) Ko (\(pctSaving(totalOxi, totalOrig))%)")

        print("\n═══ RECOMMANDATION ═══\n")
        if gpuWins > pngquantWins && gpuWins > oxipngWins {
            print("  GPU Metal est le meilleur outil lossy PNG.")
            print("  Pipeline recommandé : GPU → oxipng (lossless polish) → keepBest()")
        } else if gpuWins == 0 {
            print("  GPU Metal ne gagne jamais — envisager de le retirer du pipeline PNG lossy.")
        } else {
            print("  GPU et pngquant se partagent les victoires.")
            print("  Pipeline recommandé : GPU + pngquant → oxipng → keepBest()")
        }

        // Sauvegarder le rapport
        let reportURL = corpusDir.appendingPathComponent("gpu-benchmark-results.txt")
        let reportLines = results.map { r in
            "\(r.file),\(r.originalSize),\(r.gpuSize65),\(r.gpuSize80),\(r.pngquantSize),\(r.oxipngSize),\(r.winner)"
        }
        let header = "file,original,gpu_q65,gpu_q80,pngquant,oxipng,winner"
        let csv = ([header] + reportLines).joined(separator: "\n")
        try csv.write(to: reportURL, atomically: true, encoding: .utf8)
        print("\n  Résultats CSV : \(reportURL.path)")
    }

    // MARK: - Benchmark GPU JPEG sur tout le corpus

    func testGPUBenchmarkJPEG() throws {
        let jpegFiles = try FileManager.default.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" && $0.lastPathComponent.hasPrefix("bench-jpeg-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertGreaterThan(jpegFiles.count, 0, "Aucun JPEG dans le corpus")

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("gpu-jpeg-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Charger résultats CLI JPEG si disponibles
        let cliJPEG = loadJPEGCLIResults()

        var gpuWins = 0
        var jpegtranWins = 0
        var cjpegWins = 0

        print("\n═══ GPU Metal JPEG Benchmark — \(jpegFiles.count) JPEG ═══\n")
        print("  Fichier                    Original  GPU q85   GPU q75   GPU q65  jpegtran  cjpeg85   Gagnant")
        print("  " + String(repeating: "─", count: 100))

        struct JPEGResult {
            let file: String
            let origSize: Int64
            let gpuQ85: Int64
            let gpuQ75: Int64
            let gpuQ65: Int64
            let jpegtranSize: Int64
            let cjpegQ85: Int64
            let winner: String
        }
        var results: [JPEGResult] = []

        for jpg in jpegFiles {
            let fname = jpg.lastPathComponent
            let origSize = fileSize(jpg)

            // GPU encode qualité 85
            let gpuOut85 = tmpDir.appendingPathComponent("\(fname).gpu85.jpg")
            var gpuSize85: Int64 = origSize
            do {
                try gpu.encodeJPEGHardware(inputPath: jpg.path, outputPath: gpuOut85.path, quality: 85, stripMetadata: true)
                gpuSize85 = fileSize(gpuOut85)
            } catch {}

            // GPU encode qualité 75
            let gpuOut75 = tmpDir.appendingPathComponent("\(fname).gpu75.jpg")
            var gpuSize75: Int64 = origSize
            do {
                try gpu.encodeJPEGHardware(inputPath: jpg.path, outputPath: gpuOut75.path, quality: 75, stripMetadata: true)
                gpuSize75 = fileSize(gpuOut75)
            } catch {}

            // GPU encode qualité 65
            let gpuOut65 = tmpDir.appendingPathComponent("\(fname).gpu65.jpg")
            var gpuSize65: Int64 = origSize
            do {
                try gpu.encodeJPEGHardware(inputPath: jpg.path, outputPath: gpuOut65.path, quality: 65, stripMetadata: true)
                gpuSize65 = fileSize(gpuOut65)
            } catch {}

            let bestGPU = min(gpuSize85, gpuSize75, gpuSize65)

            // Résultats CLI
            let cli = cliJPEG[fname]
            let jtSize = cli?.jpegtranSize ?? origSize
            let cjSize = cli?.cjpegQ85Size ?? origSize

            // Gagnant global
            let allResults: [(String, Int64)] = [
                ("GPU", bestGPU),
                ("jpegtran", jtSize),
                ("cjpeg_q85", cjSize),
            ]
            let winner = allResults.min(by: { $0.1 < $1.1 })!

            if winner.0 == "GPU" { gpuWins += 1 }
            else if winner.0 == "jpegtran" { jpegtranWins += 1 }
            else { cjpegWins += 1 }

            results.append(JPEGResult(
                file: fname, origSize: origSize,
                gpuQ85: gpuSize85, gpuQ75: gpuSize75, gpuQ65: gpuSize65,
                jpegtranSize: jtSize, cjpegQ85: cjSize, winner: winner.0
            ))

            let pad = fname.padding(toLength: 25, withPad: " ", startingAt: 0)
            print("  \(pad) \(origSize) \(gpuSize85) \(gpuSize75) \(gpuSize65) \(jtSize) \(cjSize)  🏆 \(winner.0)")
        }

        // Rapport
        print("\n═══ RÉSUMÉ GPU JPEG vs CLI ═══\n")
        print("  GPU Metal gagne    : \(gpuWins)/\(jpegFiles.count) (\(pct(gpuWins, jpegFiles.count))%)")
        print("  jpegtran gagne     : \(jpegtranWins)/\(jpegFiles.count) (\(pct(jpegtranWins, jpegFiles.count))%)")
        print("  cjpeg q85 gagne    : \(cjpegWins)/\(jpegFiles.count) (\(pct(cjpegWins, jpegFiles.count))%)")

        let totalOrig = results.reduce(Int64(0)) { $0 + $1.origSize }
        let totalGPU = results.reduce(Int64(0)) { $0 + min($1.gpuQ85, $1.gpuQ75, $1.gpuQ65) }
        let totalJT = results.reduce(Int64(0)) { $0 + $1.jpegtranSize }
        let totalCJ = results.reduce(Int64(0)) { $0 + $1.cjpegQ85 }

        print("\n  Économie totale GPU      : \(formatKB(totalOrig - totalGPU)) Ko (\(pctSaving(totalGPU, totalOrig))%)")
        print("  Économie totale jpegtran : \(formatKB(totalOrig - totalJT)) Ko (\(pctSaving(totalJT, totalOrig))%)")
        print("  Économie totale cjpeg q85: \(formatKB(totalOrig - totalCJ)) Ko (\(pctSaving(totalCJ, totalOrig))%)")

        print("\n═══ RECOMMANDATION JPEG ═══\n")
        if gpuWins > jpegtranWins && gpuWins > cjpegWins {
            print("  GPU Metal est le meilleur encodeur JPEG lossy.")
            print("  Pipeline : GPU → jpegtran (polish lossless) → keepBest()")
        } else if gpuWins == 0 {
            print("  GPU Metal ne gagne jamais pour JPEG — envisager de le retirer.")
        } else {
            print("  GPU et cjpeg/jpegtran se partagent les victoires.")
            print("  Pipeline recommandé : GPU + cjpeg → jpegtran → keepBest()")
        }

        // Sauvegarder CSV
        let reportURL = corpusDir.appendingPathComponent("gpu-jpeg-benchmark-results.txt")
        let header = "file,original,gpu_q85,gpu_q75,gpu_q65,jpegtran,cjpeg_q85,winner"
        let lines = results.map { "\($0.file),\($0.origSize),\($0.gpuQ85),\($0.gpuQ75),\($0.gpuQ65),\($0.jpegtranSize),\($0.cjpegQ85),\($0.winner)" }
        try ([header] + lines).joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print("\n  Résultats CSV : \(reportURL.path)")
    }

    // MARK: - JPEG CLI Results loader

    private struct JPEGCLIRow {
        let jpegtranSize: Int64
        let cjpegQ85Size: Int64
    }

    private func loadJPEGCLIResults() -> [String: JPEGCLIRow] {
        let jpegCSV = corpusDir.appendingPathComponent("jpeg-comparison-results.csv")
        guard FileManager.default.fileExists(atPath: jpegCSV.path),
              let content = try? String(contentsOf: jpegCSV, encoding: .utf8) else {
            print("  ⚠️  jpeg-comparison-results.csv introuvable — comparaison GPU-only pour jpegtran/cjpeg")
            return [:]
        }
        var dict: [String: JPEGCLIRow] = [:]
        let lines = content.components(separatedBy: "\n").dropFirst()
        for line in lines where !line.isEmpty {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 6 else { continue }
            let fname = cols[0]
            let jtSize = Int64(cols[3]) ?? 0   // jpegtran_lossless_bytes
            let cj85 = Int64(cols[5]) ?? 0     // cjpeg_q85_bytes
            dict[fname] = JPEGCLIRow(jpegtranSize: jtSize, cjpegQ85Size: cj85)
        }
        return dict
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func pct(_ n: Int, _ total: Int) -> String {
        total > 0 ? String(format: "%.1f", Double(n) / Double(total) * 100) : "0"
    }

    private func pctSaving(_ optimized: Int64, _ original: Int64) -> String {
        original > 0 ? String(format: "%.1f", (1 - Double(optimized) / Double(original)) * 100) : "0"
    }

    private func formatKB(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1024.0)
    }

    // MARK: - CLI Results loader

    private struct CLIRow {
        let pngquantSize: Int64
        let bestOxipngSize: Int64
    }

    private func loadCLIResults() -> [String: CLIRow] {
        guard FileManager.default.fileExists(atPath: csvURL.path),
              let content = try? String(contentsOf: csvURL, encoding: .utf8) else {
            print("  ⚠️  CSV tool-comparison-results.csv introuvable — comparaison GPU-only")
            return [:]
        }
        var dict: [String: CLIRow] = [:]
        let lines = content.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines where !line.isEmpty {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 7 else { continue }
            let fname = cols[0]
            let pqSize = Int64(cols[3]) ?? 0
            let oxi4Size = Int64(cols[5]) ?? 0
            let oxi6Size = Int64(cols[6]) ?? 0
            let bestOxi = min(oxi4Size, oxi6Size)
            dict[fname] = CLIRow(pngquantSize: pqSize, bestOxipngSize: bestOxi)
        }
        return dict
    }

    private struct GPUResult {
        let file: String
        let originalSize: Int64
        let gpuSize65: Int64
        let gpuSize80: Int64
        let pngquantSize: Int64
        let oxipngSize: Int64
        let winner: String
    }
}
