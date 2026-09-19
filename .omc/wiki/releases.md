---
title: Historique des releases
category: session-log
tags: [release, changelog, version]
updated: 2026-09-19
---

# Historique des releases ImageArm

## v1.6.1 (build 15) — 2026-09-19

Fix: « Masquer la barre d'outils » (⌥⌘T) ne survivait pas au relancement.

La barre réapparaissait au lancement suivant, ce qui vidait de son sens la fonctionnalité annoncée en 1.6.0. AppKit enregistrait pourtant bien le choix — c'est SwiftUI qui reposait la barre en visible à la création de la fenêtre. Le choix est désormais restauré explicitement au démarrage, dans les deux sens.

Merci à @eduardodesigner pour le signalement initial (#7).

## v1.6.0 (build 14) — 2026-09-19

Feat: barre d'outils masquable et personnalisable (#7)

- **Présentation ▸ Masquer la barre d'outils** (⌥⌘T) et **Personnaliser la barre d'outils…** : glisser-déposer des boutons, modes Icône / Texte / Icône et texte, disposition mémorisée par macOS.
- Deux nouveaux boutons disponibles dans la palette de personnalisation : **Vider les terminés** et **Réglages…**
- **Nouveau menu Optimisation** : Optimiser tout (⌘↩), Arrêter l'optimisation (⌘.), Niveau d'optimisation, Vider la liste (⇧⌘⌫), Vider les terminés. Toutes les actions de la barre d'outils existent désormais aussi dans la barre des menus — l'app reste entièrement pilotable barre masquée.
- Présentation ▸ Afficher/Masquer la console (⇧⌘L), plus un bouton de fermeture dans l'en-tête de la console.
- Optimiser et Stop fusionnés en un seul bouton qui bascule selon l'état du traitement.

Fix: trois chaînes des Réglages n'étaient pas traduites (« Fichiers » et les deux options de préservation).

Tests: 111 → 121.

## v1.5.1 (build 13) — 2026-09-19

**Feat : support des fichiers `.icns` + restauration de l'UI française**

- **`.icns`** : pipeline `iconutil -c iconset` → oxipng sur chaque PNG → `iconutil -c icns`.
  Outils natifs macOS, zéro dépendance. Les `.icns` legacy sans ressource PNG sont ignorés. (closes #6)
- **UI française restaurée** : `Localizable.xcstrings` déclare `sourceLanguage: fr` mais
  `CFBundleDevelopmentRegion` valait `en` — aucun `fr.lproj` n'était généré et les utilisateurs
  français recevaient les traductions anglaises. Voir [[bugs-connus#localisation-fr]].
- **Sélecteur de niveau refondu** : un `Picker` `.menu` n'affiche que l'icône de son `Label`,
  le niveau sélectionné était invisible et une capsule `(compression max)` compensait.
  Remplacé par un menu unique « Rapide — sans perte » … « Ultra — compression extrême ».
- **5 correctifs de fiabilité du pipeline** (revue adversariale) : ordre du `DispatchGroup`
  avant `process.run()`, `guard !Task.isCancelled` avant chaque `finalize()`, backups
  `.imagearm.backup` préservés du nettoyage, fuite des tâches auxiliaires, `isProcessing`
  pendant un reoptimize.
- **gifsicle de nouveau embarqué** : il était copié dans le bundle sans règle de compilation.
  Voir [[bugs-connus#gifsicle-jamais-compile]].
- **Suite de tests réparée** : elle ne compilait plus depuis la 1.3.3 et masquait 17 tests
  obsolètes. 111 tests au vert.

Note : les versions 1.5.0 (build 12) et le tag associé n'ont jamais été publiés — la chaîne
de release était cassée. Voir [[release-process]] pour les garde-fous ajoutés.

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
