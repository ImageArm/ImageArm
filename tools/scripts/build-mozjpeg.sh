#!/usr/bin/env bash
# build-mozjpeg.sh — Compile mozjpeg en arm64 (C + CMake)
# Produit deux binaires : cjpeg et jpegtran
# Version cible : 4.1.5 (tag v4.1.5)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/mozjpeg"
BUILD_DIR="$SUBMODULE/build-arm64"
BIN_DIR="$REPO_ROOT/tools/bin"

echo "🔨 Compilation mozjpeg (C + CMake, arm64) → cjpeg + jpegtran..."

# 1. Vérifier cmake
command -v cmake >/dev/null 2>&1 || { echo "  ❌ cmake requis : brew install cmake"; exit 1; }
echo "  ℹ️  CMake version : $(cmake --version | head -1)"

# 2. Vérifier le submodule
if [ ! -f "$SUBMODULE/CMakeLists.txt" ]; then
    echo "  ❌ Submodule mozjpeg non initialisé : git submodule update --init tools/submodules/mozjpeg"
    exit 1
fi

# 3. Créer le répertoire de build (clean si CMakeCache stale)
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "  ℹ️  Nettoyage du cache CMake précédent..."
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 4. Configurer avec CMake
# -DWITH_SIMD=0 si nasm absent (performance légèrement réduite mais fonctionnel)
SIMD_OPTION="-DWITH_SIMD=1"
if ! command -v nasm >/dev/null 2>&1; then
    echo "  ℹ️  nasm absent — SIMD désactivé (compression identique, performance réduite)"
    SIMD_OPTION="-DWITH_SIMD=0"
fi

echo "  🔧 CMake configure..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DWITH_JPEG8=1 \
    $SIMD_OPTION \
    -DENABLE_SHARED=FALSE \
    -DENABLE_STATIC=TRUE \
    2>&1 | tail -5

# 5. Compiler
echo "  🔧 make..."
make -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -10

cd "$REPO_ROOT"

# 6. Copier les deux binaires (v4.x: cjpeg-static/jpegtran-static, v5.x: cjpeg/jpegtran)
for BIN_NAME in cjpeg jpegtran; do
    DST="$BIN_DIR/$BIN_NAME"

    if [ -f "$BUILD_DIR/$BIN_NAME" ]; then
        SRC="$BUILD_DIR/$BIN_NAME"
    elif [ -f "$BUILD_DIR/${BIN_NAME}-static" ]; then
        SRC="$BUILD_DIR/${BIN_NAME}-static"
    else
        echo "  ❌ Binaire $BIN_NAME non trouvé (ni $BIN_NAME ni ${BIN_NAME}-static) dans $BUILD_DIR"
        exit 1
    fi

    cp "$SRC" "$DST"
    ARCH=$(file "$DST")
    if ! echo "$ARCH" | grep -q "arm64"; then
        echo "  ❌ $BIN_NAME n'est pas arm64 : $ARCH"
        exit 1
    fi
    SIZE=$(du -sh "$DST" | cut -f1)
    echo "  ✅ $BIN_NAME compilé : $SIZE — arm64"
done
