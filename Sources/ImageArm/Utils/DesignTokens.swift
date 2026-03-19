import SwiftUI

// MARK: - Couleurs par format

enum DesignTokens {
    enum FormatColor {
        static let png = Color.blue
        static let jpeg = Color.orange
        static let heif = Color.purple
        static let gif = Color.pink
        static let tiff = Color.indigo
        static let avif = Color.mint
        static let svg = Color.teal
        static let webp = Color.cyan
        static let unknown = Color.gray
    }

    enum StatusColor {
        static let success = Color.green
        static let error = Color.red
        static let warning = Color.orange
        static let pending = Color.secondary
        static let processing = Color.accentColor
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Couleur par ImageFormat

extension ImageFormat {
    var badgeColor: Color {
        switch self {
        case .png: return DesignTokens.FormatColor.png
        case .jpeg: return DesignTokens.FormatColor.jpeg
        case .heif: return DesignTokens.FormatColor.heif
        case .gif: return DesignTokens.FormatColor.gif
        case .tiff: return DesignTokens.FormatColor.tiff
        case .avif: return DesignTokens.FormatColor.avif
        case .svg: return DesignTokens.FormatColor.svg
        case .webp: return DesignTokens.FormatColor.webp
        case .unknown: return DesignTokens.FormatColor.unknown
        }
    }
}
