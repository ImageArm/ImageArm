import SwiftUI

struct LogConsoleView: View {
    @EnvironmentObject var logStore: LogStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Console")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(logStore.entries.count) lignes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    logStore.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(logStore.entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: logStore.entries.count) { _, _ in
                    if let last = logStore.entries.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.formattedTime)
                .foregroundStyle(.tertiary)
                .frame(width: 85, alignment: .leading)

            Image(systemName: entry.level.icon)
                .font(.system(size: 9))
                .foregroundStyle(iconColor)
                .frame(width: 12)

            Text(entry.message)
                .foregroundStyle(textColor)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var iconColor: Color {
        switch entry.level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .gpu: return .purple
        }
    }

    private var textColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        default: return .primary
        }
    }
}
