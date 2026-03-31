# Vue d'ensemble du projet — ImageArm

> Mis à jour le 2026-03-31

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
| **Outils CLI** | pngquant, oxipng, pngcrush, mozjpeg (cjpeg/jpegtran), gifsicle, svgo, cwebp — embarqués dans le .app |
| **Packaging** | Xcode project (ImageArm.xcodeproj) → Archive/Export → .app bundle / DMG |
| **Localisation** | 5 langues : fr, en, de, nl, it (via Localizable.xcstrings) |

## Fonctionnalités principales

1. **Optimisation multi-format** : PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG, WebP
2. **Pipeline compétitif** : plusieurs outils s'exécutent et le plus petit résultat gagne
3. **4 niveaux d'optimisation** : Rapide, Standard, Maximum, Ultra
4. **Accélération GPU Metal** : quantization PNG par compute shader, encodage JPEG/HEIF/AVIF hardware
5. **Traitement en lot** : drag-and-drop, file picker, dossiers récursifs
6. **Concurrence configurable** : 2 à 16 optimisations simultanées (TaskGroup)
7. **Qualité personnalisable** : override lossy/lossless, sliders qualité PNG/JPEG
8. **Console de logs** : journal d'activité temps réel intégré avec copie presse-papier en un clic
9. **Intégration Finder** : Quick Action (clic droit) + CLI wrapper
10. **Modification in-place** : remplacement atomique avec backup → trash
11. **Mode headless** : `imagearm --headless *.png` pour scripts et CI
12. **Notifications macOS** : alerte quand le traitement batch est terminé
13. **Multi-langues** : interface en français, anglais, allemand, néerlandais et italien
14. **Écran d'accueil** : WelcomeOverlay au premier lancement
15. **Soutien Ko-fi** : lien de donation intégré dans l'interface
16. **Outils CLI embarqués** : compilés et signés dans le .app (pas besoin de Homebrew)

## Structure du dépôt

| Répertoire/Fichier | Rôle |
|---|---|
| `Sources/ImageArm/` | Code source Swift (18 fichiers) |
| `Sources/ImageArm/Models/` | Modèles de données et état (5 fichiers) |
| `Sources/ImageArm/Services/` | Logique métier : optimizer, GPU, tool manager (3 fichiers) |
| `Sources/ImageArm/Views/` | Interface SwiftUI (7 fichiers) |
| `Sources/ImageArm/Utils/` | Utilitaires (2 fichiers) |
| `Sources/ImageArm/Localizable.xcstrings` | Traductions multi-langues (fr, en, de, nl, it) |
| `Sources/ImageArm/Credits.rtf` | Crédits de l'application |
| `project.yml` | Configuration xcodegen (génère ImageArm.xcodeproj) |
| `ImageArm.xcodeproj` | Projet Xcode (généré par xcodegen) |
| `Info.plist` | Info.plist de l'application (racine du projet) |
| `ImageArm.entitlements` | Entitlements macOS (pas de sandbox, GPU) |
| `Tests/ImageArmTests/` | Tests unitaires (9 fichiers) |
| `tools/` | Build system outils CLI embarqués (Makefile, scripts, submodules, bin/) |
| `install-service.sh` | Installation Finder Quick Action + CLI |
| `install-finder-action.sh` | Installation service Automator |
| `Sources/ImageArm/Assets.xcassets/` | Ressources (icônes, assets) |

## Liens vers la documentation détaillée

- [Architecture](./architecture.md) — Architecture technique détaillée, pipelines, GPU, concurrence
- [Arborescence source](./source-tree-analysis.md) — Arbre annoté et répertoires critiques
- [Gestion d'état](./state-management.md) — Stores, flux de données, persistance
- [Composants UI](./ui-component-inventory.md) — Inventaire complet des vues SwiftUI
- [Guide de développement](./development-guide.md) — Build, run, déploiement, outils requis
