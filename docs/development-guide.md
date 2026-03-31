# Guide de développement — ImageArm

> Mis à jour le 2026-03-31

## Prérequis

| Outil | Version | Installation |
|---|---|---|
| macOS | 14.0+ (Sonoma) | — |
| Xcode / Command Line Tools | 15+ (Swift 5.9) | `xcode-select --install` |
| Homebrew | Dernière | [brew.sh](https://brew.sh) |

## Outils d'optimisation (optionnels mais recommandés)

Les outils CLI sont **embarqués dans le .app bundle** (compilés via `tools/Makefile`). Pas besoin de les installer via Homebrew pour l'utilisateur final.

Pour le développement, compiler les outils :
```bash
# Prérequis : Rust, Bun, CMake
brew install rust oven-sh/bun/bun cmake

# Compiler et signer
cd tools && make && make sign-tools && cd ..
```

| Outil | Format | Rôle |
|---|---|---|
| pngquant | PNG | Quantization lossy |
| oxipng | PNG | Recompression lossless |
| pngcrush | PNG | Sélection brute-force de filtres |
| cjpeg/jpegtran | JPEG | Recompression progressive (mozjpeg) |
| gifsicle | GIF | Optimisation GIF |
| svgo | SVG | Minification SVG |
| cwebp | WebP | Recompression WebP |

> Si un outil embarqué est absent, le ToolManager cherche aussi dans Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`) et le système en fallback. Les outils manquants sont silencieusement ignorés.

## Build

```bash
# Build debug (développement)
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm build

# Build release
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -configuration Release build
```

Le binaire se trouve dans `DerivedData/` (ou via Xcode : Product → Show Build Folder in Finder).

## Lancer l'application

```bash
# Via Xcode
# Ouvrir ImageArm.xcodeproj puis ⌘R

# Via le bundle .app (après Archive/Export depuis Xcode)
open ImageArm.app

# Ouvrir des fichiers directement
open -a ImageArm image.png dossier/
```

## Packaging (distribution)

Utiliser Xcode pour créer un Archive et l'exporter :

1. **Product → Archive** dans Xcode
2. Dans l'Organizer, sélectionner l'archive → **Distribute App**
3. Choisir le mode de distribution (Direct Distribution, Developer ID, etc.)
4. Xcode gère la signature, le bundle `.app`, et l'export

L'icône est gérée via `Sources/ImageArm/Assets.xcassets/AppIcon.appiconset/`.

## Installation des services système

```bash
# Finder Quick Action + CLI wrapper (~/.local/bin/imagearm)
./install-service.sh

# Ou seulement le service Automator
./install-finder-action.sh
```

Après installation :
- **Finder** : clic droit sur image(s) → Actions rapides → "Optimiser avec ImageArm"
- **CLI** : `imagearm image.png` (nécessite `~/.local/bin` dans le PATH)
- **Terminal** : `open -a ImageArm fichier.png`

## Structure du code

```
Sources/ImageArm/
├── ImageArmApp.swift          # Point d'entrée @main + AppDelegate
├── Models/                   # État et types de données
├── Services/                 # Logique métier (actor, GPU, outils)
├── Views/                    # Interface SwiftUI
└── Utils/                    # Utilitaires
```

Voir [Arborescence source](./source-tree-analysis.md) pour le détail complet.

## Conventions

- **Langue de l'UI** : multi-langues (fr, en, de, nl, it) via `Localizable.xcstrings`
- **Langue des logs** : français
- **Nommage** : conventions Swift standard (camelCase, PascalCase pour les types)
- **Concurrence** : `@MainActor` pour l'UI, `actor` pour les services, `Sendable` enforced
- **Logging** : `optiLog()` (fonction globale → `LogStore.shared`)
- **Tests unitaires** : 9 fichiers dans `Tests/ImageArmTests/` (formats, optimizer, store, headless, etc.)

## Architecture décisionnelle

| Décision | Choix | Raison |
|---|---|---|
| Pas de sandbox | Modification fichiers in-place | Nécessite accès libre au système de fichiers |
| Pas de dépendances externes | Zéro dépendance | Frameworks Apple suffisants, simplicité |
| Actor pour l'optimizer | Swift actor | Isolation concurrence pour les processus externes |
| Metal inline shaders | String source compilée runtime | Évite la complexité d'un bundle .metallib |
| Pipeline compétitif | keepBest() | Le plus petit résultat gagne, maximise la compression |
| Outils CLI optionnels | Graceful degradation | L'app reste fonctionnelle sans outils installés |

## Notarisation (distribution hors App Store)

```bash
xcrun notarytool submit ImageArm-1.0.0.dmg \
    --apple-id VOTRE@EMAIL \
    --team-id TEAMID \
    --password APP_PASSWORD \
    --wait

xcrun stapler staple ImageArm-1.0.0.dmg
```
