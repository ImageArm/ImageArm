import Foundation

struct FileSizeFormatter {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    static func formatSavings(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        return "-\(format(bytes))"
    }
}
