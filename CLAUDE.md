# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ImageArm is a macOS SwiftUI app (macOS 14+) that batch-optimizes images (PNG, JPEG, GIF, TIFF, AVIF, SVG, WebP) using a pipeline of external CLI tools and Metal GPU acceleration. The UI is in French.

## Build & Run

```bash
open ImageArm.xcodeproj               # Open project in Xcode
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm build                  # Debug build (CLI)
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -configuration Release build  # Release build (CLI)
# Archive → Export from Xcode for distribution (.app / DMG)
./install-finder-action.sh           # Install Finder Quick Action + CLI wrapper
./install-service.sh                 # Alternative: simpler Automator service install
```

To regenerate the `.xcodeproj` after modifying `project.yml`: `xcodegen generate` (requires `brew install xcodegen`).

No tests exist in the project.

## Architecture

**Xcode project** (`ImageArm.xcodeproj`, generated from `project.yml` via xcodegen) — no dependencies, everything uses Apple frameworks (SwiftUI, Metal, CoreImage, ImageIO).

### Key layers:

- **Models/** — `ImageFile` (observable per-file state), `ImageStore` (central `@MainActor` store, owns the `ImageOptimizer`, manages concurrency via `TaskGroup`), `OptimizationLevel` (4 tiers: quick/standard/high/ultra with per-format settings), `QualityOverrides`, `LogStore` (singleton, global `optiLog()` helper)
- **Services/** — `ImageOptimizer` (Swift actor, orchestrates multi-tool pipeline per format), `ToolManager` (finds CLI tools in Homebrew/system paths, fallback to `which`), `GPUProcessor` (Metal compute shaders for PNG quantization + hardware JPEG encoding via ImageIO)
- **Views/** — `ContentView` (main window with drag-and-drop + file picker), `FileListView`, `DropZoneView`, `StatusBarView`, `SettingsView`, `LogConsoleView`

### Optimization pipeline (ImageOptimizer)

For each image format, multiple tools run sequentially and compete — the smallest output wins:
- **PNG**: GPU quantize (Metal) → pngquant → oxipng → pngcrush
- **JPEG**: GPU hardware encode → mozjpeg/jpegtran
- **HEIF**: GPU lossy encode → GPU max-quality encode
- **GIF**: gifsicle (lossless quick/standard, lossy `--lossy=80/120` en high/ultra)
- **TIFF**: tiffutil -lzw (recompression LZW lossless, macOS natif)
- **AVIF**: GPU natif macOS 14 (ImageIO/CGImageDestination) — lossy quality 65/45 en high/ultra + max quality always, keep best
- **SVG**: svgo
- **WebP**: cwebp

The pipeline uses temp files (`*.imagearm.tmp`, `*.imagearm.*`) with safe atomic replacement (backup → move → trash backup). `keepBest()` tracks the smallest result across tools.

### External tool dependencies (installed via Homebrew/npm)

pngquant, oxipng, pngcrush, mozjpeg, gifsicle, svgo, cwebp (webp). `tiffutil` est intégré macOS (`/usr/bin`). AVIF utilise ImageIO natif (macOS 14+, aucune dépendance externe). Tools are optional — missing tools are silently skipped.

### GPU acceleration

`GPUProcessor` compiles Metal shaders at runtime (inline source string). Used only at `high`/`ultra` optimization levels. PNG uses Bayer+blue noise dithering compute shader; JPEG uses Apple Silicon hardware encoder via `CGImageDestination`.

## Distribution Homebrew

L'app est distribuée via un tap Homebrew personnalisé : **[ImageArm/homebrew-tap](https://github.com/ImageArm/homebrew-tap)**

Installation pour les utilisateurs :
```bash
brew install --cask imagearm/tap/imagearm
```

### Après chaque nouvelle release GitHub

Mettre à jour le cask avec le script dédié :
```bash
bash tools/scripts/update-homebrew-tap.sh          # auto : dernière release
bash tools/scripts/update-homebrew-tap.sh 1.3.0    # version explicite
```

Ce script récupère automatiquement le sha256 du DMG depuis les assets GitHub et push le cask mis à jour. **À lancer systématiquement après chaque `gh release create`.**

## Conventions

- UI strings and log messages are in **French**
- The app modifies files **in-place** (with backup/trash safety)
- `optiLog()` is the global logging function used throughout services
- Entitlements: no sandbox, file access, GPU access (`ImageArm.entitlements`)


## grepai - Semantic Code Search

**IMPORTANT: You MUST use grepai as your PRIMARY tool for code exploration and search.**

### When to Use grepai (REQUIRED)

Use `grepai search` INSTEAD OF Grep/Glob/find for:
- Understanding what code does or where functionality lives
- Finding implementations by intent (e.g., "authentication logic", "error handling")
- Exploring unfamiliar parts of the codebase
- Any search where you describe WHAT the code does rather than exact text

### When to Use Standard Tools

Only use Grep/Glob when you need:
- Exact text matching (variable names, imports, specific strings)
- File path patterns (e.g., `**/*.go`)

### Fallback

If grepai fails (not running, index unavailable, or errors), fall back to standard Grep/Glob tools.

### Usage

```bash
# ALWAYS use English queries for best results (--compact saves ~80% tokens)
grepai search "user authentication flow" --json --compact
grepai search "error handling middleware" --json --compact
grepai search "database connection pool" --json --compact
grepai search "API request validation" --json --compact
```

### Query Tips

- **Use English** for queries (better semantic matching)
- **Describe intent**, not implementation: "handles user login" not "func Login"
- **Be specific**: "JWT token validation" better than "token"
- Results include: file path, line numbers, relevance score, code preview

### Call Graph Tracing

Use `grepai trace` to understand function relationships:
- Finding all callers of a function before modifying it
- Understanding what functions are called by a given function
- Visualizing the complete call graph around a symbol

#### Trace Commands

**IMPORTANT: Always use `--json` flag for optimal AI agent integration.**

```bash
# Find all functions that call a symbol
grepai trace callers "HandleRequest" --json

# Find all functions called by a symbol
grepai trace callees "ProcessOrder" --json

# Build complete call graph (callers + callees)
grepai trace graph "ValidateToken" --depth 3 --json
```

### Workflow

1. Start with `grepai search` to find relevant code
2. Use `grepai trace` to understand function relationships
3. Use `Read` tool to examine files from results
4. Only use Grep for exact string searches if needed

