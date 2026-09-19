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
        // Barre d'outils personnalisable : l'identifiant active la feuille
        // « Personnaliser la barre d'outils… » et l'autosauvegarde AppKit.
        //
        // ⚠️ Deux règles à ne jamais casser ici :
        //  1. AUCUN item conditionnel (`if`, `ForEach` sur une collection
        //     mutable). Une appartenance qui apparaît/disparaît casse
        //     l'identité de personnalisation et fait planter SwiftUI
        //     (FB15513599, non corrigé). Utiliser `.disabled()` à la place.
        //  2. Chaque item expose un `Label` titre + icône, sinon il s'affiche
        //     vide dans la palette et dans les modes « Icône seule » /
        //     « Texte seul ».
        .toolbar(id: ToolbarItemID.toolbarID) {
            ToolbarItem(id: ToolbarItemID.level.rawValue, placement: .automatic) {
                // Un Picker `.menu` en toolbar n'affiche que l'icône du Label :
                // le niveau sélectionné devenait invisible. Un Menu explicite
                // permet de montrer le nom, et l'indicateur de perte descend
                // dans les entrées où il sert à choisir.
                Menu {
                    Picker("Niveau", selection: $store.level) {
                        ForEach(OptimizationLevel.allCases) { level in
                            // Un Picker de menu aplatit chaque entrée à son libellé
                            // principal : un Text secondaire serait ignoré, d'où
                            // l'indicateur fusionné dans le titre.
                            Label("\(level.name) — \(level.lossIndicator)", systemImage: level.icon)
                                .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    // .titleAndIcon est indispensable : sans lui, SwiftUI réduit
                    // le Label à sa seule icône dans une toolbar.
                    Label(store.level.name, systemImage: store.level.icon)
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Niveau d'optimisation — \(store.level.lossIndicator)")
            }

            ToolbarItem(id: ToolbarItemID.console.rawValue, placement: .automatic) {
                Toggle(isOn: $logStore.isVisible) {
                    Label("Console", systemImage: "terminal")
                }
                .help("Afficher/masquer la console")
            }

            ToolbarItem(id: ToolbarItemID.donate.rawValue, placement: .primaryAction) {
                Button {
                    if let url = URL(string: "https://ko-fi.com/imagearm") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    // Label(title:icon:) et non un HStack : la palette de
                    // personnalisation a besoin d'un titre et d'une icône
                    // distincts. Le dégradé reste porté par l'icône.
                    Label {
                        Text(store.donationDone ? "Merci ♥" : "Soutenir")
                    } icon: {
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
                    }
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .help("Soutenir ImageArm sur Ko-fi")
            }

            ToolbarItem(id: ToolbarItemID.add.rawValue, placement: .primaryAction) {
                Button {
                    store.showFilePicker = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .help("Ajouter des images à optimiser")
            }
            .customizationBehavior(.reorderable)

            // Optimiser et Stop fusionnés en un seul item toujours présent :
            // les deux états sont mutuellement exclusifs, et un item construit
            // conditionnellement est interdit dans une barre personnalisable.
            ToolbarItem(id: ToolbarItemID.run.rawValue, placement: .primaryAction) {
                Button {
                    if store.isProcessing {
                        store.stopAll()
                    } else {
                        store.optimizeAll()
                    }
                } label: {
                    Label(store.isProcessing ? "Stop" : "Optimiser",
                          systemImage: store.isProcessing ? "stop.fill" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canStop && !store.canOptimize)
                // ⌘↩ vit désormais dans le menu Optimisation : un raccourci
                // porté par un bouton de barre d'outils meurt avec elle.
                .help(store.isProcessing
                      ? "Arrêter l'optimisation en cours"
                      : "Lancer l'optimisation (⌘↩)")
            }
            .customizationBehavior(.reorderable)

            ToolbarItem(id: ToolbarItemID.clear.rawValue, placement: .primaryAction) {
                Button {
                    store.clearAll()
                } label: {
                    Label("Vider", systemImage: "trash")
                }
                .disabled(!store.canClear)
                .help("Vider la liste des images")
            }

            // Masqués par défaut : disponibles dans « Personnaliser la barre
            // d'outils… » pour ceux qui en ont besoin, zéro coût visuel sinon.
            ToolbarItem(id: ToolbarItemID.clearCompleted.rawValue,
                        placement: .primaryAction,
                        showsByDefault: false) {
                Button {
                    store.clearCompleted()
                } label: {
                    Label("Vider les terminés", systemImage: "checkmark.circle")
                }
                .disabled(!store.canClearCompleted)
                .help("Retirer de la liste les images déjà optimisées")
            }

            ToolbarItem(id: ToolbarItemID.settings.rawValue,
                        placement: .primaryAction,
                        showsByDefault: false) {
                SettingsLink {
                    Label("Réglages…", systemImage: "gearshape")
                }
                .help("Ouvrir les réglages d'ImageArm")
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
