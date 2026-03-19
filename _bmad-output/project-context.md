---
project_name: 'imagearm'
user_name: 'Julien'
date: '2026-03-19'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'code_quality', 'workflow_rules', 'critical_rules']
status: 'complete'
rule_count: 42
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Swift 5.9** — `swift-tools-version: 5.9`, ne pas changer
- **SwiftUI macOS 14+** — `.macOS(.v14)` minimum, ne pas baisser
- **Metal** — compute shaders compilés à l'exécution via inline string source
- **Core Image / ImageIO** — traitement d'image et encodage JPEG hardware Apple Silicon
- **Swift Concurrency** — async/await, Actor, TaskGroup, @MainActor
- **Xcode project** (`ImageArm.xcodeproj`, généré via `xcodegen` depuis `project.yml`) — build via `xcodebuild` ou Xcode GUI
- **Zéro dépendances SPM** — frameworks Apple uniquement, ne jamais ajouter de packages tiers
- **Outils CLI externes** (tous optionnels) : pngquant, oxipng, pngcrush, advpng, jpegoptim, mozjpeg, gifsicle, svgo, cwebp
- **Pas de sandbox** — `com.apple.security.app-sandbox = false`, intentionnel (modification fichiers in-place)

### Contraintes critiques

- Metal shaders sont inline dans `GPUProcessor.swift` — ne jamais créer de fichier `.metal` séparé
- `GPUProcessor.shared` est `Optional` — toujours gérer le cas `nil`, jamais de force-unwrap
- `ToolManager.find()` renvoie `String?` — chaque outil manquant est silencieusement ignoré, jamais de crash

## Critical Implementation Rules

### Règles Swift / Concurrence

- **`@MainActor`** sur toutes les classes UI : `ImageStore`, `ImageFile`, `LogStore` — ne jamais créer de classe observable sans `@MainActor`
- **`actor`** pour `ImageOptimizer` — isole les appels Process ; `withCheckedContinuation` + `terminationHandler` libère l'actor pendant l'exécution
- **`@unchecked Sendable`** pour `GPUProcessor` — justifié car propriétés immutables après `init()`. Ne pas utiliser ce pattern sans la même garantie d'immutabilité
- **`ToolManager`** est `final class: Sendable` — lecture seule après init, pas d'état mutable
- **`nonisolated`** requis pour les conformances `Hashable`/`Equatable` sur classes `@MainActor` (cf. `ImageFile`)

### Patterns d'erreur

- Pas de `throw` dans les pipelines d'optimisation — erreurs capturées et reportées via `setFailed(file, message)`
- `try?` systématique pour les opérations fichier non critiques (cleanup, suppression temporaires)
- Fail silencieux pour outils manquants et étapes optionnelles — jamais de `fatalError` ou crash

### Organisation du code

- `// MARK: -` pour séparer les sections logiques dans les fichiers longs
- Un type principal par fichier (exceptions acceptées : enums associés dans le même fichier, cf. `ImageFile.swift`)
- `@Published` pour l'état observable, `@AppStorage` pour la persistance UserDefaults
- Propriétés calculées pour les agrégats — ne pas stocker de valeurs dérivées

### Règles SwiftUI

- `@StateObject` uniquement dans `ImageArmApp` — partout ailleurs `@EnvironmentObject`
- `@NSApplicationDelegateAdaptor` pour gérer les URLs ouvertes via Finder/CLI (open URL)
- Architecture à fenêtre unique : `WindowGroup` + `Settings` scene, pas de navigation stack
- Pas de `.sheet()` ni `.alert()` — UI plate, tout visible en même temps
- `VSplitView` conditionnel pour la console de logs

### Règles du pipeline d'optimisation

- **Pattern compétitif** : chaque outil produit un candidat, `keepBest()` compare les tailles et garde le plus petit
- **Fichiers temporaires** : nommés `{original}.imagearm.{suffix}` — respecter ce pattern obligatoirement
- **Cleanup** : `defer { cleanupTemps(around: path) }` en début de chaque méthode de pipeline
- **Annulation** : `guard !Task.isCancelled else { return }` entre chaque étape d'outil
- **Remplacement atomique** : backup original → move optimisé → trash backup — ne jamais écraser directement l'original
- **Isolation des outils** : `copyFile(from: bestPath, to: ...)` avant chaque outil — chaque outil travaille sur sa propre copie
- **ToolManager** : recherche `/opt/homebrew/bin` → `/usr/local/bin` → `/usr/bin` → chemins mozjpeg keg-only → fallback `which`
- Nouveau format/outil : suivre le pattern existant (méthode `optimizeXXX`, temp files, keepBest, defer cleanup)

### Règles de tests

- **Aucun test existant** — pas de test target dans le projet Xcode
- Si des tests sont ajoutés : créer un test target dans `project.yml`, régénérer avec `xcodegen generate`, et un dossier `Tests/`
- `GPUProcessor` nécessite un Mac avec GPU Metal — prévoir des skip conditionnels (`XCTSkipIf`)
- Le pipeline compétitif dépend des outils CLI installés — les tests d'intégration ne sont pas déterministes

### Qualité du code & Conventions de style

**Nommage :**
- **PascalCase** pour les types, **camelCase** pour propriétés/méthodes/variables
- Fichiers nommés d'après leur type principal — pas de préfixe/suffixe de couche

**Langue :**
- **UI et logs en français** — boutons, labels, messages d'erreur, messages de log
- **Code en anglais** — noms de variables, méthodes, commentaires techniques
- **Localisation multi-langues** — `Localizable.xcstrings` (fr/en/de/it/nl) ; `sourceLanguage: fr`, `developmentRegion: en` (fallback anglais) ; utiliser `String(localized:)` dans les Services/Models et `Text("clé")` dans SwiftUI

**Logging :**
- Utiliser `optiLog(_:level:)` partout — jamais `print()` ni `NSLog()`
- 5 niveaux : `.info`, `.success`, `.warning`, `.error`, `.gpu`
- Format logs optimisation : `"[step/total] filename : tool..."` et `"filename : size1 -> size2 (-saved, pct%)"`

**Documentation :**
- Commentaires `///` uniquement pour les méthodes/types non évidents
- Pas de docstrings systématiques — code auto-explicatif privilégié

### Workflow de développement

- **Build dev** : `xcodebuild -project ImageArm.xcodeproj -scheme ImageArm build` ou Run ▶ dans Xcode
- **Build release** : `xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -configuration Release build`
- **Packaging** : Archive → Export depuis Xcode (remplace l'ancien `package.sh`)
- **Installation services** : `./install-finder-action.sh` pour Quick Action Finder + CLI wrapper
- **Distribution** : hors App Store uniquement, signature automatique via Xcode
- **Notarisation** : `xcrun notarytool` pour distribution publique
- **Régénération projet** : `xcodegen generate` après modification de `project.yml`

### Règles critiques "Don't-Miss"

**Anti-patterns interdits :**
- Ne jamais ajouter de dépendance SPM — zéro dépendances par design
- Ne jamais écraser un fichier original directement — toujours backup → move → trash (`safeReplace`)
- Ne jamais `force-unwrap` `GPUProcessor.shared` — c'est un `Optional` par design
- Ne jamais utiliser `print()` ou `NSLog()` — toujours `optiLog()`
- Ne jamais créer de fichier `.metal` séparé — shaders inline dans `GPUProcessor.swift`
- Ne jamais ajouter de sandbox — accès fichier libre requis pour modification in-place

**Patterns de concurrence critiques :**
- `run()` ne throw jamais — toujours `await run(...)`, checker `result.exitCode == 0` après (pas `try await`)
- Pool de concurrence dans `optimizeAll()` est un pattern producteur-consommateur intentionnel — ne pas simplifier en lançant toutes les tâches d'un coup
- Actor → UI : seul pattern autorisé = `await MainActor.run { file.status = ... }`
- `try?` sur les opérations de cleanup est voulu — ne pas remplacer par `try`

**Edge cases :**
- Un outil peut produire un fichier plus gros → `keepBest()` garde le plus petit
- Fichier déjà optimal → status `.alreadyOptimal`, pas d'erreur
- `Task.isCancelled` doit être vérifié entre chaque étape du pipeline
- `cleanupTemps(around:)` ne nettoie que les `.pngopti.*` du même fichier source, pas tout le dossier

**Sécurité fichiers :**
- `safeReplace()` restaure le backup si le move échoue — ne jamais simplifier
- `cleanupIfNot()` protège le meilleur candidat actuel de la suppression
- Fichiers temporaires préfixés par le nom original — pas de collision entre fichiers différents

**Ajout d'un nouveau format (checklist obligatoire) :**
1. `ImageFormat` enum dans `ImageFile.swift`
2. `supportedExtensions` dans `ImageStore`
3. `supportedTypes` (UTType) dans `ImageStore`
4. Nouvelle méthode `optimizeXXX()` dans `ImageOptimizer` + case dans `optimize()`

---

## Usage Guidelines

**Pour les agents IA :**
- Lire ce fichier avant d'implémenter du code
- Suivre TOUTES les règles exactement comme documentées
- En cas de doute, préférer l'option la plus restrictive
- Mettre à jour ce fichier si de nouveaux patterns émergent

**Pour les humains :**
- Garder ce fichier lean et focalisé sur les besoins des agents
- Mettre à jour quand la stack technologique change
- Revoir périodiquement pour retirer les règles devenues évidentes

Dernière mise à jour : 2026-03-11
