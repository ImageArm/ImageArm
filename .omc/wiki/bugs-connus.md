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
