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
#   0. Pré-vol : outils CLI présents et signés Developer ID
#   1. Bump version dans Info.plist
#   2. Build DMG (depuis un build propre) + vérification des signatures
#   3. Wiki (releases.md) — avant le commit, pour être inclus dedans
#   4. Commit + push (HTTPS via le token du compte ImageArm)
#   5. GitHub Release
#   6. Tap Homebrew
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
WIKI_RELEASES="$ROOT/.omc/wiki/releases.md"
SSH_REMOTE="git@github.com-imagearm:ImageArm/ImageArm.git"
APP_NAME="ImageArm"
GH_ACCOUNT="ImageArm"

# L'étape 3 bascule le remote en HTTPS + token. Sans ce trap, une sortie en
# erreur (push refusé, réseau) laissait le token en clair dans .git/config.
ORIGINAL_REMOTE="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "$SSH_REMOTE")"
case "$ORIGINAL_REMOTE" in
    *@github.com/*) ORIGINAL_REMOTE="$SSH_REMOTE" ;;  # run précédent interrompu
esac
restore_remote() { git -C "$ROOT" remote set-url origin "$ORIGINAL_REMOTE" 2>/dev/null || true; }
trap restore_remote EXIT

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
PLIST="/usr/libexec/PlistBuddy"
CURRENT_BUILD=$("$PLIST" -c "Print :CFBundleVersion" "$ROOT/Info.plist")
BUILD=$((CURRENT_BUILD + 1))

DATE=$(date +%Y-%m-%d)

echo ""
echo "=== Release ImageArm v$VERSION (build $BUILD) ==="
echo ""

# ── 1. Bump version ────────────────────────────────────────────────────────────

echo "📝 Bump version $VERSION (build $BUILD)..."

# PlistBuddy cible la clé exacte — le sed précédent réécrivait toute ligne
# <string> de même valeur, où qu'elle soit dans le fichier.
"$PLIST" -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Info.plist"
"$PLIST" -c "Set :CFBundleVersion $BUILD" "$ROOT/Info.plist"

# ── 2. Build DMG ───────────────────────────────────────────────────────────────

cd "$ROOT"

# Pré-vol : `make dmg` ne dépend PAS de `make tools` — il se contente de copier
# tools/bin/ (gitignoré) dans le bundle. Sur un dépôt propre, le build échoue
# sur PhaseScriptExecution avec un « No such file or directory » peu parlant.
echo "🔍 Vérification des droits d'écriture GitHub..."
CAN_PUSH="$(GH_TOKEN="$(gh auth token --user "$GH_ACCOUNT" 2>/dev/null)" \
    gh api repos/ImageArm/ImageArm --jq '.permissions.push' 2>/dev/null || echo false)"
if [ "$CAN_PUSH" != "true" ]; then
    echo "  ❌ Le compte $GH_ACCOUNT n'a pas le droit push sur ImageArm/ImageArm."
    echo "     Comptes connus : $(gh auth status 2>&1 | grep -oE 'account [a-zA-Z0-9_-]+' | sed 's/account //' | tr '\n' ' ')"
    echo "     Lancer : gh auth login --user $GH_ACCOUNT"
    exit 1
fi
echo "  ✅ $GH_ACCOUNT peut pousser"

echo "🔍 Vérification des outils CLI embarqués..."
MISSING_TOOLS=""
for TOOL in pngquant oxipng cjpeg jpegtran svgo cwebp gifsicle; do
    [ -f "$ROOT/tools/bin/$TOOL" ] || MISSING_TOOLS="$MISSING_TOOLS $TOOL"
done
if [ -n "$MISSING_TOOLS" ]; then
    echo "  ❌ Outils manquants dans tools/bin/ :$MISSING_TOOLS"
    echo "     Lancer : git submodule update --init --recursive && make -f tools/Makefile tools"
    exit 1
fi
echo "  ✅ 7 outils présents"

# Les binaires embarqués doivent porter une signature Developer ID : Xcode scelle
# le bundle sans les resigner, et Apple rejette la notarisation d'un code interne
# en signature ad-hoc. `make release` n'appelle pas sign-tools — on le fait ici.
echo "🔏 Signature des outils embarqués..."
make -f tools/Makefile sign-tools

xcodegen generate --quiet 2>/dev/null || xcodegen generate

# Build propre obligatoire : le script post-compile recopie tools/bin/ à chaque
# build, mais Xcode saute la phase CodeSign si l'exécutable n'a pas changé. On
# obtient alors un bundle scellé sur les anciens hachages — codesign --verify
# --deep sort « nested code is modified or invalid ».
echo "🧹 Nettoyage du build précédent..."
rm -rf "$ROOT/build/DerivedData" "$ROOT/build/$APP_NAME.app" "$ROOT/build/ImageArm.dmg"

# create-dmg monte un volume temporaire puis le démonte. Spotlight ou Finder le
# gardent parfois occupé une poignée de secondes : hdiutil sort alors
# « couldn't unmount - Ressource occupée » et laisse traîner le volume + le
# scratch build/rw.*.dmg, ce qui fait échouer les runs suivants en cascade.
cleanup_stale_dmg() {
    for VOL in /Volumes/dmg.*; do
        [ -d "$VOL" ] && hdiutil detach "$VOL" -force -quiet 2>/dev/null || true
    done
    rm -f "$ROOT"/build/rw.*.dmg
}

echo "🔨 Build + DMG..."
cleanup_stale_dmg
if ! make -f tools/Makefile dmg; then
    echo "  ⚠️  Échec du DMG — nettoyage des volumes résiduels et seconde tentative..."
    cleanup_stale_dmg
    sleep 5
    make -f tools/Makefile dmg
fi

# ── 2b. Vérification du DMG avant publication ─────────────────────────────────

echo "🔎 Vérification des signatures dans le DMG..."
MOUNT="$(mktemp -d)/imagearm-verify"
hdiutil attach "$ROOT/build/ImageArm.dmg" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
verify_cleanup() { hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; restore_remote; }
trap verify_cleanup EXIT

VERIFY_FAILED=0
if ! codesign --verify --deep --strict "$MOUNT/$APP_NAME.app" 2>/dev/null; then
    echo "  ❌ codesign --verify --deep a échoué sur le bundle"
    codesign --verify --deep --strict --verbose=2 "$MOUNT/$APP_NAME.app" 2>&1 | grep -v '^--' | head -10
    VERIFY_FAILED=1
fi
for TOOL in pngquant oxipng cjpeg jpegtran svgo cwebp gifsicle; do
    # --verbose=2 obligatoire : les lignes Authority= n'apparaissent pas en
    # verbosité 1, et `codesign -dv` seul faisait échouer le contrôle sur des
    # binaires pourtant correctement signés.
    if ! codesign -dv --verbose=2 "$MOUNT/$APP_NAME.app/Contents/MacOS/$TOOL" 2>&1 | grep -q "Authority=Developer ID Application"; then
        echo "  ❌ $TOOL n'est pas signé Developer ID (notarisation impossible)"
        VERIFY_FAILED=1
    fi
done
hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
trap restore_remote EXIT
[ "$VERIFY_FAILED" -eq 0 ] || { echo "❌ DMG invalide — publication annulée"; exit 1; }
echo "  ✅ Bundle et 7 outils signés Developer ID"

# ── 3. Wiki ────────────────────────────────────────────────────────────────────

# Le wiki est mis à jour AVANT le commit : tant qu'il était en dernière étape,
# sa modification arrivait après le push et n'était jamais commitée — il fallait
# rédiger l'entrée à la main après coup.
echo "📖 Mise à jour wiki..."

if [ -f "$WIKI_RELEASES" ]; then
    # L'entrée passe par un fichier, pas par `awk -v` : l'awk de macOS (BSD)
    # rejette toute variable -v contenant un retour à la ligne
    # (« awk: newline in string »), et $NOTES est systématiquement multi-ligne.
    ENTRY_FILE=$(mktemp)
    printf '\n## v%s (build %s) — %s\n\n%s\n' "$VERSION" "$BUILD" "$DATE" "$NOTES" > "$ENTRY_FILE"

    # Insertion après le titre H1
    TMPFILE=$(mktemp)
    awk -v f="$ENTRY_FILE" '
        /^# Historique des releases/ {
            print
            while ((getline line < f) > 0) print line
            close(f)
            next
        }
        { print }
    ' "$WIKI_RELEASES" > "$TMPFILE"
    mv "$TMPFILE" "$WIKI_RELEASES"
    rm -f "$ENTRY_FILE"

    # Mettre à jour la date dans le frontmatter
    sed -i '' "s/^updated: .*/updated: $DATE/" "$WIKI_RELEASES"

    echo "  ✅ wiki/releases.md mis à jour"
else
    echo "  ⚠️  wiki/releases.md introuvable — crée le wiki avec /wiki d'abord"
fi

# ── 4. Commit + push ───────────────────────────────────────────────────────────

echo "📦 Commit + push..."
git add Info.plist ImageArm.xcodeproj/project.pbxproj
git add "$WIKI_RELEASES" 2>/dev/null || true

# Ajouter les fichiers sources modifiés s'il y en a
git add -u Sources/ Tests/ docs/ tools/ project.yml 2>/dev/null || true

git commit -m "Chore: bump version $VERSION (build $BUILD) — ${NOTES}"

# `gh auth token` renvoie le token du compte ACTIF. Sur cette machine c'est
# madjuju, qui n'a que le droit pull sur ImageArm/ImageArm — d'où un 403
# « Permission denied » alors que l'URL porte le nom ImageArm. On demande
# explicitement le token du compte ImageArm, quel que soit le compte actif.
GH_PUSH_TOKEN="$(gh auth token --user "$GH_ACCOUNT" 2>/dev/null || true)"
if [ -z "$GH_PUSH_TOKEN" ]; then
    echo "  ❌ Aucun token pour le compte $GH_ACCOUNT — lancer : gh auth login --user $GH_ACCOUNT"
    exit 1
fi

git remote set-url origin "https://$GH_ACCOUNT:$GH_PUSH_TOKEN@github.com/ImageArm/ImageArm.git"
git pull origin main --rebase
git push origin main
restore_remote

# ── 5. GitHub Release ──────────────────────────────────────────────────────────

echo "🚀 GitHub Release v$VERSION..."
cp "$ROOT/build/ImageArm.dmg" "/tmp/ImageArm-$VERSION.dmg"

GH_TOKEN="$GH_PUSH_TOKEN" gh release create "v$VERSION" "/tmp/ImageArm-$VERSION.dmg" \
    --title "ImageArm $VERSION" \
    --notes "$NOTES"

# ── 6. Tap Homebrew ────────────────────────────────────────────────────────────

echo "🍺 Mise à jour Homebrew tap..."
bash "$SCRIPT_DIR/update-homebrew-tap.sh" "$VERSION"

# ── Résumé ────────────────────────────────────────────────────────────────────

echo ""
echo "=== ✅ Release v$VERSION livrée ==="
echo ""
echo "  GitHub  : https://github.com/ImageArm/ImageArm/releases/tag/v$VERSION"
echo "  Homebrew: brew upgrade --cask imagearm"
echo "  Wiki    : .omc/wiki/releases.md"
