---
title: Procédure de release
category: pattern
tags: [release, git, homebrew, dmg]
updated: 2026-09-19
---

# Procédure de release ImageArm

## Prérequis (dépôt fraîchement cloné)

⚠️ `make dmg` **ne compile pas** les outils CLI — il se contente de les copier depuis `tools/bin/`, qui est gitignoré. Sans cette étape, le build Release échoue sur `PhaseScriptExecution Copier outils CLI`.

```bash
git submodule update --init --recursive
brew install rust oven-sh/bun/bun cmake autoconf automake
make -f tools/Makefile tools    # compile les 8 binaires (~5 min)
```

Vérifier ensuite que la suite est verte — elle tourne contre les binaires embarqués :

```bash
xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -destination 'platform=macOS' test
```

> Les 2 tests `GPUBenchmarkTests` sont `skipped` tant que le corpus `Tests/fixtures/benchmark/` est vide (images gitignorées) — c'est normal.

## Étapes

### 1. Bumper la version

Dans `Info.plist` : incrémenter `CFBundleShortVersionString` et `CFBundleVersion`.

### 2. Build DMG

```bash
xcodegen generate
make -f tools/Makefile dmg
# Produit : build/ImageArm.dmg
```

### 3. Commit + push

Le push SSH échoue (clé liée au compte `madjuju`). Utiliser HTTPS + gh token :

```bash
git add Info.plist Sources/ ImageArm.xcodeproj/ Tests/
git commit -m "Fix/Feat/Chore: description (build N)"

git remote set-url origin "https://ImageArm:$(gh auth token)@github.com/ImageArm/ImageArm.git"
git pull origin main --rebase
git push origin main
git remote set-url origin git@github.com-imagearm:ImageArm/ImageArm.git
```

### 4. GitHub Release

Le DMG **doit** s'appeler `ImageArm-X.Y.Z.dmg` (le tap Homebrew cherche ce nom) :

```bash
cp build/ImageArm.dmg /tmp/ImageArm-X.Y.Z.dmg
gh release create vX.Y.Z /tmp/ImageArm-X.Y.Z.dmg \
  --title "ImageArm X.Y.Z" \
  --notes "## Changements\n- ..."
```

### 5. Tap Homebrew

```bash
bash tools/scripts/update-homebrew-tap.sh
```

### 6. Wiki

Mettre à jour [[releases]] avec les changements de la version livrée.

## Script global

```bash
bash tools/scripts/release.sh X.Y.Z "Description du fix"
```

Voir `tools/scripts/release.sh` pour l'automatisation complète.
