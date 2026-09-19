#!/usr/bin/env bash
# build-gifsicle.sh — Compile gifsicle en arm64 (C + autotools)
# Version cible : 1.96 (tag v1.96)
#
# gifview et gifdiff sont désactivés : gifview dépend de X11 (absent des
# machines de build) et seul gifsicle est embarqué dans le .app.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/gifsicle"
BIN_DIR="$REPO_ROOT/tools/bin"
OUT="$BIN_DIR/gifsicle"

echo "🔨 Compilation gifsicle (C + autotools, arm64)..."

# 1. Vérifier autoreconf (gifsicle ne versionne pas ./configure)
command -v autoreconf >/dev/null 2>&1 || { echo "  ❌ autoconf requis : brew install autoconf automake"; exit 1; }
echo "  ℹ️  autoreconf : $(autoreconf --version | head -1)"

# 2. Vérifier le submodule
if [ ! -f "$SUBMODULE/configure.ac" ]; then
    echo "  ❌ Submodule gifsicle non initialisé : git submodule update --init tools/submodules/gifsicle"
    exit 1
fi

cd "$SUBMODULE"

# 3. Générer ./configure si absent (bootstrap.sh appelle autoreconf -i)
if [ ! -x "./configure" ]; then
    echo "  🔧 bootstrap (autoreconf)..."
    ./bootstrap.sh 2>&1 | tail -5
fi

# 4. Configurer pour arm64 / macOS 14
echo "  🔧 configure..."
./configure \
    --disable-gifview \
    --disable-gifdiff \
    CC="clang" \
    CFLAGS="-O2 -arch arm64 -mmacosx-version-min=14.0" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=14.0" \
    2>&1 | tail -5

# 5. Compiler
echo "  🔧 make..."
make -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -5

cd "$REPO_ROOT"

# 6. Récupérer le binaire
GIFSICLE_BIN="$SUBMODULE/src/gifsicle"
if [ ! -f "$GIFSICLE_BIN" ]; then
    echo "  ❌ Binaire gifsicle non trouvé dans $SUBMODULE/src/"
    exit 1
fi

mkdir -p "$BIN_DIR"
cp "$GIFSICLE_BIN" "$OUT"

# 7. Vérification
ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire gifsicle n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ gifsicle compilé : $SIZE — arm64"
