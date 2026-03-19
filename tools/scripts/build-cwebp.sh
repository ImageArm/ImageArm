#!/usr/bin/env bash
# build-cwebp.sh — Compile cwebp en arm64 (C + CMake) depuis libwebp
# Version cible : 1.6.0 (tag v1.6.0)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/libwebp"
BUILD_DIR="$SUBMODULE/build-arm64"
BIN_DIR="$REPO_ROOT/tools/bin"
OUT="$BIN_DIR/cwebp"

echo "🔨 Compilation cwebp (C + CMake, arm64)..."

# 1. Vérifier cmake
command -v cmake >/dev/null 2>&1 || { echo "  ❌ cmake requis : brew install cmake"; exit 1; }
echo "  ℹ️  CMake version : $(cmake --version | head -1)"

# 2. Vérifier le submodule
if [ ! -f "$SUBMODULE/CMakeLists.txt" ]; then
    echo "  ❌ Submodule libwebp non initialisé : git submodule update --init tools/submodules/libwebp"
    exit 1
fi

# 3. Créer le répertoire de build (clean si CMakeCache stale)
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "  ℹ️  Nettoyage du cache CMake précédent..."
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 4. Configurer avec CMake (cwebp uniquement)
echo "  🔧 CMake configure..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DWEBP_BUILD_CWEBP=ON \
    -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_EXTRAS=OFF \
    2>&1 | tail -5

# 5. Compiler uniquement cwebp
echo "  🔧 make cwebp..."
make -j"$(sysctl -n hw.ncpu)" cwebp 2>&1 | tail -5

cd "$REPO_ROOT"

# 6. Trouver et copier le binaire
CWEBP_BIN=$(find "$BUILD_DIR" -name "cwebp" -type f | head -1)
if [ -z "$CWEBP_BIN" ] || [ ! -f "$CWEBP_BIN" ]; then
    echo "  ❌ Binaire cwebp non trouvé dans $BUILD_DIR"
    exit 1
fi

cp "$CWEBP_BIN" "$OUT"

# 7. Vérification
ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire cwebp n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ cwebp compilé : $SIZE — arm64"
