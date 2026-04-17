---
title: Historique des releases
category: session-log
tags: [release, changelog, version]
updated: 2026-04-17
---

# Historique des releases ImageArm

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
