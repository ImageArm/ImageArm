#!/usr/bin/env bash
# validate-release.sh — Validation automatisée pre-release pour ImageArm
#
# Vérifie : signatures, Hardened Runtime, deployment target, dépendances
# dynamiques et taille du bundle .app.
#
# Usage :
#   bash tools/scripts/validate-release.sh [chemin/vers/ImageArm.app]
#
# Si aucun chemin n'est fourni, utilise build/ImageArm.app par défaut.
#
# ═══════════════════════════════════════════════════════════════════════
# PROCÉDURE DE TEST MAC VIERGE (manuelle, non automatisable) :
# ═══════════════════════════════════════════════════════════════════════
#   1. Transférer le DMG notarié sur un Mac vierge (ou VM macOS propre)
#      sans Xcode ni Developer Tools installés.
#   2. Ouvrir le DMG — Gatekeeper ne doit afficher AUCUN avertissement.
#   3. Glisser ImageArm.app dans /Applications.
#   4. Lancer l'app — aucun dialogue "développeur non identifié".
#   5. Tester chaque pipeline : PNG, JPEG, HEIF, SVG, WebP.
#   6. Tester le mode headless :
#      /Applications/ImageArm.app/Contents/MacOS/ImageArm --headless test.png
#   7. Tester Quick Action : ./install-finder-action.sh + clic droit Finder.
#   8. Tester open -a ImageArm test.png.
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/build/ImageArm.app}"
MACOS_DIR="$APP_PATH/Contents/MacOS"
MAX_BUNDLE_SIZE_MB=100
MIN_DEPLOYMENT_TARGET="14.0"

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

echo "🔍 Validation pre-release : $APP_PATH"
echo ""

# ── 1. Vérifier que le bundle existe ─────────────────────────────────────────

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Bundle introuvable : $APP_PATH"
    echo "   Lancer 'make release' d'abord."
    exit 1
fi

# ── 2. Signature récursive du bundle (--deep --strict) ───────────────────────

echo "── Signature du bundle ──"
if codesign --verify --deep --strict --verbose=0 "$APP_PATH" 2>&1; then
    pass "codesign --deep --strict : valide"
else
    fail "codesign --deep --strict : ÉCHEC"
fi

# ── 3. Gatekeeper assessment (spctl) ────────────────────────────────────────

echo "── Gatekeeper (spctl) ──"
SPCTL_OUT=$(spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true)
if echo "$SPCTL_OUT" | grep -qi "accepted"; then
    pass "spctl : accepted ($(echo "$SPCTL_OUT" | grep -o 'source=.*'))"
else
    fail "spctl : $SPCTL_OUT"
fi

# ── 4. Binaires individuels : codesign + Hardened Runtime ────────────────────

echo "── Binaires dans Contents/MacOS/ ──"
for bin in "$MACOS_DIR"/*; do
    name=$(basename "$bin")
    [ ! -f "$bin" ] && continue

    # Codesign
    if ! codesign --verify --verbose=0 "$bin" 2>/dev/null; then
        fail "$name : signature invalide"
        continue
    fi

    # Hardened Runtime
    FLAGS=$(codesign --display --verbose "$bin" 2>&1 | grep "flags=" || true)
    if echo "$FLAGS" | grep -q "runtime"; then
        pass "$name : signé + Hardened Runtime"
    else
        fail "$name : Hardened Runtime ABSENT"
    fi
done

# ── 5. Deployment target (minos) ────────────────────────────────────────────

echo "── Deployment target ──"
for bin in "$MACOS_DIR"/*; do
    name=$(basename "$bin")
    [ ! -f "$bin" ] && continue

    MINOS=$(otool -l "$bin" 2>/dev/null | grep -A3 "LC_BUILD_VERSION" | grep "minos" | awk '{print $2}' | head -1)
    if [ -z "$MINOS" ]; then
        warn "$name : LC_BUILD_VERSION introuvable"
    elif [ "$(printf '%s\n' "$MIN_DEPLOYMENT_TARGET" "$MINOS" | sort -V | head -1)" = "$MIN_DEPLOYMENT_TARGET" ]; then
        pass "$name : minos $MINOS (≥ $MIN_DEPLOYMENT_TARGET)"
    else
        # minos inférieur mais compatible (ex: svgo compilé par Bun cible 13.0)
        warn "$name : minos $MINOS (< $MIN_DEPLOYMENT_TARGET mais compatible)"
    fi
done

# ── 6. Dépendances dynamiques (otool -L) ────────────────────────────────────

echo "── Dépendances dynamiques ──"
for bin in "$MACOS_DIR"/*; do
    name=$(basename "$bin")
    [ ! -f "$bin" ] && continue

    BAD_DEPS=$(otool -L "$bin" 2>/dev/null | tail -n +2 | grep -v "/usr/lib/" | grep -v "/System/Library/" | grep -v "@rpath" | grep -v "@executable_path" | grep -v "(architecture" | grep -v "^$APP_PATH" || true)
    if [ -n "$BAD_DEPS" ]; then
        fail "$name : dépendances non-système détectées :"
        echo "$BAD_DEPS" | sed 's/^/        /'
    else
        pass "$name : dépendances système uniquement"
    fi
done

# ── 7. Taille du bundle ─────────────────────────────────────────────────────

echo "── Taille du bundle ──"
SIZE_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
SIZE_MB=$((SIZE_KB / 1024))
if [ "$SIZE_MB" -le "$MAX_BUNDLE_SIZE_MB" ]; then
    pass "Taille : ${SIZE_MB} Mo (≤ ${MAX_BUNDLE_SIZE_MB} Mo)"
else
    fail "Taille : ${SIZE_MB} Mo (> ${MAX_BUNDLE_SIZE_MB} Mo)"
fi

# ── 8. Vérification ticket de notarisation (si DMG existe) ──────────────────

echo "── Notarisation ──"
DMG_PATH="$REPO_ROOT/build/ImageArm.dmg"
if [ -f "$DMG_PATH" ]; then
    if xcrun stapler validate "$DMG_PATH" 2>&1 | grep -qi "valid"; then
        pass "DMG notarié et ticket agrafé"
    else
        warn "DMG existe mais ticket de notarisation non agrafé (lancer 'make notarize')"
    fi
else
    warn "DMG introuvable — lancer 'make dmg' puis 'make notarize'"
fi

# ── Résumé ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 Résultat : $PASS pass, $FAIL fail, $WARN warn"
if [ "$FAIL" -eq 0 ]; then
    echo "✅ VALIDATION RÉUSSIE — prêt pour test Mac vierge"
    exit 0
else
    echo "❌ VALIDATION ÉCHOUÉE — corriger les $FAIL problèmes avant distribution"
    exit 1
fi
