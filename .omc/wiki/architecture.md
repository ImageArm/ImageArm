---
title: Architecture ImageArm
category: architecture
tags: [architecture, pipeline, swiftui, metal]
updated: 2026-09-19
---

# Architecture ImageArm

App macOS SwiftUI (macOS 14+) qui optimise des images en batch via un pipeline de CLI externes et Metal GPU.

## Couches principales

| Couche | Fichiers clés | Rôle |
|--------|--------------|------|
| Models | `ImageFile`, `ImageStore`, `OptimizationLevel` | État observable, store central `@MainActor` |
| Services | `ImageOptimizer`, `ToolManager`, `GPUProcessor` | Pipeline d'optimisation, outils CLI, GPU Metal |
| Views | `ContentView`, `FileListView`, `DropZoneView` | UI drag-and-drop, liste fichiers, barre de statut |
| Commands | `OptimizationCommands` | Miroir des actions de la barre d'outils dans la barre des menus |
| Utils | `DesignTokens`, `FileSizeFormatter`, `ToolbarItemID` | Tokens de design, formatage, identifiants de barre d'outils |

## Barre d'outils personnalisable

La barre d'outils de la fenêtre principale (`Views/ContentView.swift`) utilise le mécanisme natif macOS : `.toolbar(id:)` côté vue et `ToolbarCommands()` côté `commands`. L'utilisateur obtient donc gratuitement, dans le menu **Présentation** :

- « Masquer / Afficher la barre d'outils » (⌥⌘T)
- « Personnaliser la barre d'outils… » — feuille système, glisser-déposer, modes Icône / Texte / Icône et texte

Aucune préférence maison : **AppKit persiste tout** sous la clé `NSToolbar Configuration mainToolbar` (`TB Item Identifiers`, `TB Display Mode`, `TB Is Shown`, `TB Size Mode`). Le nom d'autosauvegarde **est** l'identifiant passé à `.toolbar(id:)`.

### Les huit items

| id | Rôle | Par défaut | Personnalisation |
|---|---|---|---|
| `level` | Menu du niveau d'optimisation | visible | retirable |
| `console` | Bascule de la console de logs | visible | retirable |
| `donate` | Soutien Ko-fi | visible | retirable |
| `add` | Ajouter des images | visible | **non retirable** (`.reorderable`) |
| `run` | Optimiser / Stop (fusionnés) | visible | **non retirable** (`.reorderable`) |
| `clear` | Vider la liste | visible | retirable |
| `clearCompleted` | Vider les terminés | masqué | retirable |
| `settings` | Réglages… (`SettingsLink`) | masqué | retirable |

### Deux invariants à ne jamais casser

1. **Les identifiants sont un contrat de persistance** (`Utils/ToolbarItemID.swift`) : les renommer réinitialise silencieusement la barre de tous les utilisateurs. `ToolbarItemIDTests` les épingle.
2. **Aucun item conditionnel** dans le bloc `.toolbar(id:)` — voir `toolbar-items-conditionnels` dans [bugs-connus](bugs-connus.md).

### Pourquoi le miroir menu est obligatoire

La barre peut être masquée ou vidée. Or `⌘↩` était porté par le bouton Optimiser de la barre, et un `keyboardShortcut` ne vit que tant que sa vue est rendue : masquer la barre tuait le raccourci. Stop et la bascule Console n'existaient nulle part ailleurs. `Commands/OptimizationCommands.swift` reflète donc chaque action :

| Menu | Entrées |
|---|---|
| Optimisation | Optimiser tout (⌘↩), Arrêter l'optimisation (⌘.), Niveau d'optimisation, Vider la liste (⇧⌘⌫), Vider les terminés |
| Présentation | Afficher / Masquer la console (⇧⌘L), après les entrées de `ToolbarCommands()` |
| ImageArm | Soutenir ImageArm ♥, après « À propos » |

`LogConsoleView` a également un bouton de fermeture (✕) : barre masquée, c'était la seule sortie manquante.

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
- **ICNS** : iconutil -c iconset → oxipng sur chaque PNG → iconutil -c icns (natif macOS, depuis v1.5.0)

## Gestion des fichiers externes (AppDelegate)

Les fichiers sont reçus via `application(_:open:)`. Pour éviter que SwiftUI `WindowGroup` crée une fenêtre par fichier, `kAEOpenDocuments` est intercepté dans `applicationWillFinishLaunching`. Voir [[bugs-connus#multi-fenetres]].

Depuis la v1.3.2, `application(_:open:)` applique en plus un **debounce de 250 ms** : les URLs s'accumulent dans `batchURLs` et ne sont transmises au store qu'une fois la fenêtre écoulée. Finder envoyant un Apple Event par fichier, c'est ce qui consolide une sélection multiple en un seul lot. ⚠️ Tout test de ce chemin doit attendre au-delà de 250 ms — un `await Task.yield()` ne suffit pas (voir [[bugs-connus#tests-debounce]]).

## Outils CLI embarqués

8 binaires compilés depuis les sources (submodules `tools/submodules/`) et copiés dans `Contents/MacOS/` par un post-compile script de `project.yml` :

| Outil | Build | Note |
|---|---|---|
| pngquant, oxipng | Rust (cargo) | |
| cjpeg, jpegtran | mozjpeg (CMake) | un seul script, `.mozjpeg-built` |
| cwebp | libwebp (CMake) | |
| svgo | Bun compile | ~61 Mo |
| gifsicle | autotools | ajouté v1.5.0 |
| pngcrush | make | ⚠️ compilé mais **plus copié dans le bundle** — retiré du pipeline PNG en v1.3.0 |

⚠️ `make dmg` **ne dépend pas** de `make tools` : sur un dépôt fraîchement cloné, `tools/bin/` est vide (gitignoré) et le build Release échoue sur la copie. Lancer `make tools` d'abord.

## Distribution

- App : GitHub Releases (DMG `ImageArm-X.Y.Z.dmg`)
- Homebrew Cask : `imagearm/tap/imagearm`
- CLI headless : `imagearm --headless fichier.png`
- Quick Action Finder : workflow Automator installé via `install-finder-action.sh`
