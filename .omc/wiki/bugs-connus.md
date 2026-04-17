---
title: Bugs connus et résolus
category: debugging
tags: [bug, fix, diagnostic]
updated: 2026-04-17
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

## crash-gpu-quantize

**Symptôme** : crash use-after-free dans `GPUProcessor.quantizePNG` (build 6).

**Fix (v1.3.0)** : Correction de la gestion mémoire dans le processeur GPU Metal. Pipeline PNG simplifié (retrait GPU Metal et pngcrush).
