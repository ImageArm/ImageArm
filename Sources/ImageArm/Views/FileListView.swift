import SwiftUI
import AppKit

// MARK: - NSTableView Introspection Helper

private struct TableScrollHelper: NSViewRepresentable {
    var scrollToRow: Int?
    var onReset: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let row = scrollToRow, row >= 0 else { return }
        DispatchQueue.main.async {
            if let tableView = Self.findNSTableView(from: nsView) {
                tableView.scrollRowToVisible(row)
            }
            onReset()
        }
    }

    private static func findNSTableView(from view: NSView) -> NSTableView? {
        var current: NSView? = view.superview
        var depth = 0
        while let v = current, depth < 20 {
            if let found = findNSTableView(in: v) {
                return found
            }
            current = v.superview
            depth += 1
        }
        return nil
    }

    private static func findNSTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let found = findNSTableView(in: subview) {
                return found
            }
        }
        return nil
    }
}

struct FileListView: View {
    @EnvironmentObject var store: ImageStore
    @Binding var selection: Set<ImageFile.ID>
    @Binding var scrollToRow: Int?

    var body: some View {
        Table(store.files, selection: $selection) {
            TableColumn("") { file in
                StatusIcon(file: file)
                    .frame(width: 20)
            }
            .width(28)

            TableColumn("Nom") { file in
                HStack(spacing: 8) {
                    FormatBadge(format: file.format)
                    Text(file.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Original") { file in
                Text(FileSizeFormatter.format(file.originalSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Progression") { file in
                ProgressCell(file: file)
            }
            .width(min: 140, ideal: 180)

            TableColumn("Optimisé") { file in
                OptimizedCell(file: file)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Gain") { file in
                SavingsCell(file: file)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: ImageFile.ID.self) { ids in
            if !ids.isEmpty {
                Button("Supprimer") { store.removeFiles(ids) }
                Button("Ré-optimiser") {
                    for file in store.files where ids.contains(file.id) {
                        store.reoptimize(file)
                    }
                }
                Divider()
                Button("Afficher dans le Finder") {
                    if let file = store.files.first(where: { ids.contains($0.id) }) {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                }
            }
        } primaryAction: { ids in
            if let file = store.files.first(where: { ids.contains($0.id) }) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        }
        .alternatingRowBackgrounds(.enabled)
        .background {
            TableScrollHelper(scrollToRow: scrollToRow) {
                scrollToRow = nil
            }
        }
    }
}

// MARK: - Progress Cell

struct ProgressCell: View {
    @ObservedObject var file: ImageFile

    var body: some View {
        switch file.status {
        case .pending:
            HStack(spacing: 6) {
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                Text("En attente")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .processing(let tool, let step, let totalSteps):
            HStack(spacing: 6) {
                ProgressView(value: Double(step - 1) + 0.5, total: Double(totalSteps))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                Text("\(tool) \(step)/\(totalSteps)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .done:
            HStack(spacing: 6) {
                ProgressView(value: 1)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        case .alreadyOptimal:
            HStack(spacing: 6) {
                ProgressView(value: 1)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text("optimal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            HStack(spacing: 6) {
                ProgressView(value: 1)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(msg)
            }
        }
    }
}

// MARK: - Status Icon

struct StatusIcon: View {
    @ObservedObject var file: ImageFile

    var body: some View {
        switch file.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .font(.caption)
        case .processing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .alreadyOptimal:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }
}

// MARK: - Format Badge

struct FormatBadge: View {
    let format: ImageFormat

    var body: some View {
        Text(format.displayName)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Format \(format.displayName)")
    }

    private var badgeColor: Color {
        format.badgeColor
    }
}

// MARK: - Optimized Cell

struct OptimizedCell: View {
    @ObservedObject var file: ImageFile

    var body: some View {
        if let size = file.optimizedSize {
            Text(FileSizeFormatter.format(size))
                .monospacedDigit()
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Savings Cell

struct SavingsCell: View {
    @ObservedObject var file: ImageFile

    var body: some View {
        if let savings = file.savings, let saved = file.savedBytes {
            HStack(spacing: 4) {
                Text(String(format: "%.1f%%", savings))
                    .monospacedDigit()
                    .foregroundStyle(savings > 10 ? .green : savings > 0 ? .primary : .secondary)
                    .fontWeight(savings > 10 ? .medium : .regular)
                Text("(\(FileSizeFormatter.formatSavings(saved)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if case .alreadyOptimal = file.status {
            Text("optimal")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else if case .failed(let msg) = file.status {
            Text(msg)
                .foregroundStyle(.orange)
                .font(.caption)
                .lineLimit(1)
                .help(msg)
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }
}
