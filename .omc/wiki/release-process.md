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
make -f tools/Makefile sign-tools   # ⚠️ indispensable — voir ci-dessous
rm -rf build/DerivedData build/ImageArm.app
xcodegen generate
make -f tools/Makefile dmg
# Produit : build/ImageArm.dmg
```

Deux pièges, tous deux automatisés dans `release.sh` :

1. **`make release` n'appelle pas `sign-tools`.** Les binaires de `tools/bin/` gardent la
   signature de leur dernier `sign-tools` ; fraîchement compilés, ils sont en **ad-hoc** et
   Apple rejette la notarisation d'un code interne non signé Developer ID.
2. **Le build incrémental produit un bundle invalide.** Le script post-compile recopie
   `tools/bin/` à chaque build, mais Xcode saute la phase CodeSign si l'exécutable n'a pas
   changé : le bundle reste scellé sur les anciens hachages et
   `codesign --verify --deep --strict` sort `nested code is modified or invalid`.
   D'où le `rm -rf build/DerivedData build/ImageArm.app` préalable.

Vérification avant publication :

```bash
hdiutil attach build/ImageArm.dmg -nobrowse -readonly -mountpoint /tmp/v
codesign --verify --deep --strict /tmp/v/ImageArm.app     # doit sortir silencieusement
codesign -dv /tmp/v/ImageArm.app/Contents/MacOS/gifsicle 2>&1 | grep "Developer ID"
hdiutil detach /tmp/v
```

### 3. Commit + push

⚠️ **Deux comptes `gh` coexistent sur la machine de build** :

| Compte | Droits sur `ImageArm/ImageArm` |
|---|---|
| `madjuju` (souvent l'actif) | `pull` seulement — **push refusé** |
| `ImageArm` | `admin` / `push` |

Le push HTTPS échouait parce que `gh auth token` renvoie le token du compte *actif*, pas
celui du compte nommé dans l'URL.

Le push SSH échouait, lui, pour une raison distincte — désormais corrigée, voir
[[bugs-connus#ssh-mauvais-compte]]. La clé `~/.ssh/imagearm` **est bien enregistrée sur le
compte ImageArm** ; c'est l'ordre des identités dans `~/.ssh/config` qui en présentait une
autre avant elle.

Toujours demander le token explicitement :

```bash
git add Info.plist Sources/ ImageArm.xcodeproj/ Tests/
git commit -m "Fix/Feat/Chore: description (build N)"

git remote set-url origin "https://ImageArm:$(gh auth token --user ImageArm)@github.com/ImageArm/ImageArm.git"
git pull origin main --rebase
git push origin main
git remote set-url origin git@github.com-imagearm:ImageArm/ImageArm.git
```

> `release.sh` gère tout cela : il vérifie le droit push **avant** de builder, et restaure
> l'URL SSH via un `trap` même s'il s'interrompt (sinon le token reste en clair dans
> `.git/config`).
>
> Le push SSH direct fonctionne à nouveau depuis la correction de `~/.ssh/config`.

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
