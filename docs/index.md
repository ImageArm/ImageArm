# ImageArm — Index de la documentation projet

> Mis à jour le 2026-03-31 | Swift 5.9 / SwiftUI / macOS 14+

## Vue rapide

| Attribut | Valeur |
|---|---|
| **Type** | Monolithe — application desktop macOS |
| **Langage** | Swift 5.9 |
| **Framework** | SwiftUI (macOS 14+ Sonoma) |
| **Architecture** | MVVM simplifié + Services Actor + Pipeline compétitif |
| **GPU** | Metal compute shaders + hardware JPEG/HEIF/AVIF encoder |
| **Point d'entrée** | `Sources/ImageArm/ImageArmApp.swift` |
| **Dépendances** | Zéro (frameworks Apple uniquement) |
| **Outils CLI embarqués** | pngquant, oxipng, pngcrush, mozjpeg (cjpeg/jpegtran), gifsicle, svgo, cwebp |
| **Localisation** | 5 langues (fr, en, de, nl, it) |

## Documentation générée

- [Vue d'ensemble du projet](./project-overview.md) — Description, fonctionnalités, structure
- [Architecture](./architecture.md) — Architecture technique, pipelines d'optimisation, GPU Metal, concurrence
- [Arborescence source](./source-tree-analysis.md) — Arbre annoté, répertoires critiques, statistiques
- [Gestion d'état](./state-management.md) — Stores SwiftUI, flux de données, persistance
- [Composants UI](./ui-component-inventory.md) — Inventaire complet des vues et sous-composants
- [Guide de développement](./development-guide.md) — Build, run, packaging, installation, conventions

## Documentation existante

- [CLAUDE.md](../CLAUDE.md) — Instructions pour Claude Code (guide du projet)

## Pour démarrer

```bash
# Build
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm build

# Build release
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -configuration Release build

# Compiler les outils CLI embarqués (nécessite Rust, Bun, CMake)
cd tools && make && make sign-tools && cd ..

# Packaging : utiliser Product → Archive dans Xcode

# Installer le service Finder + CLI
./install-finder-action.sh

# Lancer les tests
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm test
```
