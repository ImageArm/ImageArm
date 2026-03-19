#!/usr/bin/env bash
# build-oxipng.sh — Compile oxipng en arm64 (Rust pur)
# Version cible : 10.1.0 (tag v10.1.0)
# Feature zopfli activée pour meilleure compression

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/oxipng"
BIN_DIR="$REPO_ROOT/tools/bin"
OUT="$BIN_DIR/oxipng"

echo "🔨 Compilation oxipng (Rust pur, arm64)..."

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
    echo "  ❌ Submodule oxipng non initialisé : git submodule update --init tools/submodules/oxipng"
    exit 1
fi

# 4. Compiler avec feature zopfli
echo "  🔧 cargo build --release --features zopfli --target aarch64-apple-darwin..."
cd "$SUBMODULE"
MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --features zopfli --target aarch64-apple-darwin 2>&1 | tail -5
cd "$REPO_ROOT"

# 5. Copier le binaire
BUILD_OUT="$SUBMODULE/target/aarch64-apple-darwin/release/oxipng"
if [ ! -f "$BUILD_OUT" ]; then
    echo "  ❌ Binaire oxipng non trouvé après build : $BUILD_OUT"
    exit 1
fi
cp "$BUILD_OUT" "$OUT"

# 6. Vérification
ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire oxipng n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ oxipng compilé : $SIZE — arm64 (avec zopfli)"
