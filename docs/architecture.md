# Architecture — ImageArm

> Généré le 2026-03-19 | Scan exhaustif

## Résumé

ImageArm est une application macOS native (SwiftUI, macOS 14+) qui optimise des images en lot via un pipeline multi-outils compétitif. L'application combine des outils CLI externes (pngquant, oxipng, mozjpeg, etc.) avec de l'accélération GPU Metal pour obtenir la meilleure compression possible. Zéro dépendance externe — uniquement les frameworks Apple.

## Stack technologique

| Catégorie | Technologie | Version |
|---|---|---|
| Langage | Swift | 5.9 |
| UI | SwiftUI | macOS 14+ |
| GPU | Metal (compute shaders) | System |
| Traitement image | Core Image, ImageIO | System |
| Concurrence | Swift Concurrency (async/await, Actor, TaskGroup) | Built-in |
| Packaging | Xcode project (ImageArm.xcodeproj) via xcodegen (project.yml) | Single target |

## Pattern architectural

**MVVM simplifié avec Services en couche Actor**

```
┌─────────────────────────────────────────────────────┐
│                    Views (SwiftUI)                    │
│  ContentView → FileListView, DropZoneView,           │
│                StatusBarView, SettingsView            │
│                LogConsoleView                         │
├──────────────────────┬──────────────────────────────┤
│    @EnvironmentObject │  @EnvironmentObject           │
│         ▼            │         ▼                     │
│    ImageStore        │     LogStore                  │
│  (@MainActor)        │   (singleton)                 │
├──────────────────────┴──────────────────────────────┤
│                   Models                             │
│  ImageFile, OptimizationLevel, QualityOverrides      │
├─────────────────────────────────────────────────────┤
│                  Services                            │
│  ImageOptimizer (actor) ←── ToolManager (Sendable)  │
│         │                                            │
│         ├── Pipeline PNG:  GPU → pngquant → oxipng → pngcrush │
│         ├── Pipeline JPEG: GPU HW → mozjpeg               │
│         ├── Pipeline HEIF: GPU lossy → GPU max quality     │
│         ├── Pipeline GIF:  gifsicle (lossy optionnel)      │
│         ├── Pipeline TIFF: tiffutil -lzw                   │
│         ├── Pipeline AVIF: GPU lossy → GPU max quality     │
│         ├── Pipeline SVG:  svgo                            │
│         └── Pipeline WebP: cwebp                          │
│                                                            │
│  GPUProcessor (@unchecked Sendable, singleton)             │
│  ├── Metal compute shader (quantize_dither) — PNG          │
│  ├── Metal compute shader (build_histogram)                │
│  ├── ImageIO hardware JPEG encoder                         │
│  ├── ImageIO hardware HEIF encoder                         │
│  └── ImageIO hardware AVIF encoder (macOS 14+)             │
└─────────────────────────────────────────────────────┘
```

## Pipeline d'optimisation

### Principe : compétition multi-outils

Pour chaque image, plusieurs outils s'exécutent séquentiellement. Chaque outil produit un fichier temporaire. La fonction `keepBest()` compare la taille du résultat avec le meilleur résultat courant — **le plus petit gagne**.

### Pipeline par format

#### PNG (2-4 étapes selon le niveau)
1. **Metal GPU quantize** (high/ultra, lossy) — Compute shader Bayer+blue noise dithering
2. **pngquant** (high/ultra, lossy) — Quantization lossy, compète avec le résultat GPU
3. **oxipng** (toujours) — Recompression lossless, niveaux -o2 à -o6
4. **pngcrush** (high/ultra) — Sélection brute-force de filtres PNG

#### JPEG (1-2 étapes selon le niveau)
1. **Metal GPU HW encoder** (high/ultra, lossy) — Apple Silicon hardware encoder via ImageIO
2. **mozjpeg/jpegtran** (toujours) — Recompression progressive lossless

#### HEIF (1-2 étapes selon le niveau)
1. **GPU lossy** (high/ultra) — Encodage HEIF à qualité configurable
2. **GPU max qualité** (toujours) — Encodage HEIF qualité maximale

#### GIF (1 étape)
1. **gifsicle** — Optimisation -O1 à -O3, `--lossy=80/120` en high/ultra

#### TIFF (1 étape)
1. **tiffutil -lzw** — Recompression LZW lossless (intégré macOS, `/usr/bin`)

#### AVIF (1-2 étapes selon le niveau)
1. **GPU lossy** (high/ultra) — Encodage AVIF via ImageIO natif macOS 14+
2. **GPU qualité 95** (toujours) — Encodage AVIF haute qualité

#### SVG (1 étape)
1. **svgo** — Optimisation SVG (minification, nettoyage)

#### WebP (1 étape)
1. **cwebp** — Recompression lossless ou lossy

### Gestion des fichiers temporaires

- Pattern de nommage : `{original}.imagearm.{suffix}`
- Suffixes : `.tmp`, `.gpu.png`, `.quant.png`, `.oxi.png`, `.crush.png`, `.adv.png`, `.jpegoptim.jpg`, `.moz.jpg`, etc.
- Remplacement atomique : backup original → move optimisé → trash backup
- Nettoyage systématique via `cleanupTemps(around:)` en `defer`

## Accélération GPU (Metal)

### GPUProcessor (`Services/GPUProcessor.swift`)

**Design** : Singleton optionnel (`GPUProcessor.shared: GPUProcessor?`). Si le GPU Metal n'est pas disponible, le champ est `nil` et les étapes GPU sont silencieusement ignorées.

**Marqué `@unchecked Sendable`** car :
- Toutes les propriétés sont immutables après `init()`
- Les méthodes publiques n'utilisent que des variables locales
- Les objets Metal (device, commandQueue) et CIContext sont thread-safe

### Shaders Metal (compilés à l'exécution)

#### `quantize_dither`
- Quantization des couleurs avec dithering mixte Bayer 8x8 + blue noise
- Paramètres : `colorLevels` (basé sur qualité), `ditherStrength` (0.5-1.5)
- Dispatché en groupes de 16×16 threads

#### `build_histogram`
- Construction d'histogramme 5 bits/canal (32×32×32 = 32 768 entrées)
- Utilise `atomic_fetch_add_explicit` pour la concurrence
- Préparé pour future quantization median-cut (non utilisé actuellement)

### Encodage JPEG hardware
- Utilise `CGImageDestination` avec `kCGImageDestinationLossyCompressionQuality`
- Exploite l'encodeur matériel Apple Silicon via ImageIO
- Option `kCGImageDestinationOptimizeColorForSharing`

## Gestion de la concurrence

### Niveaux de concurrence

| Composant | Mécanisme | Isolation |
|---|---|---|
| `ImageStore` | `@MainActor` | Thread principal, état UI |
| `ImageOptimizer` | `actor` | Isolation actor, appels async |
| `GPUProcessor` | `@unchecked Sendable` (singleton) | Thread-safe par design |
| `ToolManager` | `Sendable` (final class) | Lecture seule après init |
| `ImageFile` | `@MainActor` | Thread principal, état UI |

### TaskGroup pour le parallélisme

`ImageStore.optimizeAll()` utilise `withTaskGroup` avec un pool de taille `maxConcurrent` (configurable 2/4/8/16). L'implémentation utilise un pattern producteur-consommateur :

```swift
while index < pending.count {
    if running < maxConc {
        group.addTask { await optimizer.optimize(file: ...) }
        running += 1
    } else {
        await group.next()  // attend qu'un slot se libère
        running -= 1
    }
}
```

### Process externe

`ImageOptimizer.run()` lance les outils CLI via `Process` avec `withCheckedContinuation` + `terminationHandler`, ce qui libère l'actor pendant l'exécution du processus externe.

## Détection des outils (ToolManager)

**Stratégie de recherche** (dans l'ordre) :
1. `/opt/homebrew/bin` (Homebrew Apple Silicon)
2. `/usr/local/bin` (Homebrew Intel / installations manuelles)
3. `/usr/bin` (outils système)
4. `/opt/homebrew/opt/mozjpeg/bin` (mozjpeg keg-only)
5. `/usr/local/opt/mozjpeg/bin` (mozjpeg keg-only Intel)
6. Fallback : `which` via Process

**Outils supportés** : pngquant, oxipng, pngcrush, jpegtran (mozjpeg), gifsicle, svgo, cwebp, tiffutil (macOS natif). HEIF et AVIF utilisent ImageIO natif via GPUProcessor.

## Niveaux d'optimisation

| Niveau | GPU | PNG lossy | JPEG lossy | Outils PNG | Outils JPEG | Temps estimé |
|---|---|---|---|---|---|---|
| Rapide | Non | Non | Non | oxipng -o2 | jpegoptim + mozjpeg | ~1s/image |
| Standard | Non | Non | Non | oxipng -o4 + advpng | jpegoptim + mozjpeg | ~3s/image |
| Maximum | Oui | Oui | Oui | GPU + pngquant + oxipng -o6 + pngcrush + advpng | GPU HW + jpegoptim + mozjpeg | ~8s/image |
| Ultra | Oui | Oui | Oui | GPU + pngquant + oxipng -o6 + pngcrush brute + advpng | GPU HW + jpegoptim + mozjpeg | ~20s/image |

## Entitlements

```xml
com.apple.security.app-sandbox = false       # Pas de sandbox
com.apple.security.files.user-selected.read-write = true
com.apple.security.files.downloads.read-write = true
com.apple.security.device.gpu = true          # Accès Metal
```

## Points d'entrée

| Point d'entrée | Fichier | Description |
|---|---|---|
| Application | `ImageArmApp.swift` | `@main struct ImageArmApp: App` |
| Open URL | `AppDelegate.application(_:open:)` | Gestion `open -a ImageArm fichier.png` |
| CLI wrapper | `~/.local/bin/imagearm` | Script shell → `open -a ImageArm` |
| Finder Action | `~/Library/Services/Optimiser avec ImageArm.workflow` | Quick Action Finder |
