import Foundation

final class ToolManager: Sendable {
    struct ToolInfo: Sendable {
        let name: String
        let path: String?
        let installCommand: String

        var isAvailable: Bool { path != nil }
    }

    // MARK: - Détection bundle vs dev

    private static let isBundle: Bool = {
        Bundle.main.executableURL?.pathComponents
            .contains(where: { $0.hasSuffix(".app") }) ?? false
    }()

    private static let bundleBinDir: String? = {
        Bundle.main.executableURL?.deletingLastPathComponent().path
    }()

    // MARK: - Chemins de recherche

    private static let devSearchPaths: [String] = {
        let toolsBin = FileManager.default.currentDirectoryPath + "/tools/bin"
        return [
            toolsBin,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/opt/homebrew/opt/mozjpeg/bin",
            "/usr/local/opt/mozjpeg/bin",
            "/opt/local/opt/mozjpeg/bin",
        ]
    }()

    private let pathCache: [String: String]

    // MARK: - Init

    init() {
        let names = ["pngquant", "oxipng", "pngcrush",
                     "cjpeg", "jpegtran", "svgo", "cwebp",
                     "gifsicle", "tiffutil"]
        var cache: [String: String] = [:]
        for name in names {
            if let path = Self.resolvePath(name) {
                cache[name] = path
            }
        }
        self.pathCache = cache

        optiLog("ToolManager : mode \(Self.isBundle ? "bundle" : "dev"), \(cache.count) outils trouvés", level: .info)
        for (name, path) in cache.sorted(by: { $0.key < $1.key }) {
            optiLog("  \(name) → \(path)", level: .info)
        }
    }

    // MARK: - API publique

    func find(_ name: String) -> String? {
        pathCache[name]
    }

    func findMozJpegTran() -> String? {
        pathCache["jpegtran"]
    }

    func allTools() -> [ToolInfo] {
        [
            ToolInfo(name: "pngquant",        path: find("pngquant"),  installCommand: "brew install pngquant"),
            ToolInfo(name: "oxipng",           path: find("oxipng"),    installCommand: "brew install oxipng"),
            ToolInfo(name: "pngcrush",         path: find("pngcrush"),  installCommand: "brew install pngcrush"),
            ToolInfo(name: "cjpeg (mozjpeg)",  path: find("cjpeg"),     installCommand: "brew install mozjpeg"),
            ToolInfo(name: "jpegtran (mozjpeg)", path: find("jpegtran"), installCommand: "brew install mozjpeg"),
            ToolInfo(name: "svgo",             path: find("svgo"),      installCommand: "npm install -g svgo"),
            ToolInfo(name: "cwebp",            path: find("cwebp"),     installCommand: "brew install webp"),
            ToolInfo(name: "gifsicle",         path: find("gifsicle"),  installCommand: "brew install gifsicle"),
            ToolInfo(name: "gifsicle",         path: find("gifsicle"),  installCommand: "brew install gifsicle"),
            ToolInfo(name: "tiffutil",         path: find("tiffutil"),  installCommand: "(intégré macOS)"),
        ]
    }

    // MARK: - Résolution de chemins (dual-mode)

    private static func resolvePath(_ name: String) -> String? {
        // Mode bundle : chercher dans Contents/MacOS/ d'abord
        if isBundle, let dir = bundleBinDir {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback dev (ou bundle si non trouvé dans Contents/MacOS/)
        for dir in devSearchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
