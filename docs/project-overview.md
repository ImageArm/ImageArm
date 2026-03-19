# Vue d'ensemble du projet — PngOpti

> Généré le 2026-03-11 | Scan exhaustif

## Description

ImageArm est une application macOS native (SwiftUI) qui optimise des images en lot (PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG, WebP) en utilisant un pipeline de compétition entre outils CLI externes et accélération GPU Metal. L'interface est en français.

## Résumé technique

| Attribut | Valeur |
|---|---|
| **Type** | Application desktop macOS |
| **Langage** | Swift 5.9 |
| **Framework** | SwiftUI (macOS 14+ / Sonoma) |
| **Architecture** | Monolithe, MVVM simplifié + Services Actor |
| **Dépendances** | Zéro (frameworks Apple uniquement) |
| **GPU** | Metal compute shaders + hardware JPEG encoder |
| **Outils CLI** | pngquant, oxipng, pngcrush, mozjpeg, gifsicle, svgo, cwebp, tiffutil (macOS natif) |
| **Packaging** | Xcode project (PngOpti.xcodeproj) → Archive/Export → .app bundle |

## Fonctionnalités principales

1. **Optimisation multi-format** : PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG, WebP
2. **Pipeline compétitif** : plusieurs outils s'exécutent et le plus petit résultat gagne
3. **4 niveaux d'optimisation** : Rapide, Standard, Maximum, Ultra
4. **Accélération GPU Metal** : quantization PNG par compute shader, encodage JPEG hardware
5. **Traitement en lot** : drag-and-drop, file picker, dossiers récursifs
6. **Concurrence configurable** : 2 à 16 optimisations simultanées (TaskGroup)
7. **Qualité personnalisable** : override lossy/lossless, sliders qualité PNG/JPEG
8. **Console de logs** : journal d'activité temps réel intégré avec copie presse-papier en un clic
9. **Intégration Finder** : Quick Action (clic droit) + CLI wrapper
10. **Modification in-place** : remplacement atomique avec backup → trash

## Structure du dépôt

| Répertoire/Fichier | Rôle |
|---|---|
| `Sources/PngOpti/` | Code source Swift (16 fichiers) |
| `Sources/PngOpti/Models/` | Modèles de données et état (5 fichiers) |
| `Sources/PngOpti/Services/` | Logique métier : optimizer, GPU, tool manager (3 fichiers) |
| `Sources/PngOpti/Views/` | Interface SwiftUI (6 fichiers) |
| `Sources/PngOpti/Utils/` | Utilitaires (1 fichier) |
| `project.yml` | Configuration xcodegen (génère PngOpti.xcodeproj) |
| `PngOpti.xcodeproj` | Projet Xcode (généré par xcodegen) |
| `Info.plist` | Info.plist de l'application (racine du projet) |
| `PngOpti.entitlements` | Entitlements macOS (pas de sandbox, GPU) |
| `install-service.sh` | Installation Finder Quick Action + CLI |
| `install-finder-action.sh` | Installation service Automator |
| `Sources/PngOpti/Assets.xcassets/` | Ressources (icônes, assets) |

## Liens vers la documentation détaillée

- [Architecture](./architecture.md) — Architecture technique détaillée, pipelines, GPU, concurrence
- [Arborescence source](./source-tree-analysis.md) — Arbre annoté et répertoires critiques
- [Gestion d'état](./state-management.md) — Stores, flux de données, persistance
- [Composants UI](./ui-component-inventory.md) — Inventaire complet des vues SwiftUI
- [Guide de développement](./development-guide.md) — Build, run, déploiement, outils requis
