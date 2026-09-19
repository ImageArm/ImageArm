---
title: Bugs connus et résolus
category: debugging
tags: [bug, fix, diagnostic]
updated: 2026-09-19
---

# Bugs connus et résolus

## toolbar-items-conditionnels

**Symptôme** : avec une barre d'outils personnalisable (`.toolbar(id:)`), un `ToolbarItem(id:)` construit conditionnellement corrompt la disposition enregistrée et peut faire planter l'app (le déclencheur documenté : basculer l'item puis ouvrir une nouvelle fenêtre).

**Cause** : une appartenance qui apparaît/disparaît casse l'identité de personnalisation côté SwiftUI/AppKit. Bug Apple **FB15513599**, reconnu par un ingénieur DTS en mars 2026, toujours ouvert de macOS 15 à 26.3 — voir https://developer.apple.com/forums/thread/772096

**Règle** : **aucun `if` ni `ForEach` sur une collection mutable** dans le bloc `.toolbar(id:)` de `Views/ContentView.swift`. Utiliser `.disabled()` pour désactiver, jamais pour retirer.

**Historique** : le bouton Stop était `if store.isProcessing { … }` avant la v1.6. Il a été fusionné avec Optimiser en un seul item `run` toujours présent, dont le libellé/l'icône basculent sur `store.isProcessing`.

**Atténuation supplémentaire** : ImageArm remplace `CommandGroup(replacing: .newItem)` et déclare `LSMultipleInstancesProhibited`, donc il n'existe aucune commande « Nouvelle fenêtre » — le chemin de crash exact n'est pas atteignable. La règle reste appliquée par précaution.

## toolbar-visibilite-non-persistee

**Symptôme** : « Masquer la barre d'outils » (⌥⌘T) fonctionnait pendant la session, mais la barre réapparaissait au relancement. Signalé sur la v1.6.0, **corrigé en v1.6.1**.

**Cause** : AppKit écrit bien `NSToolbar Configuration mainToolbar` (`TB Is Shown = 0`) — l'écriture n'était pas le problème. C'est **SwiftUI qui repose `toolbar.isVisible = true` à la création de la fenêtre**, écrasant l'autosauvegarde avant qu'elle ne serve.

**Correctif** (`ImageArmApp.swift`) : restauration **impérative et ponctuelle** dans `AppDelegate`. `restoreToolbarVisibility()` est appelée depuis le `onAppear` de `ContentView`, en `DispatchQueue.main.async` car la barre n'est pas encore installée sur la `NSWindow` à ce moment-là ; l'état est persisté sous la clé `toolbarVisible` sur `NSWindow.willCloseNotification` et `applicationWillTerminate`.

**Ce qu'il ne faut PAS faire** : `@AppStorage` + `.toolbar(.hidden, for: .windowToolbar)`. Ce modificateur est déclaratif, donc réappliqué à chaque évaluation du corps de `ContentView` — c'est-à-dire en continu pendant un lot, `store.files` publiant à chaque fichier — et il écraserait le basculement natif de l'utilisateur en pleine optimisation.

**Vérification** : se fier à la présence de l'élément d'accessibilité `AXToolbar` sur la fenêtre, **pas** au titre de l'entrée de menu « Afficher/Masquer la barre d'outils » : ce titre ne se met pas à jour de façon fiable (quirk SwiftUI, sans conséquence fonctionnelle).

## ecran-partage-sls-software-renderer

**Symptôme** : l'app se fige (roue multicolore) après l'ouverture du sélecteur de fichiers (⌘O), sans générer de rapport de crash.

**Cause probable** : en session d'écran partagé (`ScreensharingAgent` / `ARDAgent`), macOS bascule sur le **renderer logiciel** du window server. Le seul rapport de hang observé a son thread principal bloqué sur `dlopen` dans `SkyLight __SLSGLSoftwareRendererIsLoaded` → `SLSDeviceLock` → `CoreGraphics ripd_Lock`, pendant un `NSCoreDragManager _dragUntilMouseUp`. Aucune ligne d'ImageArm dans cette pile.

**Non reproduit** : 4 scénarios testés sur la v1.6.0 (⌘O seul, ⌘O + navigation ⇧⌘G, parcours clavier avec vignettes, glisser-déposer souris dans le panneau) — l'app répond en 147-214 ms dans tous les cas, mesuré par requête d'accessibilité avec timeout. Le chemin de code de ⌘O (`showFilePicker`, `.fileImporter`) est par ailleurs **identique depuis la v1.5.1**.

**À retenir** : ne pas conclure à un plantage applicatif depuis une session d'écran partagé sans avoir rejoué sur écran local. Et pour tester un blocage, mesurer la **réactivité** (requête AX avec timeout), pas la simple existence du process : un beachball, c'est un process bien vivant.

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
