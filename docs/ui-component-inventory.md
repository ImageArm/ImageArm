# Inventaire des composants UI — ImageArm

> Mis à jour le 2026-03-31

## Vue d'ensemble

Interface SwiftUI macOS native. Design tokens centralisés dans `Utils/DesignTokens.swift` (couleurs par format, statuts, spacing). Composants dans `Sources/ImageArm/Views/`. L'UI est disponible en **5 langues** (fr, en, de, nl, it) via `Localizable.xcstrings`.

## Fenêtre principale

### ContentView (`Views/ContentView.swift`)

**Rôle** : Vue racine de la fenêtre principale. Orchestre l'affichage conditionnel et la toolbar.

**Comportement** :
- Si aucun fichier → affiche `DropZoneView`
- Si fichiers présents → affiche `FileListView` + `StatusBarView`
- Si console visible → `VSplitView` avec `FileListView` en haut et `LogConsoleView` en bas

**Fonctionnalités** :
- Drag-and-drop (`.onDrop` avec `NSItemProvider`)
- File picker natif (`.fileImporter`)
- Toolbar : sélecteur de niveau, toggle console, boutons Ajouter/Optimiser/Stop/Vider

**Raccourcis clavier** :
- `⌘O` : Ajouter des images
- `⌘↩` : Lancer l'optimisation

### DropZoneView (`Views/DropZoneView.swift`)

**Rôle** : Zone d'accueil affichée quand la liste est vide.

**Design** : Icône centrée + texte d'invitation + bordure en pointillés. Animation de surbrillance au drag-over.

### FileListView (`Views/FileListView.swift`)

**Rôle** : Tableau principal listant tous les fichiers.

**Colonnes** :
| Colonne | Contenu |
|---|---|
| (icône) | `StatusIcon` — état visuel (pending/processing/done/failed) |
| Nom | `FormatBadge` (badge coloré PNG/JPEG/HEIF/GIF/TIFF/AVIF/SVG/WebP) + nom de fichier |
| Original | Taille originale formatée |
| Progression | `ProgressCell` — barre de progression + outil en cours |
| Optimisé | `OptimizedCell` — taille après optimisation |
| Gain | `SavingsCell` — pourcentage + économie en octets |

**Menu contextuel** : Supprimer, Ré-optimiser, Afficher dans le Finder

**Interaction** : Double-clic → ouvrir dans le Finder

### StatusBarView (`Views/StatusBarView.swift`)

**Rôle** : Barre d'état en bas de la fenêtre.

**Contenu** :
- Barre de progression globale (pendant le traitement)
- Compteur de fichiers (`X/Y fichiers`)
- Outil en cours (si un seul fichier traité) ou `N en cours`
- Économie totale (taille + pourcentage)
- Résumé taille originale → taille optimisée

### WelcomeOverlay (`Views/WelcomeOverlay.swift`)

**Rôle** : Écran d'accueil affiché au premier lancement de l'application.

**Design** : Material background arrondi avec icône sparkles, titre "Bienvenue dans ImageArm", description des formats supportés, bouton "Commencer". Utilise `DesignTokens.Spacing` pour l'espacement.

## Fenêtre de réglages

### SettingsView (`Views/SettingsView.swift`)

**Rôle** : Préférences de l'application (accessible via `⌘,`).

**Onglets** :

#### Onglet "Optimisation"
- **Sélecteur de niveau** : 4 boutons (Rapide/Standard/Maximum/Ultra) via `LevelButton`
- **Détail du niveau** : `LevelDetailView` — description + grille des outils par format (PNG, JPEG, GIF, métadonnées)
- **Qualité personnalisée** : toggles lossy PNG/JPEG + sliders de qualité (30-100%)
- **Performance** : sélecteur d'optimisations simultanées (2/4/8/16)

#### Onglet "Outils"
- Liste des outils CLI avec statut (installé/manquant)
- Chemin d'installation affiché
- Bouton "Copier install" pour les outils manquants
- Commande d'installation groupée en bas

### LogConsoleView (`Views/LogConsoleView.swift`)

**Rôle** : Console de logs intégrée (panneau rétractable).

**Composants** :
- Header avec compteur de lignes + bouton vider
- `ScrollView` auto-scrolling avec `LazyVStack`
- `LogEntryRow` : timestamp + icône colorée par niveau + message

## Sous-composants réutilisables

| Composant | Fichier | Description |
|---|---|---|
| `StatusIcon` | FileListView.swift | Icône d'état par fichier (circle/spinner/checkmark/warning) |
| `FormatBadge` | FileListView.swift | Badge coloré du format (utilise `DesignTokens.FormatColor`) |
| `ProgressCell` | FileListView.swift | Barre de progression + label outil |
| `OptimizedCell` | FileListView.swift | Affichage taille optimisée |
| `SavingsCell` | FileListView.swift | Affichage gain (% + octets) |
| `LevelButton` | SettingsView.swift | Bouton de sélection de niveau |
| `LevelDetailView` | SettingsView.swift | Panneau détaillé d'un niveau d'optimisation |
| `LogEntryRow` | LogConsoleView.swift | Ligne de log avec timestamp et couleur |
| `WelcomeOverlay` | WelcomeOverlay.swift | Écran d'accueil premier lancement |

## Design Tokens (`Utils/DesignTokens.swift`)

Système centralisé de couleurs et d'espacement utilisé dans toute l'UI.

### Couleurs par format (`DesignTokens.FormatColor`)

| Format | Couleur |
|---|---|
| PNG | Bleu (`Color.blue`) |
| JPEG | Orange (`Color.orange`) |
| HEIF | Violet (`Color.purple`) |
| GIF | Rose (`Color.pink`) |
| TIFF | Indigo (`Color.indigo`) |
| AVIF | Menthe (`Color.mint`) |
| SVG | Teal (`Color.teal`) |
| WebP | Cyan (`Color.cyan`) |
| Inconnu | Gris (`Color.gray`) |

### Couleurs de statut (`DesignTokens.StatusColor`)

| Statut | Couleur |
|---|---|
| Succès | Vert (`Color.green`) |
| Erreur | Rouge (`Color.red`) |
| Avertissement | Orange (`Color.orange`) |
| En attente | Secondaire (`Color.secondary`) |
| En cours | Accent (`Color.accentColor`) |

### Espacement (`DesignTokens.Spacing`)

| Token | Valeur |
|---|---|
| xs | 4 pt |
| sm | 8 pt |
| md | 12 pt |
| lg | 16 pt |
| xl | 24 pt |
