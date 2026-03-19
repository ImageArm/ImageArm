import SwiftUI
import AppKit

struct StatusBarView: View {
    @EnvironmentObject var store: ImageStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isProcessing {
                // Mode progression
                ProgressView(value: globalProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack(spacing: DesignTokens.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text("\(store.completedCount)/\(store.files.count) fichiers")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let current = currentProcessingInfo {
                        Text(current)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    sizeInfo
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
            } else if store.totalSavings > 0 {
                // Mode résultat — chiffre héros
                HStack(spacing: DesignTokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FileSizeFormatter.format(store.totalSavings))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(DesignTokens.StatusColor.success)
                        Text("\(store.completedCount) fichiers optimisés")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    sizeInfo

                    // CopyResultButton
                    Button {
                        let summary = resultSummary
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Copier le résumé dans le presse-papiers")
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(Color.green.opacity(0.15))
            } else {
                // Mode par défaut
                HStack {
                    Text("\(store.files.count) fichiers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    sizeInfo
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
        .background(.bar)
    }

    // MARK: - Composants

    private var sizeInfo: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(FileSizeFormatter.format(store.totalOriginalSize))
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(FileSizeFormatter.format(store.totalOptimizedSize))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)

            if store.totalSavings > 0 {
                let pct = store.totalOriginalSize > 0
                    ? Double(store.totalSavings) / Double(store.totalOriginalSize) * 100
                    : 0
                Text(String(format: "(%.1f%%)", pct))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.success)
            }
        }
    }

    // MARK: - Helpers

    private var globalProgress: Double {
        let total = store.files.count
        guard total > 0 else { return 0 }
        var progress = 0.0
        for file in store.files {
            progress += file.status.progress
        }
        return progress / Double(total)
    }

    private var currentProcessingInfo: String? {
        let processing = store.files.filter {
            if case .processing = $0.status { return true }
            return false
        }
        guard !processing.isEmpty else { return nil }
        if processing.count == 1, let info = processing.first?.status.stepInfo {
            return info
        }
        return String(localized: "\(processing.count) en cours")
    }

    private var resultSummary: String {
        let saved = FileSizeFormatter.format(store.totalSavings)
        let pct = store.totalOriginalSize > 0
            ? Double(store.totalSavings) / Double(store.totalOriginalSize) * 100
            : 0
        return "ImageArm : \(store.completedCount) fichiers optimisés, \(saved) économisés (\(String(format: "%.1f%%", pct)))"
    }
}
