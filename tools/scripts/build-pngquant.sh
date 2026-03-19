#!/usr/bin/env bash
# build-pngquant.sh — Compile pngquant en arm64 (Rust + C)
# Version cible : 3.0.x (latest stable)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/pngquant"
BIN_DIR="$REPO_ROOT/tools/bin"
OUT="$BIN_DIR/pngquant"

echo "🔨 Compilation pngquant (Rust + C, arm64)..."

# 1. Vérifier cargo
command -v cargo >/dev/null 2>&1 || { echo "  ❌ cargo requis : brew install rust"; exit 1; }
echo "  ℹ️  Rust version : $(rustc --version)"

# 2. Vérifier la target arm64
rustup target list --installed 2>/dev/null | grep -q "aarch64-apple-darwin" || {
    echo "  ❌ Target arm64 manquante : rustup target add aarch64-apple-darwin"
    exit 1
}

# 3. Vérifier le submodule
if [ ! -f "$SUBMODULE/Cargo.toml" ]; then
    echo "  ❌ Submodule pngquant non initialisé : git submodule update --init tools/submodules/pngquant"
    exit 1
fi

# 4. Compiler
echo "  🔧 cargo build --release --features static --target aarch64-apple-darwin..."
cd "$SUBMODULE"
MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --features static --target aarch64-apple-darwin 2>&1 | tail -5
cd "$REPO_ROOT"

# 5. Copier le binaire
BUILD_OUT="$SUBMODULE/target/aarch64-apple-darwin/release/pngquant"
if [ ! -f "$BUILD_OUT" ]; then
    echo "  ❌ Binaire pngquant non trouvé après build : $BUILD_OUT"
    exit 1
fi
cp "$BUILD_OUT" "$OUT"

# 6. Vérification
ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire pngquant n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ pngquant compilé : $SIZE — arm64"
