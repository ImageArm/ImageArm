import Foundation

/// Actor qui orchestre le pipeline d'optimisation multi-outils.
/// Bien que ce soit un actor, la concurrence fonctionne car `run()` suspend via
/// `withCheckedContinuation` + `terminationHandler`, libérant l'actor pour d'autres appels.
actor ImageOptimizer {
    private let toolManager = ToolManager()
    private let gpu = GPUProcessor.shared

    func optimize(file: ImageFile, level: OptimizationLevel, overrides: QualityOverrides = .none) async {
        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        switch file.format {
        case .png:   await optimizePNG(file: file, level: level, overrides: overrides)
        case .jpeg:  await optimizeJPEG(file: file, level: level, overrides: overrides)
        case .heif:  await optimizeHEIF(file: file, level: level)
        case .gif:   await optimizeGIF(file: file, level: level)
        case .tiff:  await optimizeTIFF(file: file, level: level)
        case .avif:  await optimizeAVIF(file: file, level: level)
        case .svg:   await optimizeSVG(file: file, level: level)
        case .webp:  await optimizeWebP(file: file, level: level)
        case .unknown:
            await MainActor.run { file.status = .failed(String(localized: "Format non supporté")) }
        }
    }

    // MARK: - Actual step counts (accounts for missing tools)

    private func actualPNGSteps(level: OptimizationLevel, overrides: QualityOverrides) -> Int {
        let pngIsLossy = overrides.effectivePNGLossy(level: level)
        var steps = 0
        if pngIsLossy && gpu != nil { steps += 1 }
        if pngIsLossy && toolManager.find("pngquant") != nil { steps += 1 }
        if toolManager.find("oxipng") != nil { steps += 1 }
        if level.usePngcrush && toolManager.find("pngcrush") != nil { steps += 1 }
        return max(steps, 1)
    }

    private func actualJPEGSteps(level: OptimizationLevel, overrides: QualityOverrides) -> Int {
        let jpegIsLossy = overrides.effectiveJPEGLossy(level: level)
        var steps = 0
        if jpegIsLossy && gpu != nil { steps += 1 }
        if toolManager.find("jpegtran") != nil { steps += 1 }
        return max(steps, 1)
    }

    // MARK: - PNG

    private func optimizePNG(file: ImageFile, level: OptimizationLevel, overrides: QualityOverrides) async {
        let path = file.url.path
        let tempPath = path + ".imagearm.tmp"
        let total = actualPNGSteps(level: level, overrides: overrides)
        var step = 0
        defer { cleanupTemps(around: path) }

        guard copyFile(from: path, to: tempPath) else {
            await setFailed(file, String(localized: "Erreur de copie"))
            return
        }

        var bestPath = tempPath
        var bestSize = fileSize(tempPath)
        let pngIsLossy = overrides.effectivePNGLossy(level: level)
        let pngQRange = overrides.effectivePNGQualityRange(level: level)

        // --- GPU quantization (Metal compute shader) ---
        if pngIsLossy, let gpu = gpu {
            step += 1
            await setProcessing(file, "Metal GPU", step: step, total: total)
            let gpuOut = tempPath + ".gpu.png"
            do {
                try gpu.quantizePNG(inputPath: tempPath, outputPath: gpuOut, quality: pngQRange.max)
                bestPath = keepBest(&bestSize, candidate: gpuOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "Metal GPU quantize : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(gpuOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- pngquant (lossy quantization, compete with GPU result) ---
        if pngIsLossy, let pngquant = toolManager.find("pngquant") {
            step += 1
            await setProcessing(file, "pngquant", step: step, total: total)
            let quantOut = tempPath + ".quant.png"
            let (minQ, maxQ) = pngQRange
            let result = await run(pngquant, args: [
                "--force",
                "--quality=\(minQ)-\(maxQ)",
                "--speed=1",
                "--strip",
                "--output", quantOut,
                tempPath
            ])
            if result.exitCode == 0 {
                bestPath = keepBest(&bestSize, candidate: quantOut, current: bestPath, tempBase: tempPath)
            }
            cleanupIfNot(quantOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- oxipng (lossless recompression on best candidate) ---
        if let oxipng = toolManager.find("oxipng"), copyFile(from: bestPath, to: tempPath + ".oxi.png") {
            step += 1
            await setProcessing(file, "oxipng", step: step, total: total)
            let oxiOut = tempPath + ".oxi.png"
            var args = ["-o", "\(level.oxipngLevel)", "--threads", "1"]
            if level.stripMetadata { args += ["--strip", "safe"] }
            args.append(oxiOut)
            let result = await run(oxipng, args: args)
            if result.exitCode == 0 {
                bestPath = keepBest(&bestSize, candidate: oxiOut, current: bestPath, tempBase: tempPath)
            }
            cleanupIfNot(oxiOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- pngcrush (brute-force filter selection) ---
        if level.usePngcrush, let pngcrush = toolManager.find("pngcrush") {
            step += 1
            await setProcessing(file, "pngcrush", step: step, total: total)
            let crushIn = tempPath + ".crush_in.png"
            let crushOut = tempPath + ".crush.png"
            if copyFile(from: bestPath, to: crushIn) {
                var args = ["-reduce"]
                if level.pngcrushBrute { args.append("-brute") }
                if level.stripMetadata { args += ["-rem", "allb"] }
                args += [crushIn, crushOut]
                let result = await run(pngcrush, args: args)
                try? FileManager.default.removeItem(atPath: crushIn)
                if result.exitCode == 0 {
                    bestPath = keepBest(&bestSize, candidate: crushOut, current: bestPath, tempBase: tempPath)
                }
                cleanupIfNot(crushOut, keep: bestPath)
            }
        }

        await finalize(file: file, originalPath: path, bestPath: bestPath, bestSize: bestSize)
    }

    // MARK: - JPEG

    private func optimizeJPEG(file: ImageFile, level: OptimizationLevel, overrides: QualityOverrides) async {
        let path = file.url.path
        let tempPath = path + ".imagearm.tmp"
        let total = actualJPEGSteps(level: level, overrides: overrides)
        var step = 0
        defer { cleanupTemps(around: path) }

        guard copyFile(from: path, to: tempPath) else {
            await setFailed(file, String(localized: "Erreur de copie"))
            return
        }

        var bestPath = tempPath
        var bestSize = fileSize(tempPath)
        let jpegIsLossy = overrides.effectiveJPEGLossy(level: level)
        let jpegQ = overrides.effectiveJPEGQuality(level: level)

        // --- GPU hardware JPEG encoding (Apple Silicon media engine) ---
        if jpegIsLossy, let gpu = gpu {
            step += 1
            await setProcessing(file, "Metal GPU", step: step, total: total)
            let gpuOut = tempPath + ".gpu.jpg"
            do {
                try gpu.encodeJPEGHardware(
                    inputPath: tempPath,
                    outputPath: gpuOut,
                    quality: jpegQ,
                    stripMetadata: level.stripMetadata
                )
                bestPath = keepBest(&bestSize, candidate: gpuOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "Metal GPU JPEG : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(gpuOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- mozjpeg jpegtran (lossless progressive recompression) ---
        if let jpegtran = toolManager.find("jpegtran") {
            step += 1
            await setProcessing(file, "mozjpeg", step: step, total: total)
            let mozOut = tempPath + ".moz.jpg"
            var args = [
                "-copy", level.stripMetadata ? "none" : "all",
                "-optimize",
            ]
            if level.jpegProgressive { args.append("-progressive") }
            args += ["-outfile", mozOut, bestPath]
            let result = await run(jpegtran, args: args)
            if result.exitCode == 0 {
                bestPath = keepBest(&bestSize, candidate: mozOut, current: bestPath, tempBase: tempPath)
            }
            cleanupIfNot(mozOut, keep: bestPath)
        }

        await finalize(file: file, originalPath: path, bestPath: bestPath, bestSize: bestSize)
    }

    // MARK: - HEIF

    private func optimizeHEIF(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        let tempPath = path + ".imagearm.tmp"
        let total = actualHEIFSteps(level: level)
        var step = 0
        defer { cleanupTemps(around: path) }

        guard copyFile(from: path, to: tempPath) else {
            await setFailed(file, String(localized: "Erreur de copie"))
            return
        }

        var bestPath = tempPath
        var bestSize = fileSize(tempPath)
        let heifIsLossy = level.heifLossy

        // --- Lossy HEIF encoding (GPU hardware, configurable quality) ---
        if heifIsLossy, let gpu = gpu {
            step += 1
            await setProcessing(file, "HEIF lossy", step: step, total: total)
            let lossyOut = tempPath + ".imagearm.heif.lossy"
            do {
                try gpu.encodeHEIFHardware(
                    inputPath: tempPath,
                    outputPath: lossyOut,
                    quality: level.heifQuality,
                    stripMetadata: level.stripMetadata
                )
                bestPath = keepBest(&bestSize, candidate: lossyOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "HEIF lossy : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(lossyOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- Max quality HEIF encoding (GPU hardware, quality = 1.0) ---
        if let gpu = gpu {
            step += 1
            await setProcessing(file, "HEIF qualité max", step: step, total: total)
            let losslessOut = tempPath + ".imagearm.heif.lossless"
            do {
                try gpu.encodeHEIFMaxQuality(
                    inputPath: tempPath,
                    outputPath: losslessOut,
                    stripMetadata: level.stripMetadata
                )
                bestPath = keepBest(&bestSize, candidate: losslessOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "HEIF qualité max : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(losslessOut, keep: bestPath)
        }

        await finalize(file: file, originalPath: path, bestPath: bestPath, bestSize: bestSize)
    }

    private func actualHEIFSteps(level: OptimizationLevel) -> Int {
        var steps = 0
        if gpu != nil {
            if level.heifLossy { steps += 1 }  // lossy
            steps += 1                           // lossless (always)
        }
        return max(steps, 1)
    }

    // MARK: - GIF

    private func optimizeGIF(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        guard let gifsicle = toolManager.find("gifsicle") else {
            optiLog("\(file.url.lastPathComponent) : gifsicle non disponible, ignoré", level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
            return
        }

        await setProcessing(file, "gifsicle", step: 1, total: 1)
        let tempOut = path + ".imagearm.gif"
        defer { cleanupTemps(around: path) }

        let origSize = fileSize(path)
        var args = ["--optimize=\(level.gifOptimizeLevel)"]
        if level.gifLossy { args.append("--lossy=\(level.gifLossyLevel)") }
        if level.stripMetadata { args.append("--no-comments") }
        args += [path, "--output", tempOut]

        let result = await run(gifsicle, args: args)
        guard result.exitCode == 0 else {
            await setFailed(file, result.stderr.prefix(200).description)
            return
        }

        let newSize = fileSize(tempOut)
        if newSize < origSize && newSize > 0 {
            await safeReplace(file: file, originalPath: path, optimizedPath: tempOut, originalSize: origSize, optimizedSize: newSize)
        } else {
            optiLog(String(localized: "\(file.url.lastPathComponent) : déjà optimal (\(formatBytes(origSize)))"), level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
        }
    }

    // MARK: - TIFF

    private func optimizeTIFF(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        guard let tiffutil = toolManager.find("tiffutil") else {
            optiLog("\(file.url.lastPathComponent) : tiffutil non disponible, ignoré", level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
            return
        }

        await setProcessing(file, "tiffutil", step: 1, total: 1)
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let tempOut = path + ".imagearm.\(ext)"
        defer { cleanupTemps(around: path) }

        let origSize = fileSize(path)
        let result = await run(tiffutil, args: ["-lzw", path, "-out", tempOut])
        guard result.exitCode == 0 else {
            await setFailed(file, result.stderr.prefix(200).description)
            return
        }

        let newSize = fileSize(tempOut)
        if newSize < origSize && newSize > 0 {
            await safeReplace(file: file, originalPath: path, optimizedPath: tempOut, originalSize: origSize, optimizedSize: newSize)
        } else {
            optiLog(String(localized: "\(file.url.lastPathComponent) : déjà optimal (\(formatBytes(origSize)))"), level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
        }
    }

    // MARK: - AVIF

    private func optimizeAVIF(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        let tempPath = path + ".imagearm.tmp"
        let total = actualAVIFSteps(level: level)
        var step = 0
        defer { cleanupTemps(around: path) }

        guard copyFile(from: path, to: tempPath) else {
            await setFailed(file, String(localized: "Erreur de copie"))
            return
        }

        var bestPath = tempPath
        var bestSize = fileSize(tempPath)

        // --- Lossy AVIF encoding (GPU hardware, qualité configurable) ---
        if level.avifLossy, let gpu = gpu {
            step += 1
            await setProcessing(file, "AVIF lossy", step: step, total: total)
            let lossyOut = tempPath + ".imagearm.avif.lossy"
            do {
                try gpu.encodeAVIFHardware(
                    inputPath: tempPath,
                    outputPath: lossyOut,
                    quality: level.avifQuality,
                    stripMetadata: level.stripMetadata
                )
                bestPath = keepBest(&bestSize, candidate: lossyOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "AVIF lossy : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(lossyOut, keep: bestPath)
        }

        guard !Task.isCancelled else {
            await MainActor.run { file.status = .pending }
            return
        }

        // --- Max quality AVIF encoding (GPU hardware, qualité = 100) ---
        if let gpu = gpu {
            step += 1
            await setProcessing(file, "AVIF qualité max", step: step, total: total)
            let maxOut = tempPath + ".imagearm.avif.max"
            do {
                try gpu.encodeAVIFMaxQuality(
                    inputPath: tempPath,
                    outputPath: maxOut,
                    stripMetadata: level.stripMetadata
                )
                bestPath = keepBest(&bestSize, candidate: maxOut, current: bestPath, tempBase: tempPath)
            } catch {
                optiLog(String(localized: "AVIF qualité max : \(error.localizedDescription)"), level: .warning)
            }
            cleanupIfNot(maxOut, keep: bestPath)
        }

        await finalize(file: file, originalPath: path, bestPath: bestPath, bestSize: bestSize)
    }

    private func actualAVIFSteps(level: OptimizationLevel) -> Int {
        var steps = 0
        if gpu != nil {
            if level.avifLossy { steps += 1 }
            steps += 1  // max quality (always)
        }
        return max(steps, 1)
    }

    // MARK: - SVG

    private func optimizeSVG(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        guard let svgo = toolManager.find("svgo") else {
            optiLog("\(file.url.lastPathComponent) : svgo non disponible, ignoré", level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
            return
        }

        await setProcessing(file, "svgo", step: 1, total: 1)
        let tempOut = path + ".imagearm.svg"
        defer { cleanupTemps(around: path) }

        let origSize = fileSize(path)
        var args = ["-i", path, "-o", tempOut]
        if level.svgoMultipass { args.append("--multipass") }
        let result = await run(svgo, args: args)
        guard result.exitCode == 0 else {
            await setFailed(file, result.stderr.prefix(200).description)
            return
        }

        let newSize = fileSize(tempOut)
        if newSize < origSize && newSize > 0 {
            await safeReplace(file: file, originalPath: path, optimizedPath: tempOut, originalSize: origSize, optimizedSize: newSize)
        } else {
            optiLog(String(localized: "\(file.url.lastPathComponent) : déjà optimal (\(formatBytes(origSize)))"), level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
        }
    }

    // MARK: - WebP

    private func optimizeWebP(file: ImageFile, level: OptimizationLevel) async {
        let path = file.url.path
        guard let cwebp = toolManager.find("cwebp") else {
            optiLog("\(file.url.lastPathComponent) : cwebp non disponible, ignoré", level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
            return
        }

        await setProcessing(file, "cwebp", step: 1, total: 1)
        let tempOut = path + ".imagearm.webp"
        defer { cleanupTemps(around: path) }

        var args: [String]
        if level.webpLossless {
            args = ["-lossless", "-z", "\(level.webpCompressionLevel)", path, "-o", tempOut]
        } else {
            args = ["-q", "\(level.webpQuality)", "-m", "\(level.webpCompressionLevel)", path, "-o", tempOut]
        }

        let result = await run(cwebp, args: args)
        guard result.exitCode == 0 else {
            await setFailed(file, result.stderr.prefix(200).description)
            return
        }

        let origSize = fileSize(path)
        let newSize = fileSize(tempOut)
        if newSize < origSize && newSize > 0 {
            await safeReplace(file: file, originalPath: path, optimizedPath: tempOut, originalSize: origSize, optimizedSize: newSize)
        } else {
            optiLog(String(localized: "\(file.url.lastPathComponent) : déjà optimal (\(formatBytes(origSize)))"), level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
        }
    }

    // MARK: - Helpers

    private func finalize(file: ImageFile, originalPath: String, bestPath: String, bestSize: Int64) async {
        let originalSize = fileSize(originalPath)

        if bestSize < originalSize && bestSize > 0 && bestPath != originalPath {
            await safeReplace(file: file, originalPath: originalPath, optimizedPath: bestPath, originalSize: originalSize, optimizedSize: bestSize)
        } else {
            let name = URL(fileURLWithPath: originalPath).lastPathComponent
            let formattedSize = formatBytes(originalSize)
            optiLog(String(localized: "\(name) : déjà optimal (\(formattedSize))"), level: .info)
            await MainActor.run { file.status = .alreadyOptimal }
        }
    }

    /// Safe in-place replace: backup original, move optimized, trash backup
    private func safeReplace(file: ImageFile, originalPath: String, optimizedPath: String, originalSize: Int64, optimizedSize: Int64) async {
        let name = URL(fileURLWithPath: originalPath).lastPathComponent
        let backupPath = originalPath + ".imagearm.backup"
        do {
            try FileManager.default.moveItem(atPath: originalPath, toPath: backupPath)
            try FileManager.default.moveItem(atPath: optimizedPath, toPath: originalPath)
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: backupPath), resultingItemURL: nil)
            if FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.removeItem(atPath: backupPath)
            }
            let saved = originalSize - optimizedSize
            let pct = originalSize > 0 ? Double(saved) / Double(originalSize) * 100 : 0
            optiLog("\(name) : \(formatBytes(originalSize)) -> \(formatBytes(optimizedSize)) (-\(formatBytes(saved)), \(String(format: "%.1f%%", pct)))", level: .success)
            await MainActor.run {
                file.optimizedSize = optimizedSize
                file.status = .done(savedBytes: saved)
            }
        } catch {
            if !FileManager.default.fileExists(atPath: originalPath),
               FileManager.default.fileExists(atPath: backupPath) {
                do {
                    try FileManager.default.moveItem(atPath: backupPath, toPath: originalPath)
                } catch let restoreError {
                    optiLog("\(name) : \(String(localized: "ERREUR restauration backup")) - \(restoreError.localizedDescription)", level: .error)
                }
            }
            optiLog("\(name) : \(String(localized: "ERREUR")) - \(error.localizedDescription)", level: .error)
            await MainActor.run { file.status = .failed(String(localized: "Erreur remplacement")) }
        }
    }

    private func keepBest(_ bestSize: inout Int64, candidate: String, current: String, tempBase: String) -> String {
        let candidateSize = fileSize(candidate)
        if candidateSize < bestSize && candidateSize > 0 {
            let formattedCandidate = formatBytes(candidateSize)
            let formattedBest = formatBytes(bestSize)
            optiLog(String(localized: "  meilleur résultat : \(formattedCandidate) (vs \(formattedBest))"), level: .info)
            if current != tempBase {
                try? FileManager.default.removeItem(atPath: current)
            }
            bestSize = candidateSize
            return candidate
        }
        return current
    }

    private func cleanupIfNot(_ path: String, keep: String) {
        if path != keep {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Clean temp files only for a specific file (not all .imagearm files in directory)
    private func cleanupTemps(around path: String) {
        let baseName = URL(fileURLWithPath: path).lastPathComponent
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for item in items where item.hasPrefix(baseName + ".imagearm.") {
                try? FileManager.default.removeItem(atPath: dir + "/" + item)
            }
        }
    }

    private func copyFile(from src: String, to dst: String) -> Bool {
        try? FileManager.default.removeItem(atPath: dst)
        return (try? FileManager.default.copyItem(atPath: src, toPath: dst)) != nil
    }

    private func fileSize(_ path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    private func setProcessing(_ file: ImageFile, _ tool: String, step: Int, total: Int) async {
        let name = file.url.lastPathComponent
        let isGPU = tool.contains("Metal") || tool.contains("GPU")
        optiLog("[\(step)/\(total)] \(name) : \(tool)...", level: isGPU ? .gpu : .info)
        await MainActor.run { file.status = .processing(tool: tool, step: step, totalSteps: total) }
    }

    private func setFailed(_ file: ImageFile, _ msg: String) async {
        optiLog("\(file.url.lastPathComponent) : \(String(localized: "ERREUR")) - \(msg)", level: .error)
        await MainActor.run { file.status = .failed(msg) }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static let extendedPATH: String = {
        let extra = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/opt/mozjpeg/bin",
            "/usr/local/opt/mozjpeg/bin",
        ]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        return (extra + [current]).joined(separator: ":")
    }()

    private func run(_ executable: String, args: [String]) async -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.extendedPATH
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let readGroup = DispatchGroup()

        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Set terminationHandler BEFORE run() to avoid race condition
                // where process exits before handler is assigned.
                process.terminationHandler = { _ in
                    readGroup.notify(queue: .global()) {
                        continuation.resume(returning: ProcessResult(
                            exitCode: process.terminationStatus,
                            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                            stderr: String(data: stderrData, encoding: .utf8) ?? ""
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(returning: ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }

                // Read pipe data AFTER process started to avoid deadlock
                // when the pipe buffer (64KB) fills up.
                readGroup.enter()
                DispatchQueue.global().async {
                    stdoutData = stdoutHandle.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global().async {
                    stderrData = stderrHandle.readDataToEndOfFile()
                    readGroup.leave()
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}

/// Execute async work on `items` with at most `maxConcurrent` tasks in flight.
/// Stops submitting new tasks as soon as the parent Task is cancelled.
func withBoundedConcurrency<T: Sendable>(
    over items: [T],
    maxConcurrent: Int,
    body: @escaping @Sendable (T) async -> Void
) async {
    await withTaskGroup(of: Void.self) { group in
        var running = 0
        var index = 0
        while index < items.count {
            guard !Task.isCancelled else { break }
            if running < maxConcurrent {
                let item = items[index]
                index += 1
                running += 1
                group.addTask { await body(item) }
            } else {
                await group.next()
                running -= 1
            }
        }
        for await _ in group {}
    }
}
