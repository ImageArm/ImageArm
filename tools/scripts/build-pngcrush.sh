#!/usr/bin/env bash
# build-pngcrush.sh — Compile pngcrush en arm64 (C)
# Version cible : 1.8.x (fork GitHub Kjuly)
#
# Structure du repo : les sources sont dans tools/submodules/pngcrush/pngcrush/
# Le fork intègre libpng et zlib. On utilise le Makefile fourni avec les flags arm64.
#
# Flags spéciaux nécessaires pour compiler sur macOS arm64 moderne :
#   -include math.h   — force l'inclusion de math.h avant pngpriv.h pour éviter
#                        que TARGET_OS_MAC ne déclenche l'inclusion de fp.h
#                        (header Mac Classic non disponible sur macOS moderne)
#   -DPNG_ARM_NEON_OPT=0 — désactive les optimisations NEON de libpng dont les
#                           sources ne sont pas incluses dans ce bundle

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/pngcrush"
SRC_DIR="$SUBMODULE/pngcrush"
BIN_DIR="$REPO_ROOT/tools/bin"
OUT="$BIN_DIR/pngcrush"

echo "🔨 Compilation pngcrush (C, arm64)..."

# 1. Vérifier le submodule
if [ ! -f "$SRC_DIR/pngcrush.c" ]; then
    echo "  ❌ Submodule pngcrush non initialisé"
    echo "     Lancer : git submodule update --init tools/submodules/pngcrush"
    exit 1
fi

cd "$SRC_DIR"

# 2. Nettoyer les objets précédents si présents (évite les conflits d'architecture)
rm -f *.o pngcrush 2>/dev/null || true

# 3. Compiler via le Makefile fourni avec flags arm64
echo "  🔧 make -f Makefile (arm64, NEON désactivé)..."
make -f Makefile \
     CC="cc -arch arm64 -mmacosx-version-min=14.0 -include math.h -DPNG_ARM_NEON_OPT=0" \
     LD="cc -arch arm64 -mmacosx-version-min=14.0" \
     2>&1 | grep -E "(error:|Error [0-9]|built)" | grep -v "^make\[" | tail -5 || true

# 4. Le Makefile produit ./pngcrush dans SRC_DIR
if [ ! -f "$SRC_DIR/pngcrush" ]; then
    echo "  ❌ Binaire pngcrush non produit dans $SRC_DIR"
    exit 1
fi

cp "$SRC_DIR/pngcrush" "$OUT"

# 4b. Restaurer l'état du submodule (le fork Kjuly a commité ses .o — on les restore)
cd "$SRC_DIR" && git checkout . 2>/dev/null || true

cd "$REPO_ROOT"

# 5. Vérification
ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire pngcrush n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ pngcrush compilé : $SIZE — arm64"
