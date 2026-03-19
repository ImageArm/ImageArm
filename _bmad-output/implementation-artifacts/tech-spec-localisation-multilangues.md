---
title: 'Localisation multi-langues — sync xcstrings + fallback anglais'
slug: 'localisation-multilangues'
created: '2026-03-19'
status: 'completed'
stepsCompleted: [1, 2, 3, 4]
tech_stack: ['Swift 5.9', 'SwiftUI', 'Xcode xcstrings (JSON Apple)', 'Info.plist', 'xcodegen project.yml']
files_to_modify: ['Sources/ImageArm/Localizable.xcstrings', 'Info.plist', 'project.yml', 'Sources/ImageArm/Views/DropZoneView.swift', 'Sources/ImageArm/Views/WelcomeOverlay.swift', 'README.md', 'docs/architecture.md', 'docs/development-guide.md', 'docs/index.md', 'docs/project-overview.md', 'docs/source-tree-analysis.md', 'docs/state-management.md', 'docs/ui-component-inventory.md']
code_patterns: ['String(localized:)', 'LocalizedStringKey (SwiftUI Text/Label/Button)', 'xcstrings JSON', 'CFBundleDevelopmentRegion']
test_patterns: ['build Xcode', 'changement langue système macOS']
---

# Tech-Spec: Localisation multi-langues — sync xcstrings + fallback anglais

**Created:** 2026-03-19

## Overview

### Problem Statement

Le fichier `Localizable.xcstrings` contient 56 entrées `"extractionState": "stale"` (toutes encore utilisées, le marker est faux — voir investigation), 22 strings manquantes sans traduction ajoutées lors des derniers sprints (formats AVIF/HEIF, Ko-fi, UI), et 2 strings avec du texte outdaté (liste de formats + commande Brew). La langue de fallback pour les utilisateurs avec une langue non supportée est le français (`developmentRegion: fr`) au lieu de l'anglais. La documentation dans `docs/` mentionne encore l'ancien nom PngOpti.

### Solution

1. Changer `developmentRegion` → `en` dans `project.yml` + `CFBundleDevelopmentRegion` → `en` dans `Info.plist` : macOS utilisera l'anglais comme fallback pour les langues non supportées, sans modifier le code Swift.
2. Synchroniser `Localizable.xcstrings` : retirer les markers `stale` (56), ajouter 22 strings manquantes avec traductions fr/en/de/it/nl, mettre à jour 2 strings outdatées.
3. Mettre à jour `DropZoneView.swift` et `WelcomeOverlay.swift` pour que les listes de formats reflètent tous les formats supportés.
4. Mettre à jour `README.md` (mention localisation multi-langues) et `docs/*.md` (PngOpti → ImageArm + formats complets).

### Scope

**In Scope:**
- `project.yml` + `Info.plist` : fallback anglais
- `Sources/ImageArm/Localizable.xcstrings` : nettoyage stale + 22 nouvelles entrées + 2 mises à jour
- `Sources/ImageArm/Views/DropZoneView.swift` + `WelcomeOverlay.swift` : texte liste formats
- `README.md` : mention localisation multi-langues (FR + EN)
- `docs/*.md` (7 fichiers) : PngOpti → ImageArm + formats complets

**Out of Scope:**
- Modifier le mécanisme de localisation (String(localized:) reste tel quel)
- Ajouter de nouvelles langues (es, ja, zh…)
- Créer de nouveaux fichiers de documentation

## Context for Development

### Codebase Patterns

- **Deux mécanismes de localisation** dans le code Swift :
  1. `String(localized: "clé")` → dans Models/Services (explicit lookup)
  2. `Text("clé")` / `Label("clé")` / `Button("clé")` / `Toggle("clé")` → SwiftUI utilise `LocalizedStringKey` automatiquement, la clé est la string French littérale
- Fichier central : `Sources/ImageArm/Localizable.xcstrings` (format JSON Apple, `sourceLanguage: "fr"`)
- Langues supportées : **fr** (source), **en**, **de**, **it**, **nl** (défini dans `project.yml` → `knownRegions: [fr, en, de, nl, it]`)
- `CFBundleDevelopmentRegion` dans `Info.plist` + `developmentRegion` dans `project.yml` → valeur actuelle `fr`, à changer en `en`
- Strings avec `"extractionState": "stale"` → **toutes encore utilisées** (les format strings comme `%lld en cours` correspondent à `"\(count) en cours"` en Swift — Xcode ne sait pas reconstruire ces clés). Action : retirer le marker seulement.
- Le code et la documentation projet restent en français

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `Sources/ImageArm/Localizable.xcstrings` | Fichier xcstrings principal (47 KB, sourceLanguage: fr) |
| `project.yml` | `developmentRegion: fr` → `en` + `knownRegions` |
| `Info.plist` | `CFBundleDevelopmentRegion: fr` → `en` |
| `Sources/ImageArm/Views/DropZoneView.swift` | Ligne 20 : string formats outdatée |
| `Sources/ImageArm/Views/WelcomeOverlay.swift` | Ligne 16 : string formats outdatée |
| `Sources/ImageArm/Services/ImageOptimizer.swift` | Source strings AVIF/HEIF manquantes |
| `Sources/ImageArm/Models/OptimizationLevel.swift` | Source strings `(sans perte)` etc. |
| `README.md` | Documentation bilingue — ajouter mention langues |
| `docs/architecture.md` | Renommer PngOpti + formats |
| `docs/development-guide.md` | Renommer PngOpti |
| `docs/index.md` | Renommer PngOpti |
| `docs/project-overview.md` | Renommer PngOpti + formats |
| `docs/source-tree-analysis.md` | Renommer PngOpti |
| `docs/state-management.md` | Renommer PngOpti |
| `docs/ui-component-inventory.md` | Renommer PngOpti |

### Technical Decisions

- **`developmentRegion: en` dans project.yml** : xcodegen utilise cette valeur pour générer `DEVELOPMENT_REGION` dans le xcodeproj. Cohérence avec Info.plist indispensable car `GENERATE_INFOPLIST_FILE: NO`.
- **Stale markers** : ne pas supprimer les entrées, seulement retirer `"extractionState": "stale"`. Les clés format (`%lld`, `%@`) sont utilisées via interpolation Swift mais non détectables par l'extracteur Xcode.
- **Strings avec interpolation complexe** (ex: `"Tu viens d'optimiser %lld image%@ pour %@ économisés..."`) : ajouter dans xcstrings avec le pattern Swift attendu — `%lld` pour `Int`, `%@` pour `String`.
- **Format strings dans Views** : `DropZoneView` et `WelcomeOverlay` utilisent des LocalizedStringKey hardcodées qui sont outdatées — les mettre à jour dans le code Swift ET ajouter les nouvelles clés dans xcstrings.

## Implementation Plan

### Tasks

- [x] **Tâche 1 : Fallback anglais — project.yml + Info.plist**
  - Fichier : `project.yml`
  - Action : Ligne 8 — `developmentRegion: fr` → `developmentRegion: en`
  - Fichier : `Info.plist`
  - Action : `<string>fr</string>` → `<string>en</string>` sous la clé `CFBundleDevelopmentRegion`

- [x] **Tâche 2 : xcstrings — retirer tous les markers `"extractionState": "stale"`**
  - Fichier : `Sources/ImageArm/Localizable.xcstrings`
  - Action : Supprimer les 56 occurrences de `"extractionState" : "stale",` (ligne complète + virgule). Aucune entrée ne doit être supprimée.
  - Notes : Utiliser search & replace global sur le fichier JSON.

- [x] **Tâche 3 : xcstrings — mettre à jour la commande Brew**
  - Fichier : `Sources/ImageArm/Localizable.xcstrings`
  - Action : Renommer la clé `"Installer tous : brew install pngquant oxipng pngcrush advancecomp jpegoptim mozjpeg gifsicle webp"` → `"Installer tous : brew install pngquant oxipng pngcrush mozjpeg gifsicle svgo webp"` et mettre à jour les 4 traductions :
    - `en` : `"Install all: brew install pngquant oxipng pngcrush mozjpeg gifsicle svgo webp"`
    - `de` : `"Alle installieren: brew install pngquant oxipng pngcrush mozjpeg gifsicle svgo webp"`
    - `it` : `"Installa tutto: brew install pngquant oxipng pngcrush mozjpeg gifsicle svgo webp"`
    - `nl` : `"Alles installeren: brew install pngquant oxipng pngcrush mozjpeg gifsicle svgo webp"`
  - Note : Mettre aussi à jour la clé `"PNG · JPEG · GIF · SVG · WebP"` (stale) → supprimer cette entrée (elle ne correspond à aucune clé dans le code, `DropZoneView` utilise une clé différente).

- [x] **Tâche 4 : Mettre à jour les strings de formats dans Views + xcstrings**
  - Fichier : `Sources/ImageArm/Views/DropZoneView.swift`, ligne 20
  - Action : `"PNG · JPEG · HEIF · SVG · WebP"` → `"PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP"`
  - Fichier : `Sources/ImageArm/Views/WelcomeOverlay.swift`, ligne 16
  - Action : `"Glissez vos images ou cliquez + pour commencer.\nImageArm optimise PNG, JPEG, HEIF, SVG et WebP."` → `"Glissez vos images ou cliquez + pour commencer.\nImageArm optimise PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG et WebP."`
  - Fichier : `Sources/ImageArm/Localizable.xcstrings`
  - Action : Ajouter les 2 nouvelles clés avec traductions :
    ```
    "PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP" :
      en: "PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP"
      de: "PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP"
      it: "PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP"
      nl: "PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP"

    "Glissez vos images ou cliquez + pour commencer.\nImageArm optimise PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG et WebP." :
      en: "Drop your images or click + to start.\nImageArm optimizes PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG and WebP."
      de: "Bilder hier ablegen oder + klicken.\nImageArm optimiert PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG und WebP."
      it: "Trascina le immagini o clicca + per iniziare.\nImageArm ottimizza PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG e WebP."
      nl: "Sleep afbeeldingen of klik + om te starten.\nImageArm optimaliseert PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG en WebP."
    ```

- [x] **Tâche 5 : xcstrings — ajouter strings manquantes Models/Services (8 entrées)**
  - Fichier : `Sources/ImageArm/Localizable.xcstrings`
  - Action : Ajouter les 8 entrées suivantes avec traductions fr/en/de/it/nl :

  | Clé (fr) | en | de | it | nl |
  |---|---|---|---|---|
  | `"(sans perte)"` | `"(lossless)"` | `"(verlustfrei)"` | `"(senza perdita)"` | `"(verliesvrij)"` |
  | `"(compression max)"` | `"(max compression)"` | `"(max. Kompression)"` | `"(compressione max)"` | `"(max. compressie)"` |
  | `"(compression extrême)"` | `"(extreme compression)"` | `"(extreme Kompression)"` | `"(compressione estrema)"` | `"(extreme compressie)"` |
  | `"HEIF lossy : %@"` | `"HEIF lossy: %@"` | `"HEIF verlustbehaftet: %@"` | `"HEIF lossy: %@"` | `"HEIF lossy: %@"` |
  | `"HEIF qualité max : %@"` | `"HEIF max quality: %@"` | `"HEIF max. Qualität: %@"` | `"HEIF qualità max: %@"` | `"HEIF max. kwaliteit: %@"` |
  | `"AVIF lossy : %@"` | `"AVIF lossy: %@"` | `"AVIF verlustbehaftet: %@"` | `"AVIF lossy: %@"` | `"AVIF lossy: %@"` |
  | `"AVIF qualité max : %@"` | `"AVIF max quality: %@"` | `"AVIF max. Qualität: %@"` | `"AVIF qualità max: %@"` | `"AVIF max. kwaliteit: %@"` |
  | `"ERREUR restauration backup"` | `"ERROR restoring backup"` | `"FEHLER beim Wiederherstellen des Backups"` | `"ERRORE ripristino backup"` | `"FOUT bij herstellen back-up"` |

- [x] **Tâche 6 : xcstrings — ajouter strings manquantes Views Ko-fi + UI (14 entrées)**
  - Fichier : `Sources/ImageArm/Localizable.xcstrings`
  - Action : Ajouter les 14 entrées suivantes avec traductions fr/en/de/it/nl :

  | Clé (fr) | en | de | it | nl |
  |---|---|---|---|---|
  | `"Bienvenue dans ImageArm"` | `"Welcome to ImageArm"` | `"Willkommen bei ImageArm"` | `"Benvenuto in ImageArm"` | `"Welkom bij ImageArm"` |
  | `"Commencer"` | `"Get started"` | `"Loslegen"` | `"Inizia"` | `"Aan de slag"` |
  | `"Copier"` | `"Copy"` | `"Kopieren"` | `"Copia"` | `"Kopiëren"` |
  | `"Copier le résumé dans le presse-papiers"` | `"Copy summary to clipboard"` | `"Zusammenfassung in Zwischenablage kopieren"` | `"Copia il riepilogo negli appunti"` | `"Samenvatting naar klembord kopiëren"` |
  | `"Merci d'utiliser ImageArm ♥"` | `"Thanks for using ImageArm ♥"` | `"Danke, dass du ImageArm nutzt ♥"` | `"Grazie per usare ImageArm ♥"` | `"Bedankt voor het gebruik van ImageArm ♥"` |
  | `"Merci ♥"` | `"Thanks ♥"` | `"Danke ♥"` | `"Grazie ♥"` | `"Bedankt ♥"` |
  | `"Soutenir"` | `"Support"` | `"Unterstützen"` | `"Supporta"` | `"Steunen"` |
  | `"Soutenir ImageArm sur Ko-fi"` | `"Support ImageArm on Ko-fi"` | `"ImageArm auf Ko-fi unterstützen"` | `"Supporta ImageArm su Ko-fi"` | `"ImageArm steunen via Ko-fi"` |
  | `"Faire un don ♥"` | `"Make a donation ♥"` | `"Spenden ♥"` | `"Fai una donazione ♥"` | `"Doneer ♥"` |
  | `"Plus tard"` | `"Later"` | `"Später"` | `"Più tardi"` | `"Later"` |
  | `"Tu viens d'optimiser %lld image%@ pour %@ économisés. Si ImageArm te fait gagner du temps, un petit don sur Ko-fi nous aide beaucoup !"` | `"You just optimized %lld image%@ saving %@. If ImageArm saves you time, a small donation on Ko-fi helps a lot!"` | `"Du hast gerade %lld Bild%@ optimiert und %@ gespart. Wenn ImageArm dir Zeit spart, hilft eine kleine Spende auf Ko-fi sehr!"` | `"Hai appena ottimizzato %lld immagine%@ risparmiando %@. Se ImageArm ti fa risparmiare tempo, una piccola donazione su Ko-fi aiuta molto!"` | `"Je hebt zojuist %lld afbeelding%@ geoptimaliseerd en %@ bespaard. Als ImageArm je tijd bespaart, helpt een kleine donatie op Ko-fi enorm!"` |
  | `"Les outils CLI sont embarqués dans l'application."` | `"CLI tools are bundled within the application."` | `"CLI-Tools sind in der App enthalten."` | `"Gli strumenti CLI sono inclusi nell'applicazione."` | `"CLI-tools zijn meegeleverd in de applicatie."` |
  | `"Voir les licences"` | `"View licenses"` | `"Lizenzen anzeigen"` | `"Visualizza licenze"` | `"Licenties bekijken"` |

- [x] **Tâche 7 : README — ajouter mention localisation multi-langues**
  - Fichier : `README.md`
  - Action (section FR "Fonctionnalités") : Ajouter un bullet `**Multi-langue** — Interface disponible en français, anglais, allemand, néerlandais et italien. Anglais par défaut si votre langue n'est pas supportée.`
  - Action (section EN "Features") : Ajouter un bullet `**Multi-language** — Interface available in French, English, German, Dutch and Italian. Defaults to English for unsupported languages.`

- [x] **Tâche 8 : docs/ — renommer PngOpti → ImageArm + mettre à jour formats**
  - Fichiers : `docs/architecture.md`, `docs/development-guide.md`, `docs/index.md`, `docs/project-overview.md`, `docs/source-tree-analysis.md`, `docs/state-management.md`, `docs/ui-component-inventory.md`
  - Action : Remplacer toutes les occurrences de `PngOpti` / `pngopti` / `PngOpti.xcodeproj` par `ImageArm` / `imagearm` / `ImageArm.xcodeproj`
  - Action : Partout où les formats sont listés sans GIF/TIFF/AVIF, ajouter les formats manquants
  - Action : Mettre à jour les dates `2026-03-11` → `2026-03-19` dans les headers

### Acceptance Criteria

- [x] **AC 1 :** Étant donné un Mac avec langue système espagnol (non supportée), quand l'app est lancée, alors l'interface s'affiche en **anglais** (pas en français).
- [x] **AC 2 :** Étant donné un Mac avec langue système française, quand l'app est lancée, alors l'interface s'affiche en **français**.
- [x] **AC 3 :** Étant donné un Mac avec langue système anglaise, quand l'app est lancée, alors l'interface s'affiche en **anglais**.
- [x] **AC 4 :** Étant donné le fichier `Localizable.xcstrings`, quand on l'inspecte, alors aucune entrée ne contient `"extractionState"`.
- [x] **AC 5 :** Étant donné le fichier `Localizable.xcstrings`, quand on cherche les strings `"(sans perte)"`, `"AVIF lossy : %@"`, `"Soutenir"`, `"Bienvenue dans ImageArm"`, alors toutes existent avec des traductions en, de, it, nl.
- [x] **AC 6 :** Étant donné le projet buildé avec `xcodebuild`, quand le build se termine, alors **aucune erreur ni warning** liée à la localisation.
- [x] **AC 7 :** Étant donné la `DropZoneView`, quand on la regarde, alors la liste de formats affiche **PNG · JPEG · HEIF · GIF · TIFF · AVIF · SVG · WebP**.
- [x] **AC 8 :** Étant donné le `README.md`, quand on le lit, alors une mention **multi-langue** est présente dans les sections Features (FR et EN).
- [x] **AC 9 :** Étant donné les fichiers `docs/*.md`, quand on les inspecte, alors aucune occurrence de **PngOpti** ne subsiste.
- [x] **AC 10 :** Étant donné `project.yml`, quand on l'inspecte, alors `developmentRegion: en`. Étant donné `Info.plist`, alors `CFBundleDevelopmentRegion` = `en`.

## Additional Context

### Dependencies

- Aucune dépendance externe
- `xcodegen generate` requis après modification de `project.yml` pour régénérer le xcodeproj

### Testing Strategy

1. Après Tâche 1 : `xcodebuild -project ImageArm.xcodeproj -scheme ImageArm build` → vérifier 0 erreur
2. Après Tâche 2 : Ouvrir xcstrings dans Xcode → vérifier absence de warnings stale
3. Après Tâche 5+6 : Build → vérifier que les nouvelles clés compilent sans warning
4. Test manuel AC1 : Réglages Système → Général → Langue → ajouter Español → relancer l'app → vérifier anglais
5. Test manuel AC7 : Lancer l'app → vérifier `DropZoneView` affiche tous les formats

### Notes

- La string Ko-fi avec `%lld image%@` utilise deux specifiers : `%lld` pour le compte (Int), `%@` pour le pluriel ("s" ou ""). En xcstrings, l'entrée doit respecter exactement ce pattern.
- Les docs dans `docs/` sont générées (`> Généré le ...`) — leur contenu peut être remplacé librement sans risque de perte de travail manuel.
- Après `xcodegen generate`, vérifier que `developmentRegion` est bien propagé dans le `.xcodeproj` généré.

## Review Notes

- Adversarial review complétée
- Findings : 8 total, 2 fixés (F3 : project-context.md mis à jour), 6 bruit/noise ignorés
- Résolution : fix automatique
- F2 (docs non-trackés) : 5 fichiers docs modifiés mais non-trackés git — ajouter avec `git add docs/` lors du commit
