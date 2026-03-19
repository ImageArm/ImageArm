import Foundation

enum OptimizationStatus: Equatable {
    case pending
    case processing(tool: String, step: Int, totalSteps: Int)
    case done(savedBytes: Int64)
    case alreadyOptimal
    case failed(String)

    var isComplete: Bool {
        switch self {
        case .done, .alreadyOptimal, .failed: return true
        default: return false
        }
    }

    var progress: Double {
        switch self {
        case .pending: return 0
        case .processing(_, let step, let totalSteps):
            return totalSteps > 0 ? Double(step) / Double(totalSteps) : 0
        case .done, .alreadyOptimal, .failed: return 1
        }
    }

    var currentTool: String? {
        if case .processing(let tool, _, _) = self { return tool }
        return nil
    }

    var stepInfo: String? {
        if case .processing(let tool, let step, let total) = self {
            return "\(tool) (\(step)/\(total))"
        }
        return nil
    }
}

enum ImageFormat: String, CaseIterable {
    case png, jpeg, heif, gif, tiff, avif, svg, webp, unknown

    static func detect(from url: URL) -> ImageFormat {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heif
        case "gif": return .gif
        case "tiff", "tif": return .tiff
        case "avif": return .avif
        case "svg": return .svg
        case "webp": return .webp
        default: return .unknown
        }
    }

    var displayName: String {
        self == .heif ? "HEIF" : rawValue.uppercased()
    }
}

@MainActor
final class ImageFile: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let format: ImageFormat
    let originalSize: Int64

    @Published var optimizedSize: Int64?
    @Published var status: OptimizationStatus = .pending

    var fileName: String { url.lastPathComponent }

    var savings: Double? {
        guard let opt = optimizedSize, originalSize > 0 else { return nil }
        return Double(originalSize - opt) / Double(originalSize) * 100
    }

    var savedBytes: Int64? {
        guard let opt = optimizedSize else { return nil }
        return originalSize - opt
    }

    init(url: URL) {
        self.url = url
        self.format = ImageFormat.detect(from: url)
        self.originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

extension ImageFile: Hashable {
    nonisolated static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.id == rhs.id
    }
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
