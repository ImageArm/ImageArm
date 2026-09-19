---
title: Bugs connus et résolus
category: debugging
tags: [bug, fix, diagnostic]
updated: 2026-09-19
---

# Bugs connus et résolus

## multi-fenetres

**Symptôme** : sélectionner N fichiers dans le Finder (clic droit > Ouvrir avec > ImageArm, app fermée) ouvre N fenêtres au lieu d'une seule.

**Cause** : SwiftUI's `WindowGroup` installe son propre handler `kAEOpenDocuments`. Quand Finder envoie un Apple Event par fichier, SwiftUI crée une fenêtre pour chacun avant que `AppDelegate.application(_:open:)` soit appelé.

**Fix (v1.3.1)** : Dans `applicationWillFinishLaunching`, on surcharge le handler Apple Event avant que SwiftUI ne le fasse. Notre handler collecte toutes les URLs et appelle `application(_:open:)` une seule fois.

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
        self,
        andSelector: #selector(handleOpenDocumentsEvent(_:replyEvent:)),
        forEventClass: 0x61657674,  // kCoreEventClass 'aevt'
        andEventID: 0x6F646F63      // kAEOpenDocuments 'odoc'
    )
}
```

`LSMultipleInstancesProhibited = YES` ajouté en parallèle pour éviter les instances multiples au niveau processus.

**Tests** : `AppDelegateTests` — 10 cas couvrant multi-fichiers, pendingURLs, filtrage, Apple Events successifs.

---

## ssh-mauvais-compte

**Symptôme** : `git push` vers `github.com-imagearm` échoue en
`ERROR: Permission to ImageArm/ImageArm.git denied to madjuju`, et
`ssh -T git@github.com-imagearm` répond « Hi madjuju! » — alors que
`~/.ssh/imagearm` est bien la clé enregistrée sur le compte **ImageArm**.

**Fausse piste** : on a longtemps cru la clé rattachée au mauvais compte. Elle ne l'était
pas — son empreinte correspond exactement à la clé du compte ImageArm.

**Cause réelle** : `IdentityFile` est **cumulatif** dans `~/.ssh/config`, pas
« premier gagnant ». Un bloc `Host *` placé en tête déclarait
`IdentityFile ~/.ssh/id_rsa` ; cette clé était donc ajoutée à la liste **avant** celle du
bloc spécifique, et présentée en premier. GitHub l'acceptait (compte madjuju) sans jamais
atteindre `~/.ssh/imagearm`. `IdentitiesOnly yes` n'y change rien : il restreint aux
identités *configurées*, ce que `Host *` est aussi.

```bash
ssh -G github.com-imagearm | grep identityfile   # révèle l'ordre réel
# avant : id_rsa puis imagearm     → « Hi madjuju! »
# après : imagearm puis id_rsa     → « Hi ImageArm! »
```

**Fix** : `IdentityFile ~/.ssh/id_rsa` sorti du `Host *` de tête et replacé dans un
`Host *` en **fin** de fichier. La clé par défaut doit toujours être la dernière ;
les blocs spécifiques passent ainsi en premier. Sauvegarde : `~/.ssh/config.bak-*`.

---

## localisation-fr

**Symptôme** : l'app s'affiche en anglais (« Drop your images here ») sur un système français.

**Cause** : `Localizable.xcstrings` déclare `sourceLanguage: fr` — les chaînes françaises du
code sont les clés — mais `Info.plist` et `project.yml` déclaraient `CFBundleDevelopmentRegion: en`.
Xcode ne générait donc aucun `fr.lproj` (le bundle ne contenait que `de/en/it/nl`) et un
utilisateur français retombait sur `en.lproj`, qui a ses 91 traductions bien réelles.

**Fix (v1.5.1)** : `developmentRegion: fr` dans `project.yml` **et** `CFBundleDevelopmentRegion`
à `fr` dans `Info.plist`. Les deux doivent rester alignés sur `sourceLanguage` du catalogue.

**Vérification** :

```bash
ls build/ImageArm.app/Contents/Resources/ | grep lproj   # de, en, it, nl (fr = langue source)
/usr/libexec/PlistBuddy -c "Print :CFBundleDevelopmentRegion" build/ImageArm.app/Contents/Info.plist
open -a build/ImageArm.app --args -AppleLanguages '(fr)'
```

---

## tests-debounce

**Symptôme** : les 8 `AppDelegateTests` échouent, tous avec `store.files.count == 0`.

**Cause** : la v1.3.2 a introduit un debounce de 250 ms dans `application(_:open:)` — les URLs partent dans `batchURLs` et ne sont transmises au store qu'après `Task.sleep(250ms)`. Les tests, écrits pour la v1.3.1 synchrone, n'attendaient qu'avec deux `await Task.yield()`, très en deçà de la fenêtre.

**Fix (v1.5.0)** : helper `settleDebounce()` qui attend 400 ms.

```swift
private func settleDebounce() async {
    try? await Task.sleep(for: .milliseconds(400))
}
```

**Règle** : tout test qui passe par `application(_:open:)` doit attendre au-delà de 250 ms.

---

## tests-qualityoverrides-compile

**Symptôme** : le target `ImageArmTests` ne compilait plus du tout depuis la v1.3.3 — `Missing arguments for parameters 'preserveTimestamps', 'preserveMetadata' in call`.

**Cause** : v1.3.3 puis v1.4.0 ont ajouté deux champs à `QualityOverrides` sans mettre à jour les 3 call sites de l'init memberwise dans `QualityOverridesTests`. La suite étant rouge à la compilation, personne n'a vu que 17 autres tests étaient devenus obsolètes derrière.

**Fix (v1.5.0)** : call sites mis à jour + tests ajoutés pour `effectiveStripMetadata`.

**Leçon** : un target de test qui ne compile pas masque toutes les autres régressions. À vérifier à chaque bump qui touche un type partagé.

---

## gifsicle-jamais-compile

**Symptôme** : build Release en échec sur `PhaseScriptExecution Copier outils CLI` depuis un dépôt propre — `cp: tools/bin/gifsicle: No such file or directory`.

**Cause** : `project.yml` copiait `tools/bin/gifsicle` dans le bundle, mais le `Makefile` n'avait ni règle ni script `build-gifsicle.sh`. `make tools` ne l'a donc jamais produit. Le build ne passait que sur une machine où `tools/bin/` avait été peuplé à la main.

**Fix (v1.5.0)** : `tools/scripts/build-gifsicle.sh` (autotools, submodule `kohler/gifsicle` v1.96) + règle Makefile + `gifsicle` ajouté à `TOOLS`.

**Décalage inverse restant** : `pngcrush` est toujours dans `TOOLS` (donc compilé) mais n'est plus copié dans le bundle depuis la v1.3.0 — compilation inutile, sans conséquence fonctionnelle.

---

## crash-gpu-quantize

**Symptôme** : crash use-after-free dans `GPUProcessor.quantizePNG` (build 6).

**Fix (v1.3.0)** : Correction de la gestion mémoire dans le processeur GPU Metal. Pipeline PNG simplifié (retrait GPU Metal et pngcrush).
