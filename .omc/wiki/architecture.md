---
title: Architecture ImageArm
category: architecture
tags: [architecture, pipeline, swiftui, metal]
updated: 2026-04-17
---

# Architecture ImageArm

App macOS SwiftUI (macOS 14+) qui optimise des images en batch via un pipeline de CLI externes et Metal GPU.

## Couches principales

| Couche | Fichiers clés | Rôle |
|--------|--------------|------|
| Models | `ImageFile`, `ImageStore`, `OptimizationLevel` | État observable, store central `@MainActor` |
| Services | `ImageOptimizer`, `ToolManager`, `GPUProcessor` | Pipeline d'optimisation, outils CLI, GPU Metal |
| Views | `ContentView`, `FileListView`, `DropZoneView` | UI drag-and-drop, liste fichiers, barre de statut |

## Pipeline d'optimisation

Chaque format passe par plusieurs outils en séquence — le plus petit résultat gagne :

- **PNG** : pngquant → oxipng
- **JPEG** : GPU (hardware encode) → mozjpeg/jpegtran
- **HEIF** : GPU lossy → GPU max quality
- **GIF** : gifsicle (lossless ou lossy selon niveau)
- **TIFF** : tiffutil -lzw (natif macOS)
- **AVIF** : ImageIO natif (macOS 14+)
- **SVG** : svgo
- **WebP** : cwebp

## Gestion des fichiers externes (AppDelegate)

Les fichiers sont reçus via `application(_:open:)`. Pour éviter que SwiftUI `WindowGroup` crée une fenêtre par fichier, `kAEOpenDocuments` est intercepté dans `applicationWillFinishLaunching`. Voir [[bugs-connus#multi-fenetres]].

## Distribution

- App : GitHub Releases (DMG `ImageArm-X.Y.Z.dmg`)
- Homebrew Cask : `imagearm/tap/imagearm`
- CLI headless : `imagearm --headless fichier.png`
- Quick Action Finder : workflow Automator installé via `install-finder-action.sh`
