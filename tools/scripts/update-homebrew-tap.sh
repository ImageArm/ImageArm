#!/usr/bin/env bash
# update-homebrew-tap.sh — Met à jour le cask Homebrew après une nouvelle release
#
# Usage :
#   bash tools/scripts/update-homebrew-tap.sh [version]
#
# Exemples :
#   bash tools/scripts/update-homebrew-tap.sh          # utilise la dernière release GitHub
#   bash tools/scripts/update-homebrew-tap.sh 1.3.0    # version explicite
#
# Prérequis : gh (GitHub CLI), git

set -euo pipefail

REPO="ImageArm/ImageArm"
TAP_REPO="ImageArm/homebrew-tap"
GH_ACCOUNT="ImageArm"
TAP_CASK="Casks/imagearm.rb"
TMPDIR_TAP="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TAP"' EXIT

# ── 1. Déterminer la version cible ───────────────────────────────────────────

if [ "${1:-}" != "" ]; then
    VERSION="$1"
    TAG="v$VERSION"
else
    echo "⏳ Récupération de la dernière release..."
    TAG=$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName')
    VERSION="${TAG#v}"
fi

echo "🎯 Version cible : $VERSION (tag $TAG)"

# ── 2. Récupérer le sha256 du DMG depuis les assets de la release ───────────

echo "⏳ Récupération du sha256..."
SHA256=$(gh release view "$TAG" --repo "$REPO" --json assets \
    --jq '.assets[] | select(.name | endswith(".dmg")) | .digest' \
    | sed 's/sha256://')

if [ -z "$SHA256" ]; then
    echo "❌ SHA256 introuvable pour le tag $TAG — vérifier que le DMG est bien attaché à la release."
    exit 1
fi

DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/ImageArm-${VERSION}.dmg"
echo "✅ sha256 : $SHA256"
echo "✅ URL    : $DMG_URL"

# ── 3. Cloner le tap, mettre à jour le cask ──────────────────────────────────

# `gh auth token` renvoie le token du compte ACTIF. Si c'est madjuju (droit pull
# seulement), le clone anonyme réussit mais le push final part en 403 — après
# avoir déjà publié la release. On exige le token du compte propriétaire.
TAP_TOKEN="$(gh auth token --user "$GH_ACCOUNT" 2>/dev/null || true)"
if [ -z "$TAP_TOKEN" ]; then
    echo "❌ Aucun token pour le compte $GH_ACCOUNT — lancer : gh auth login --user $GH_ACCOUNT"
    exit 1
fi

CAN_PUSH="$(GH_TOKEN="$TAP_TOKEN" gh api "repos/${TAP_REPO}" --jq '.permissions.push' 2>/dev/null || echo false)"
if [ "$CAN_PUSH" != "true" ]; then
    echo "❌ Le compte $GH_ACCOUNT n'a pas le droit push sur ${TAP_REPO}."
    exit 1
fi

echo "⏳ Clonage du tap..."
# Le token vit dans le .git/config du clone jetable, supprimé par le trap EXIT.
git clone --quiet "https://${GH_ACCOUNT}:${TAP_TOKEN}@github.com/${TAP_REPO}.git" "$TMPDIR_TAP"

CASK_FILE="$TMPDIR_TAP/$TAP_CASK"

if [ ! -f "$CASK_FILE" ]; then
    echo "❌ Fichier cask introuvable : $TAP_CASK"
    exit 1
fi

# Lire la version actuelle pour le message de commit
OLD_VERSION=$(grep '^\s*version ' "$CASK_FILE" | head -1 | grep -o '"[^"]*"' | tr -d '"')

# Remplacer version et sha256
sed -i '' "s/version \"[^\"]*\"/version \"${VERSION}\"/" "$CASK_FILE"
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

echo ""
echo "── Diff ─────────────────────────────────────────────────────────────────"
git -C "$TMPDIR_TAP" diff
echo "─────────────────────────────────────────────────────────────────────────"

# ── 4. Commit et push ────────────────────────────────────────────────────────

cd "$TMPDIR_TAP"
git add "$TAP_CASK"

# Le workflow GitHub Actions du dépôt met déjà le cask à jour à la publication
# d'une release : relancer ce script à la main tombe alors sur un arbre propre,
# et `git commit` en erreur faisait échouer le script sous set -e.
if git diff --cached --quiet; then
    echo ""
    echo "✅ Cask déjà à jour en ${VERSION} — rien à pousser."
    exit 0
fi

git commit -m "Update imagearm cask: ${OLD_VERSION} → ${VERSION}"
git push origin main

echo ""
echo "✅ Tap mis à jour : github.com/${TAP_REPO}"
echo ""
echo "📦 Installation :"
echo "   brew update && brew upgrade --cask imagearm"
echo "   # ou pour un nouvel utilisateur :"
echo "   brew install --cask imagearm/tap/imagearm"
