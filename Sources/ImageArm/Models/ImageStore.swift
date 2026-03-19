import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImageStore: ObservableObject {
    @Published var files: [ImageFile] = [] {
        didSet { subscribeToFiles() }
    }
    @Published var showFilePicker = false
    @Published var isProcessing = false
    @Published var level: OptimizationLevel {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: "optimizationLevel") }
    }

    @AppStorage("maxConcurrent") var maxConcurrent = 4
    @AppStorage("jpegLossy") var jpegLossyOverride = false
    @AppStorage("jpegQualityCustom") var jpegQualityCustom = 85.0
    @AppStorage("pngLossy") var pngLossyOverride = false
    @AppStorage("pngQualityCustom") var pngQualityCustom = 80.0
    @AppStorage("useCustomQuality") var useCustomQuality = false

    private static let donationPromptsEnabled = true
    @AppStorage("donationBatchCount") var donationBatchCount = 0
    @AppStorage("donationNextPromptAt") var donationNextPromptAt = 2
    @AppStorage("donationDone") var donationDone = false
    @Published var showDonationPrompt = false
    @Published var donationTriggerCompletedCount = 0
    @Published var donationTriggerTotalSavings: Int64 = 0

    private let optimizer = ImageOptimizer()
    private var optimizationTask: Task<Void, Never>?
    private var auxiliaryTasks: [Task<Void, Never>] = []
    private var fileCancellables = Set<AnyCancellable>()
    private static let completionSound = NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), byReference: true)

    init() {
        let hasStoredLevel = UserDefaults.standard.object(forKey: "optimizationLevel") != nil
        let saved = hasStoredLevel ? UserDefaults.standard.integer(forKey: "optimizationLevel") : OptimizationLevel.standard.rawValue
        self.level = OptimizationLevel(rawValue: saved) ?? .standard
        subscribeToFiles()
        resetDonationCountersIfVersionChanged()
    }

    private func resetDonationCountersIfVersionChanged() {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "") + "." + (info?["CFBundleVersion"] as? String ?? "")
        let stored = UserDefaults.standard.string(forKey: "donationAppVersion") ?? ""
        guard version != ".", version != stored else { return }
        UserDefaults.standard.set(version, forKey: "donationAppVersion")
        UserDefaults.standard.set(0, forKey: "donationBatchCount")
        UserDefaults.standard.set(2, forKey: "donationNextPromptAt")
        // donationDone conservé — si l'utilisateur a déjà donné, on s'en souvient
    }

    private func subscribeToFiles() {
        fileCancellables.removeAll()
        for file in files {
            file.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &fileCancellables)
        }
    }

    var totalOriginalSize: Int64 {
        files.reduce(0) { $0 + $1.originalSize }
    }

    var totalOptimizedSize: Int64 {
        files.reduce(0) { $0 + ($1.optimizedSize ?? $1.originalSize) }
    }

    var totalSavings: Int64 {
        totalOriginalSize - totalOptimizedSize
    }

    var completedCount: Int {
        files.filter { $0.status.isComplete }.count
    }

    var firstProcessingFileID: ImageFile.ID? {
        files.first(where: { $0.status.currentTool != nil })?.id
    }

    static let supportedTypes: [UTType] = ([.png, .jpeg, .heic, .gif, .tiff, .svg, .webP] as [UTType])
        + [UTType(filenameExtension: "avif")].compactMap { $0 }
    static let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "avif", "svg", "webp"])

    func addFiles(urls: [URL]) {
        let existingURLs = Set(files.map(\.url))
        var newFiles: [ImageFile] = []
        for url in urls {
            if url.hasDirectoryPath {
                collectFilesFromDirectory(url, excluding: existingURLs, into: &newFiles)
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()),
                      !existingURLs.contains(url) {
                newFiles.append(ImageFile(url: url))
            }
        }
        if !newFiles.isEmpty {
            files.append(contentsOf: newFiles)
        }
    }

    private func collectFilesFromDirectory(_ url: URL, excluding existingURLs: Set<URL>, into newFiles: inout [ImageFile]) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()),
               !existingURLs.contains(fileURL) {
                newFiles.append(ImageFile(url: fileURL))
            }
        }
    }

    func optimizeAll() {
        let pending = files.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }

        // If already processing, queue new files with bounded concurrency
        // to avoid overwriting optimizationTask (orphan + premature isProcessing=false)
        if isProcessing {
            let level = self.level
            let maxConc = self.maxConcurrent
            let overrides = QualityOverrides(
                useCustom: self.useCustomQuality,
                jpegLossy: self.jpegLossyOverride,
                jpegQuality: Int(self.jpegQualityCustom),
                pngLossy: self.pngLossyOverride,
                pngQuality: Int(self.pngQualityCustom)
            )
            let task = Task {
                await withBoundedConcurrency(over: pending, maxConcurrent: maxConc) { file in
                    await self.optimizer.optimize(file: file, level: level, overrides: overrides)
                }
                // Même logique de don que optimizationTask (F3).
                // Thread-safe : Task créé depuis @MainActor hérite du contexte (F9).
                guard !Task.isCancelled else { return }
                donationBatchCount += 1
                if Self.donationPromptsEnabled && !donationDone && completedCount > 0
                    && donationBatchCount >= max(1, donationNextPromptAt) {
                    donationNextPromptAt += 10
                    donationTriggerCompletedCount = completedCount
                    donationTriggerTotalSavings = max(0, totalSavings)
                    showDonationPrompt = true
                }
            }
            auxiliaryTasks.append(task)
            return
        }

        isProcessing = true
        let level = self.level
        let maxConc = self.maxConcurrent
        let overrides = QualityOverrides(
            useCustom: self.useCustomQuality,
            jpegLossy: self.jpegLossyOverride,
            jpegQuality: Int(self.jpegQualityCustom),
            pngLossy: self.pngLossyOverride,
            pngQuality: Int(self.pngQualityCustom)
        )

        optimizationTask = Task {
            await withBoundedConcurrency(over: pending, maxConcurrent: maxConc) { file in
                await self.optimizer.optimize(file: file, level: level, overrides: overrides)
            }
            // Thread-safe : Task créé depuis @MainActor hérite du contexte (F9).
            guard !Task.isCancelled else { return }
            donationBatchCount += 1
            if Self.donationPromptsEnabled && !donationDone && completedCount > 0
                && donationBatchCount >= max(1, donationNextPromptAt) {
                donationNextPromptAt += 10
                donationTriggerCompletedCount = completedCount        // snapshot (F4)
                donationTriggerTotalSavings = max(0, totalSavings)   // clamped ≥ 0 (F5)
                showDonationPrompt = true
            }
            isProcessing = false
            optiLog(String(localized: "Traitement terminé"), level: .success)
            Self.completionSound?.stop()
            Self.completionSound?.play()
        }
    }

    func stopAll() {
        optimizationTask?.cancel()
        for task in auxiliaryTasks { task.cancel() }
        auxiliaryTasks.removeAll()
        isProcessing = false
        for file in files where file.status.currentTool != nil {
            file.status = .pending
        }
    }

    func clearCompleted() {
        files.removeAll { $0.status.isComplete }
    }

    func clearAll() {
        stopAll()
        files.removeAll()
    }

    func removeFiles(_ ids: Set<ImageFile.ID>) {
        files.removeAll { ids.contains($0.id) }
    }

    func reoptimize(_ file: ImageFile) {
        guard file.status.currentTool == nil else { return }
        file.status = .pending
        file.optimizedSize = nil
        let level = self.level
        let overrides = QualityOverrides(
            useCustom: self.useCustomQuality,
            jpegLossy: self.jpegLossyOverride,
            jpegQuality: Int(self.jpegQualityCustom),
            pngLossy: self.pngLossyOverride,
            pngQuality: Int(self.pngQualityCustom)
        )
        let task = Task {
            await optimizer.optimize(file: file, level: level, overrides: overrides)
        }
        auxiliaryTasks.append(task)
    }
}
