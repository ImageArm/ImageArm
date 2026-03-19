import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel {
        case info, success, warning, error, gpu

        var icon: String {
            switch self {
            case .info: return "arrow.right"
            case .success: return "checkmark"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .gpu: return "gpu"
            }
        }

        var color: String {
            switch self {
            case .info: return "secondary"
            case .success: return "green"
            case .warning: return "orange"
            case .error: return "red"
            case .gpu: return "purple"
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }
}

@MainActor
final class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isVisible = false

    static let shared = LogStore()

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)
        // Keep last 500 entries
        if entries.count > 500 {
            entries = Array(entries.suffix(500))
        }
    }

    func clear() {
        entries.removeAll()
    }
}

// Global helper to log from anywhere
func optiLog(_ message: String, level: LogEntry.LogLevel = .info) {
    Task { @MainActor in
        LogStore.shared.log(message, level: level)
    }
}
