# Gestion d'état — ImageArm

> Mis à jour le 2026-03-31

## Vue d'ensemble

ImageArm utilise le pattern **ObservableObject** natif de SwiftUI pour la gestion d'état, sans framework tiers (pas de Redux, Combine pipelines, etc.). L'état est centralisé dans deux stores principaux injectés via `@EnvironmentObject`.

## Stores principaux

### ImageStore (`Models/ImageStore.swift`)

**Rôle** : Store central de l'application. Gère la liste des fichiers, l'état de traitement, les préférences utilisateur et orchestre l'optimisation.

**Annotations** : `@MainActor final class ImageStore: ObservableObject`

| Propriété | Type | Mécanisme | Description |
|---|---|---|---|
| `files` | `[ImageFile]` | `@Published` | Liste des fichiers en cours de traitement |
| `showFilePicker` | `Bool` | `@Published` | Contrôle l'affichage du sélecteur de fichiers |
| `isProcessing` | `Bool` | `@Published` | Indique si un traitement est en cours |
| `level` | `OptimizationLevel` | `@Published` + UserDefaults | Niveau d'optimisation sélectionné (persisté) |
| `maxConcurrent` | `Int` | `@AppStorage` | Nombre max de tâches parallèles (défaut: 4) |
| `jpegLossyOverride` | `Bool` | `@AppStorage` | Override qualité JPEG lossy |
| `jpegQualityCustom` | `Double` | `@AppStorage` | Qualité JPEG personnalisée |
| `pngLossyOverride` | `Bool` | `@AppStorage` | Override qualité PNG lossy |
| `pngQualityCustom` | `Double` | `@AppStorage` | Qualité PNG personnalisée |
| `useCustomQuality` | `Bool` | `@AppStorage` | Active les réglages manuels |

**Propriétés calculées** : `totalOriginalSize`, `totalOptimizedSize`, `totalSavings`, `completedCount`

**Actions** : `addFiles(urls:)`, `optimizeAll()`, `stopAll()`, `clearCompleted()`, `clearAll()`, `removeFiles(_:)`, `reoptimize(_:)`

**Concurrence** : Utilise `TaskGroup` pour exécuter jusqu'à `maxConcurrent` optimisations en parallèle. La tâche est stockée dans `optimizationTask` pour permettre l'annulation via `stopAll()`.

### LogStore (`Models/LogStore.swift`)

**Rôle** : Singleton pour le journal d'activité de l'application.

**Annotations** : `@MainActor final class LogStore: ObservableObject`

| Propriété | Type | Mécanisme | Description |
|---|---|---|---|
| `entries` | `[LogEntry]` | `@Published` | Entrées du journal (max 500) |
| `isVisible` | `Bool` | `@Published` | Visibilité de la console |

**Accès global** : `LogStore.shared` (singleton), `optiLog()` (fonction globale helper)

### ImageFile (`Models/ImageFile.swift`)

**Rôle** : État observable par fichier.

**Annotations** : `@MainActor final class ImageFile: ObservableObject, Identifiable`

| Propriété | Type | Mécanisme | Description |
|---|---|---|---|
| `optimizedSize` | `Int64?` | `@Published` | Taille après optimisation |
| `status` | `OptimizationStatus` | `@Published` | État courant (pending/processing/done/failed) |

## Flux de données

```
ImageArmApp
  └─ @StateObject store = ImageStore()
      ├─ .environmentObject(store) → ContentView
      │   ├─ FileListView (lecture files, status)
      │   ├─ DropZoneView (pas d'accès direct au store)
      │   └─ StatusBarView (lecture totaux, isProcessing)
      ├─ .environmentObject(store) → SettingsView
      └─ .environmentObject(LogStore.shared) → LogConsoleView
```

## Persistance

- **UserDefaults** via `@AppStorage` : préférences utilisateur (niveau, qualité, concurrence)
- **Pas de base de données** : l'état des fichiers est transitoire (durée de la session)
- **Pas de cache** : les fichiers sont traités en place sur le disque

## Enum d'état : OptimizationStatus

```swift
enum OptimizationStatus: Equatable {
    case pending
    case processing(tool: String, step: Int, totalSteps: Int)
    case done(savedBytes: Int64)
    case alreadyOptimal
    case failed(String)
}
```

Propriétés calculées : `isComplete`, `progress` (0...1), `currentTool`, `stepInfo`

## Mode headless

L'application supporte un mode headless (`--headless`) détecté au lancement via `CommandLine.arguments`. Dans ce mode :
- L'`AppDelegate` traite les fichiers passés en arguments CLI
- Pas de fenêtre UI affichée
- Une notification macOS (`UNUserNotification`) est envoyée à la fin du traitement
- L'application quitte automatiquement après traitement

## Localisation

L'interface utilise `Localizable.xcstrings` pour la traduction en 5 langues (fr, en, de, nl, it). La langue de développement est l'anglais (`developmentRegion: en` dans `project.yml`), avec le français comme langue principale de l'UI.
