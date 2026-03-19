#!/usr/bin/env bash
# build-svgo.sh — Compile svgo via Bun en binaire arm64 Mach-O
#
# Méthode validée par le spike 1.1 (2026-03-18) :
#   Étape 1 : bun run build (rollup → dist/svgo-node.cjs)
#   Étape 2 : bun build --compile tools/scripts/svgo-entry.js
#
# ⚠️  La commande directe `bun build --compile bin/svgo.js` ÉCHOUE
#     car css-tree charge patch.json dynamiquement — indispensable
#     de passer par rollup d'abord.
#
# Résultat spike : ~60 Mo, arm64, Hardened Runtime sans allow-jit ✅

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE="$REPO_ROOT/tools/submodules/svgo"
BIN_DIR="$REPO_ROOT/tools/bin"
ENTRY="$REPO_ROOT/tools/scripts/svgo-entry.js"
OUT="$BIN_DIR/svgo"

echo "🔨 Compilation svgo (via Bun compile)..."

# 1. Vérifier bun
command -v bun >/dev/null 2>&1 || { echo "  ❌ bun requis : brew install oven-sh/bun/bun"; exit 1; }
echo "  ℹ️  Bun version : $(bun --version)"

# 2. Vérifier le submodule svgo
if [ ! -d "$SUBMODULE/bin" ] && [ ! -f "$SUBMODULE/package.json" ]; then
    echo "  ❌ Submodule svgo non initialisé : git submodule update --init tools/submodules/svgo"
    exit 1
fi

# 3. Vérifier le wrapper entry point (créé dans le spike 1.1)
if [ ! -f "$ENTRY" ]; then
    echo "  ❌ svgo-entry.js manquant : $ENTRY"
    echo "     Ce fichier devrait être versionné dans le repo (créé lors du spike 1.1)"
    exit 1
fi

# 4. Étape 1 : Installer les dépendances et builder le bundle CJS via rollup
echo "  📦 Étape 1 : bun install + bun run build (rollup → svgo-node.cjs)..."
cd "$SUBMODULE"
bun install --frozen-lockfile 2>/dev/null || bun install
# Le script build génère svgo-node.cjs (rollup) et svgo.browser.js (yarn).
# Seul svgo-node.cjs est nécessaire — l'étape yarn peut échouer si absent.
# Désactiver errexit car le script svgo utilise yarn (non installé) pour le bundle browser.
set +e
bun run build 2>&1
BUILD_EXIT=$?
set -e
if [ $BUILD_EXIT -ne 0 ]; then
    echo "  ⚠️  bun run build exit code $BUILD_EXIT (étape yarn manquante? vérification svgo-node.cjs...)"
fi

# Vérifier que le fichier critique est présent
if [ ! -f "$SUBMODULE/dist/svgo-node.cjs" ]; then
    echo "  ❌ svgo-node.cjs non produit — échec du build rollup"
    exit 1
fi
echo "  ✅ svgo-node.cjs produit"
cd "$REPO_ROOT"

# 5. Étape 2 : Compiler en binaire natif arm64
echo "  🔧 Étape 2 : bun build --compile → $OUT"
MACOSX_DEPLOYMENT_TARGET=14.0 bun build --compile "$ENTRY" --outfile "$OUT" --target=bun-darwin-arm64

# 6. Vérification
if [ ! -f "$OUT" ]; then
    echo "  ❌ Binaire svgo non produit"
    exit 1
fi

ARCH=$(file "$OUT")
if ! echo "$ARCH" | grep -q "arm64"; then
    echo "  ❌ Le binaire svgo n'est pas arm64 : $ARCH"
    exit 1
fi

SIZE=$(du -sh "$OUT" | cut -f1)
echo "  ✅ svgo compilé : $SIZE — $ARCH"
