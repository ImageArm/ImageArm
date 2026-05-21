---
title: Historique des releases
category: session-log
tags: [release, changelog, version]
updated: 2026-05-21
---

# Historique des releases ImageArm

## v1.4.0 (build 11) — 2026-05-21

**Feat : préserver les métadonnées (EXIF, profils couleur, commentaires SVG)**

- Nouveau toggle "Préserver les métadonnées (EXIF, profil couleur)" dans Settings → Fichiers (activé par défaut)
- `QualityOverrides.preserveMetadata` + `effectiveStripMetadata(level:)` — préserve indépendamment du niveau
- 8 call sites `level.stripMetadata` remplacés par `overrides.effectiveStripMetadata(level:)` dans `ImageOptimizer`
- **cwebp** : `-metadata all` ajouté quand préservation active (défaut cwebp = strip, logique inverse)
- **svgo v4** : config `.mjs` écrite dans `FileManager.default.temporaryDirectory` avec `removeComments: false, removeMetadata: false`
- `LevelDetailView` reflète le comportement effectif (toggle global prime sur le niveau)
- `@AppStorage("preserveMetadata")` — persisté entre les sessions
- Migration : les utilisateurs existants voient leurs métadonnées préservées par défaut (changement silencieux pour standard/high/ultra)
- Limitation connue : `pngquant --strip` (hardcodé) supprime les métadonnées même si toggle activé
- Clôture issue #4

## v1.3.3 (build 10) — 2026-05-21

**Feat : préserver les dates des fichiers lors de l'optimisation**

- Nouveau toggle "Préserver les dates originales des fichiers" dans Settings → Optimisation → section "Fichiers" (activé par défaut)
- `safeReplace()` capture les timestamps avant remplacement et les restaure via `FileManager.setAttributes`
- Propagation via `QualityOverrides.preserveTimestamps`, persisté avec `@AppStorage`
- Tous les formats : PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG, WebP + mode headless
- Clôture issue #5

## v1.3.1 (build 8) — 2026-04-17

**Fix : ouverture multi-fenêtres sur sélection multiple**

- Correction du bug où sélectionner N fichiers (clic droit > Ouvrir avec) ouvrait N fenêtres
- Cause : SwiftUI `WindowGroup` créait une fenêtre par `kAEOpenDocuments` Apple Event reçu
- Fix : interception de `kAEOpenDocuments` dans `applicationWillFinishLaunching` avant le handler SwiftUI
- Ajout de `LSMultipleInstancesProhibited` dans `Info.plist`
- Ajout de `AppDelegateTests` (10 cas de test)

Voir [[bugs-connus#multi-fenetres]] pour le diagnostic complet.

## v1.3.0 (build 7) — 2026-03-22

**Simplification pipeline PNG**

- Retrait GPU Metal et pngcrush du pipeline PNG
- Pipeline PNG simplifié : pngquant → oxipng uniquement
- Correction crash use-after-free dans `GPUProcessor.quantizePNG` (build 6)

## v1.2.2 (build 5)

- Fix Quick Action Finder
- Distribution Homebrew Cask via `imagearm/tap/imagearm`
- GitHub Actions pour mise à jour automatique du tap
