# Analyse de l'arborescence source — ImageArm

> Mis à jour le 2026-03-31

## Arborescence annotée

```
imagearm/
├── project.yml                      # Configuration xcodegen — génère ImageArm.xcodeproj
├── ImageArm.xcodeproj/               # Projet Xcode (généré par xcodegen)
├── Info.plist                       # Info.plist de l'application
├── ImageArm.entitlements             # Entitlements: pas de sandbox, accès fichiers, accès GPU
├── CLAUDE.md                        # Instructions pour Claude Code (documentation du projet)
│
├── Sources/
│   └── ImageArm/
│       ├── ImageArmApp.swift         # ★ POINT D'ENTRÉE — @main, AppDelegate, gestion open URLs
│       │
│       ├── Assets.xcassets/         # Assets catalogue (AppIcon, etc.)
│       │   └── AppIcon.appiconset/  # Icône de l'application
│       │
│       ├── Models/                  # Couche données et état
│       │   ├── ImageFile.swift      # Modèle par fichier (observable), ImageFormat enum, OptimizationStatus
│       │   ├── ImageStore.swift     # ★ STORE CENTRAL — @MainActor, gestion fichiers, concurrence TaskGroup
│       │   ├── OptimizationLevel.swift  # 4 niveaux (quick/standard/high/ultra) avec réglages par format
│       │   ├── QualityOverrides.swift   # Surcharges qualité personnalisée (JPEG/PNG)
│       │   └── LogStore.swift       # Singleton journal d'activité, optiLog() global
│       │
│       ├── Services/                # Couche logique métier
│       │   ├── ImageOptimizer.swift # ★ CŒUR — Actor, pipeline multi-outils compétitif par format
│       │   ├── ToolManager.swift    # Détection outils CLI (Homebrew, system, which fallback)
│       │   └── GPUProcessor.swift   # ★ GPU — Metal compute shaders (quantization PNG), HW JPEG encode
│       │
│       ├── Views/                   # Couche présentation SwiftUI
│       │   ├── ContentView.swift    # Vue racine — drag-and-drop, file picker, toolbar
│       │   ├── FileListView.swift   # Tableau des fichiers + sous-composants (badges, progress, savings)
│       │   ├── DropZoneView.swift   # Zone d'accueil vide (drag invitation)
│       │   ├── StatusBarView.swift  # Barre d'état (progression, totaux, économies)
│       │   ├── SettingsView.swift   # Préférences (niveaux, qualité, outils installés)
│       │   ├── LogConsoleView.swift # Console de logs intégrée
│       │   └── WelcomeOverlay.swift # Écran d'accueil au premier lancement
│       │
│       ├── Utils/
│       │   ├── FileSizeFormatter.swift  # Formatage tailles fichiers (ByteCountFormatter)
│       │   └── DesignTokens.swift       # Tokens couleurs (format, statut) et spacing
│       │
│       ├── Localizable.xcstrings    # Traductions multi-langues (fr, en, de, nl, it)
│       └── Credits.rtf              # Crédits de l'application
│
├── Tests/
│   └── ImageArmTests/               # Tests unitaires (9 fichiers)
│       ├── HeadlessModeTests.swift
│       ├── ImageFormatTests.swift
│       ├── ImageOptimizerTests.swift
│       ├── ToolManagerTests.swift
│       ├── OptimizationLevelTests.swift
│       ├── ImageStoreTests.swift
│       ├── OptimizationStatusTests.swift
│       ├── QualityOverridesTests.swift
│       └── FileSizeFormatterTests.swift
│
├── tools/
│   ├── Makefile                    # Build system outils CLI embarqués (make tools, sign-tools, dmg…)
│   ├── scripts/                    # Scripts de compilation par outil (build-*.sh)
│   ├── submodules/                 # Sources des outils (git submodules)
│   └── bin/                        # Binaires compilés (pngquant, oxipng, pngcrush, cjpeg, jpegtran, svgo, cwebp, gifsicle)
│
├── install-service.sh              # Installation Finder Quick Action + CLI wrapper (~/.local/bin/imagearm)
└── install-finder-action.sh        # Installation service Automator (Finder context menu)
```

## Répertoires critiques

| Répertoire | Rôle | Fichiers clés |
|---|---|---|
| `Sources/ImageArm/Models/` | État de l'application, types de données | ImageStore.swift (store central), ImageFile.swift |
| `Sources/ImageArm/Services/` | Logique métier, orchestration | ImageOptimizer.swift (pipeline), GPUProcessor.swift (Metal) |
| `Sources/ImageArm/Views/` | Interface utilisateur SwiftUI | ContentView.swift (racine), SettingsView.swift, WelcomeOverlay.swift |
| `Sources/ImageArm/Utils/` | Utilitaires et design tokens | FileSizeFormatter.swift, DesignTokens.swift |
| `Tests/ImageArmTests/` | Tests unitaires | 9 fichiers couvrant formats, optimizer, store, headless, etc. |
| `tools/` | Build system outils CLI | Makefile, scripts/, submodules/, bin/ |

## Statistiques

| Métrique | Valeur |
|---|---|
| Fichiers Swift (source) | 18 |
| Fichiers Swift (tests) | 9 |
| Scripts shell | 2 (install) + 7 (build outils) |
| Lignes de code Swift (approx.) | ~3 330 |
| Lignes de code Metal (inline) | ~80 |
| Outils CLI embarqués | 8 binaires (tools/bin/) |
| Langues supportées | 5 (fr, en, de, nl, it) |
| Dépendances externes | 0 |
| Projet | Xcode (ImageArm.xcodeproj via xcodegen) |
