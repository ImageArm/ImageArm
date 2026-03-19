import Foundation

enum OptimizationLevel: Int, CaseIterable, Identifiable, Codable {
    case quick = 0
    case standard = 1
    case high = 2
    case ultra = 3

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .quick: return String(localized: "Rapide")
        case .standard: return String(localized: "Standard")
        case .high: return String(localized: "Maximum")
        case .ultra: return String(localized: "Ultra")
        }
    }

    var icon: String {
        switch self {
        case .quick: return "hare"
        case .standard: return "gauge.with.dots.needle.50percent"
        case .high: return "gauge.with.dots.needle.67percent"
        case .ultra: return "gauge.with.dots.needle.100percent"
        }
    }

    var useGPU: Bool {
        switch self {
        case .quick: return false
        case .standard: return false
        case .high: return true
        case .ultra: return true
        }
    }

    var description: String {
        switch self {
        case .quick:
            return String(localized: "Optimisation rapide, lossless uniquement. Idéal pour le développement.")
        case .standard:
            return String(localized: "Bon équilibre vitesse/compression. Recommandé pour la plupart des usages.")
        case .high:
            return String(localized: "Compression maximale + GPU Metal. Idéal pour la production web.")
        case .ultra:
            return String(localized: "Compression extrême, GPU Metal + toutes les passes CPU. Chaque octet compte.")
        }
    }

    var lossIndicator: String {
        switch self {
        case .quick, .standard: return String(localized: "(sans perte)")
        case .high: return String(localized: "(compression max)")
        case .ultra: return String(localized: "(compression extrême)")
        }
    }

    // MARK: - PNG Settings

    var pngLossy: Bool {
        switch self {
        case .quick: return false
        case .standard: return false
        case .high: return true
        case .ultra: return true
        }
    }

    var pngQuantQualityRange: (min: Int, max: Int) {
        switch self {
        case .quick: return (80, 100)
        case .standard: return (70, 95)
        case .high: return (60, 85)
        case .ultra: return (45, 75)
        }
    }

    var oxipngLevel: Int {
        switch self {
        case .quick: return 2
        case .standard: return 4
        case .high: return 6
        case .ultra: return 6  // max is 6
        }
    }

    var usePngcrush: Bool {
        switch self {
        case .quick: return false
        case .standard: return false
        case .high: return true
        case .ultra: return true
        }
    }

    var pngcrushBrute: Bool {
        self == .ultra
    }

    // MARK: - JPEG Settings

    var jpegLossy: Bool {
        switch self {
        case .quick: return false
        case .standard: return false
        case .high: return true
        case .ultra: return true
        }
    }

    var jpegQuality: Int {
        switch self {
        case .quick: return 95
        case .standard: return 90
        case .high: return 80
        case .ultra: return 70
        }
    }

    var jpegProgressive: Bool {
        self != .quick
    }

    // MARK: - HEIF Settings

    var heifLossy: Bool {
        switch self {
        case .quick: return false
        case .standard: return false
        case .high: return true
        case .ultra: return true
        }
    }

    var heifQuality: Int {
        switch self {
        case .quick: return 95
        case .standard: return 90
        case .high: return 80
        case .ultra: return 70
        }
    }

    // MARK: - WebP Settings

    var webpQuality: Int {
        switch self {
        case .quick: return 90
        case .standard: return 85
        case .high: return 78
        case .ultra: return 68
        }
    }

    var webpLossless: Bool {
        switch self {
        case .quick: return true
        case .standard: return true
        case .high: return false
        case .ultra: return false
        }
    }

    var webpCompressionLevel: Int {
        switch self {
        case .quick: return 4
        case .standard: return 6
        case .high: return 6
        case .ultra: return 6
        }
    }

    // MARK: - GIF Settings

    var gifOptimizeLevel: Int {
        switch self {
        case .quick: return 1
        case .standard: return 2
        case .high, .ultra: return 3
        }
    }

    var gifLossy: Bool {
        switch self {
        case .quick, .standard: return false
        case .high, .ultra: return true
        }
    }

    var gifLossyLevel: Int {
        switch self {
        case .quick, .standard: return 0
        case .high: return 80
        case .ultra: return 120
        }
    }

    // MARK: - AVIF Settings

    var avifLossy: Bool {
        switch self {
        case .quick, .standard: return false
        case .high, .ultra: return true
        }
    }

    var avifQuality: Int {
        switch self {
        case .quick: return 90
        case .standard: return 80
        case .high: return 65
        case .ultra: return 45
        }
    }

    // MARK: - SVG Settings

    var svgoMultipass: Bool {
        self != .quick
    }

    // MARK: - General

    var stripMetadata: Bool {
        self != .quick
    }

    /// Estimated relative speed (higher = slower)
    var estimatedTime: String {
        switch self {
        case .quick: return String(localized: "~1s/image")
        case .standard: return String(localized: "~3s/image")
        case .high: return String(localized: "~8s/image")
        case .ultra: return String(localized: "~20s/image")
        }
    }

    // MARK: - Step counts per format (for progress tracking)

    func totalSteps(for format: ImageFormat) -> Int {
        switch format {
        case .png:
            var steps = 1 // oxipng always
            if pngLossy && useGPU { steps += 1 } // GPU quantize
            if pngLossy { steps += 1 }            // pngquant
            if usePngcrush { steps += 1 }
            return steps
        case .jpeg:
            var steps = 0
            if jpegLossy && useGPU { steps += 1 } // GPU HW encode
            steps += 1 // mozjpeg jpegtran
            return steps
        case .heif:
            var steps = 0
            if heifLossy { steps += 1 }  // lossy
            steps += 1                    // lossless (always)
            return steps
        case .gif:
            return 1
        case .tiff:
            return 1
        case .avif:
            var steps = 0
            if avifLossy { steps += 1 }
            steps += 1  // max quality (always)
            return steps
        case .svg:
            return 1
        case .webp:
            return 1
        case .unknown:
            return 0
        }
    }
}
