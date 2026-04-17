#!/usr/bin/env bash
# release.sh — Script de release complet ImageArm
#
# Usage :
#   bash tools/scripts/release.sh <version> "<notes>"
#
# Exemple :
#   bash tools/scripts/release.sh 1.3.2 "Fix: correction du truc"
#
# Étapes :
#   1. Bump version dans Info.plist
#   2. Build DMG
#   3. Commit + push (HTTPS via gh token)
#   4. GitHub Release
#   5. Tap Homebrew
#   6. Wiki (releases.md)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
WIKI_RELEASES="$ROOT/.omc/wiki/releases.md"

# ── Arguments ─────────────────────────────────────────────────────────────────

VERSION="${1:-}"
NOTES="${2:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: bash tools/scripts/release.sh <version> \"<notes>\""
    exit 1
fi

if [ -z "$NOTES" ]; then
    echo "Usage: bash tools/scripts/release.sh <version> \"<notes>\""
    exit 1
fi

# Déterminer le numéro de build (CFBundleVersion actuel + 1)
CURRENT_BUILD=$(grep -A1 'CFBundleVersion' "$ROOT/Info.plist" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/' | tr -d ' ')
BUILD=$((CURRENT_BUILD + 1))

DATE=$(date +%Y-%m-%d)

echo ""
echo "=== Release ImageArm v$VERSION (build $BUILD) ==="
echo ""

# ── 1. Bump version ────────────────────────────────────────────────────────────

echo "📝 Bump version $VERSION (build $BUILD)..."

# CFBundleShortVersionString
CURRENT_VERSION=$(grep -A1 'CFBundleShortVersionString' "$ROOT/Info.plist" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/' | tr -d ' ')
sed -i '' "s/<string>$CURRENT_VERSION<\/string>/<string>$VERSION<\/string>/1" "$ROOT/Info.plist"

# CFBundleVersion
sed -i '' "s/<string>$CURRENT_BUILD<\/string>/<string>$BUILD<\/string>/1" "$ROOT/Info.plist"

# ── 2. Build DMG ───────────────────────────────────────────────────────────────

echo "🔨 Build + DMG..."
cd "$ROOT"
xcodegen generate --quiet 2>/dev/null || xcodegen generate
make -f tools/Makefile dmg

# ── 3. Commit + push ───────────────────────────────────────────────────────────

echo "📦 Commit + push..."
git add Info.plist ImageArm.xcodeproj/project.pbxproj

# Ajouter les fichiers sources modifiés s'il y en a
git add -u Sources/ Tests/ 2>/dev/null || true

git commit -m "Chore: bump version $VERSION (build $BUILD) — ${NOTES}"

git remote set-url origin "https://ImageArm:$(gh auth token)@github.com/ImageArm/ImageArm.git"
git pull origin main --rebase
git push origin main
git remote set-url origin git@github.com-imagearm:ImageArm/ImageArm.git

# ── 4. GitHub Release ──────────────────────────────────────────────────────────

echo "🚀 GitHub Release v$VERSION..."
cp "$ROOT/build/ImageArm.dmg" "/tmp/ImageArm-$VERSION.dmg"

gh release create "v$VERSION" "/tmp/ImageArm-$VERSION.dmg" \
    --title "ImageArm $VERSION" \
    --notes "$NOTES"

# ── 5. Tap Homebrew ────────────────────────────────────────────────────────────

echo "🍺 Mise à jour Homebrew tap..."
bash "$SCRIPT_DIR/update-homebrew-tap.sh" "$VERSION"

# ── 6. Wiki ────────────────────────────────────────────────────────────────────

echo "📖 Mise à jour wiki..."

if [ -f "$WIKI_RELEASES" ]; then
    # Insérer la nouvelle release après la ligne "# Historique des releases ImageArm"
    ENTRY="
## v$VERSION (build $BUILD) — $DATE

$NOTES
"
    # Insertion après le titre H1
    TMPFILE=$(mktemp)
    awk -v entry="$ENTRY" '
        /^# Historique des releases/ { print; print entry; next }
        { print }
    ' "$WIKI_RELEASES" > "$TMPFILE"
    mv "$TMPFILE" "$WIKI_RELEASES"

    # Mettre à jour la date dans le frontmatter
    sed -i '' "s/^updated: .*/updated: $DATE/" "$WIKI_RELEASES"

    echo "  ✅ wiki/releases.md mis à jour"
else
    echo "  ⚠️  wiki/releases.md introuvable — crée le wiki avec /wiki d'abord"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────

echo ""
echo "=== ✅ Release v$VERSION livrée ==="
echo ""
echo "  GitHub  : https://github.com/ImageArm/ImageArm/releases/tag/v$VERSION"
echo "  Homebrew: brew upgrade --cask imagearm"
echo "  Wiki    : .omc/wiki/releases.md"
