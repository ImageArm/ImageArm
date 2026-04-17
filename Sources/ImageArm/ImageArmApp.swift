import SwiftUI
import UserNotifications

/// Détection headless au niveau global (avant init App)
private let isHeadless = CommandLine.arguments.contains("--headless")

@main
struct ImageArmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ImageStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if isHeadless {
                    // Mode headless : pas de contenu — AppDelegate gère tout
                    Color.clear
                        .frame(width: 0, height: 0)
                        .onAppear { NSApp.windows.forEach { $0.close() } }
                } else {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(LogStore.shared)
                        .frame(minWidth: 700, minHeight: 400)
                        .onAppear {
                            appDelegate.store = store
                            appDelegate.processPendingFiles()
                        }
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ajouter des images…") {
                    store.showFilePicker = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(LogStore.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: ImageStore?
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Intercept kAEOpenDocuments before SwiftUI's handler creates one window per file
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocumentsEvent(_:replyEvent:)),
            forEventClass: 0x61657674,  // kCoreEventClass 'aevt'
            andEventID: 0x6F646F63      // kAEOpenDocuments 'odoc'
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isHeadless {
            NSApp.setActivationPolicy(.prohibited)
            Task { @MainActor in
                await runHeadless()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isHeadless
    }

    /// Called when files are opened via `open -a ImageArm file.png` or Finder double-click
    func application(_ application: NSApplication, open urls: [URL]) {
        let imageURLs = filterImageURLs(urls)
        guard !imageURLs.isEmpty else { return }

        optiLog(String(localized: "Ouverture: \(imageURLs.count) fichier(s)"), level: .info)

        if let store = store {
            Task { @MainActor in
                store.addFiles(urls: imageURLs)
                store.optimizeAll()
            }
        } else {
            pendingURLs.append(contentsOf: imageURLs)
        }
    }

    @MainActor
    func processPendingFiles() {
        guard !pendingURLs.isEmpty, let store = store else { return }
        let urls = pendingURLs
        pendingURLs = []
        store.addFiles(urls: urls)
        store.optimizeAll()
    }

    // MARK: - Apple Event handler

    @objc private func handleOpenDocumentsEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: 0x2D2D2D2D) else { return } // keyDirectObject '----'
        let count = list.numberOfItems
        let descriptors = count > 0 ? (1...count).compactMap { list.atIndex($0) } : [list]
        let urls = descriptors.compactMap { urlFromDescriptor($0) }
        guard !urls.isEmpty else { return }
        application(NSApplication.shared, open: urls)
    }

    private func urlFromDescriptor(_ descriptor: NSAppleEventDescriptor) -> URL? {
        // Try coercing to file URL (modern macOS)
        if let coerced = descriptor.coerce(toDescriptorType: 0x6675726C),  // typeFileURL 'furl'
           let str = String(data: coerced.data, encoding: .utf8),
           let url = URL(string: str) {
            return url
        }
        // Fallback: string value as POSIX path
        if let path = descriptor.stringValue, !path.isEmpty {
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
        }
        return nil
    }

    // MARK: - Headless mode

    @MainActor
    private func runHeadless() async {
        let args = CommandLine.arguments
        let files = args.drop(while: { $0 != "--headless" }).dropFirst()
        let urls = files.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            return url.hasDirectoryPath || ImageStore.supportedExtensions.contains(url.pathExtension.lowercased()) ? url : nil
        }

        guard !urls.isEmpty else {
            optiLog("Headless : aucun fichier image trouvé dans les arguments", level: .error)
            exit(1)
        }

        optiLog("Headless : \(urls.count) fichier(s) à optimiser", level: .info)

        let store = ImageStore()
        store.addFiles(urls: urls)

        let pending = store.files.filter { $0.status == .pending }
        guard !pending.isEmpty else {
            optiLog("Headless : aucun fichier à traiter après filtrage", level: .error)
            exit(1)
        }

        let optimizer = ImageOptimizer()
        let level = store.level

        let maxConc = store.maxConcurrent
        await withBoundedConcurrency(over: pending, maxConcurrent: maxConc) { file in
            await optimizer.optimize(file: file, level: level)
        }

        // Résumé
        let totalFiles = store.files.count
        let doneFiles = store.files.filter { $0.status.isComplete }.count
        let totalSaved = store.totalSavings
        let hasErrors = store.files.contains { if case .failed = $0.status { return true } else { return false } }

        let formattedSaved = ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file)
        let summary = "\(doneFiles)/\(totalFiles) fichiers optimisés — \(formattedSaved) économisés"
        optiLog("Headless : \(summary)", level: hasErrors ? .warning : .success)

        // Notification macOS
        await sendNotification(title: "ImageArm", body: summary)

        exit(hasErrors ? 1 : 0)
    }

    private func sendNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)

        // Attendre un peu pour que la notification s'affiche avant exit
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: - Helpers

    private func filterImageURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            if url.hasDirectoryPath { return true }
            return ImageStore.supportedExtensions.contains(url.pathExtension.lowercased())
        }
    }
}
