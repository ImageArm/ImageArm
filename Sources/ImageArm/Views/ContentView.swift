import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: ImageStore
    @EnvironmentObject var logStore: LogStore
    @State private var selection = Set<ImageFile.ID>()
    @State private var isDragOver = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var autoScrollEnabled = true
    @State private var lastAutoScrolledID: ImageFile.ID?
    @State private var scrollToRow: Int?

    var body: some View {
        VStack(spacing: 0) {
            if store.files.isEmpty {
                DropZoneView(isDragOver: $isDragOver)
                    .overlay {
                        if !hasSeenWelcome {
                            WelcomeOverlay(hasSeenWelcome: $hasSeenWelcome)
                        }
                    }
            } else {
                // BatchWelcomeBanner quand des fichiers sont en attente
                if !store.isProcessing, store.files.contains(where: { $0.status == .pending }) {
                    HStack {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.secondary)
                        Text("\(store.files.count) images — prêt à optimiser")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.08))
                }

                if logStore.isVisible {
                    VSplitView {
                        FileListView(selection: $selection, scrollToRow: $scrollToRow)
                            .frame(minHeight: 150)
                        LogConsoleView()
                            .frame(minHeight: 100, idealHeight: 180)
                    }
                } else {
                    FileListView(selection: $selection, scrollToRow: $scrollToRow)
                }
                StatusBarView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("Niveau", selection: $store.level) {
                    ForEach(OptimizationLevel.allCases) { level in
                        Label(level.name, systemImage: level.icon)
                            .tag(level)
                    }
                }
                .pickerStyle(.menu)
                .help("Niveau d'optimisation")

                Text(store.level.lossIndicator)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())

                Toggle(isOn: $logStore.isVisible) {
                    Label("Console", systemImage: "terminal")
                }
                .help("Afficher/masquer la console")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = URL(string: "https://ko-fi.com/imagearm") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.42, blue: 0.21),
                                        Color(red: 0.88, green: 0.18, blue: 0.72),
                                        Color(red: 0.44, green: 0.28, blue: 0.98)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(store.donationDone ? "Merci ♥" : "Soutenir")
                    }
                }
                .buttonStyle(.bordered)
                .help("Soutenir ImageArm sur Ko-fi")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showFilePicker = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .help("Ajouter des images à optimiser")

                Button {
                    store.optimizeAll()
                } label: {
                    Label("Optimiser", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isProcessing || store.files.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Lancer l'optimisation (⌘↩)")

                if store.isProcessing {
                    Button {
                        store.stopAll()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Arrêter l'optimisation en cours")
                }

                Button {
                    store.clearAll()
                } label: {
                    Label("Vider", systemImage: "trash")
                }
                .disabled(store.files.isEmpty)
                .help("Vider la liste des images")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            let hasFiles = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            if hasFiles { handleDrop(providers) }
            return hasFiles
        }
        .fileImporter(
            isPresented: $store.showFilePicker,
            allowedContentTypes: ImageStore.supportedTypes + [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.addFiles(urls: urls)
                if !store.isProcessing {
                    store.optimizeAll()
                }
            }
        }
        .onChange(of: store.firstProcessingFileID) { _, newID in
            guard autoScrollEnabled, let newID else { return }
            lastAutoScrolledID = newID
            selection = [newID]
            if let index = store.files.firstIndex(where: { $0.id == newID }) {
                scrollToRow = index
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue.isEmpty {
                autoScrollEnabled = true
            } else if let lastID = lastAutoScrolledID, newValue == [lastID] {
                // User selected the same file auto-scroll picked — keep auto-scroll
            } else {
                autoScrollEnabled = false
            }
        }
        .onChange(of: store.isProcessing) { _, newValue in
            if newValue {
                autoScrollEnabled = true
                lastAutoScrolledID = nil
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .alert("Merci d'utiliser ImageArm ♥", isPresented: $store.showDonationPrompt) {
            Button("Faire un don ♥") {
                if let url = URL(string: "https://ko-fi.com/imagearm"),
                   NSWorkspace.shared.open(url) {
                    store.donationDone = true
                }
            }
            Button("Plus tard", role: .cancel) { }
        } message: {
            let n = store.donationTriggerCompletedCount
            Text("Tu viens d'optimiser \(n) image\(n > 1 ? "s" : "") pour \(FileSizeFormatter.format(store.donationTriggerTotalSavings)) économisés. Si ImageArm te fait gagner du temps, un petit don sur Ko-fi nous aide beaucoup !")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }
            store.addFiles(urls: urls)
            store.optimizeAll()
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }
}
