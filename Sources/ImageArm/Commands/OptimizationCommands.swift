import SwiftUI
import AppKit

/// Miroir, dans la barre des menus, de toutes les actions de la barre d'outils.
///
/// Indispensable depuis que la barre d'outils peut être masquée (⌥⌘T) ou vidée
/// via « Personnaliser la barre d'outils… » : sans ce miroir, Optimiser, Stop,
/// Vider, le niveau et la console deviendraient inatteignables. C'est aussi ici
/// que vit ⌘↩ — un `keyboardShortcut` porté par un bouton de barre d'outils ne
/// vit que tant que ce bouton est rendu.
///
/// Le store est injecté explicitement : un type `Commands` ne reçoit pas les
/// `environmentObject` de la scène, et `@ObservedObject` est ce qui permet aux
/// états `disabled` de se rafraîchir.
struct OptimizationCommands: Commands {
    @ObservedObject var store: ImageStore
    @ObservedObject var logStore: LogStore

    var body: some Commands {
        CommandMenu("Optimisation") {
            Button("Optimiser tout") {
                store.optimizeAll()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!store.canOptimize)

            Button("Arrêter l'optimisation") {
                store.stopAll()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!store.canStop)

            Divider()

            Picker("Niveau d'optimisation", selection: $store.level) {
                ForEach(OptimizationLevel.allCases) { level in
                    Text("\(level.name) — \(level.lossIndicator)").tag(level)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Vider la liste") {
                store.clearAll()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(!store.canClear)

            Button("Vider les terminés") {
                store.clearCompleted()
            }
            .disabled(!store.canClearCompleted)
        }

        // Menu Présentation, juste après « Masquer la barre d'outils » et
        // « Personnaliser la barre d'outils… » fournis par ToolbarCommands().
        CommandGroup(after: .toolbar) {
            Button(logStore.isVisible ? "Masquer la console" : "Afficher la console") {
                logStore.isVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        // Menu ImageArm, juste après « À propos d'ImageArm ».
        CommandGroup(after: .appInfo) {
            Button("Soutenir ImageArm ♥") {
                if let url = URL(string: "https://ko-fi.com/imagearm") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
