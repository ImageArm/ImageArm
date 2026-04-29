# AGENTS.md

Référence des skills Claude Code disponibles dans ce projet. Invoquer avec `/nom-du-skill` dans le prompt.

## Développement

| Skill | Commande | Usage |
|-------|----------|-------|
| Quick spec | `/bmad-quick-spec` | Rédiger une spec technique rapide pour une petite feature ou un fix |
| Implémenter une spec | `/bmad-quick-dev` | Implémenter une quick spec validée |
| Implémenter (preview) | `/bmad-quick-dev-new-preview` | Variante avec preview — build, fix, tweak, refactor |
| Simplifier le code | `/simplify` | Relire le code modifié et corriger qualité/redondances |

## Revues

| Skill | Commande | Usage |
|-------|----------|-------|
| Revue PR | `/review` | Revue complète d'une pull request |
| Revue sécurité | `/security-review` | Audit sécurité des changements en cours sur la branche |
| Revue adversariale | `/bmad-review-adversarial-general` | Revue critique / rapport de findings |
| Revue code (multicouche) | `/bmad-code-review` | Revue parallèle : Blind Hunter + Edge Case Hunter + Acceptance Auditor |
| Edge cases | `/bmad-review-edge-case-hunter` | Analyse exhaustive des chemins non gérés et conditions limites |

## Architecture & Documentation

| Skill | Commande | Usage |
|-------|----------|-------|
| Architecte | `/bmad-architect` | Concevoir une solution technique |
| Créer architecture | `/bmad-create-architecture` | Produire un document d'architecture / ADR |
| Documenter le projet | `/bmad-document-project` | Générer la doc du projet pour le contexte IA |
| Rédacteur tech | `/bmad-tech-writer` | Rédiger ou améliorer la documentation technique |
| Générer contexte projet | `/bmad-generate-project-context` | Créer `project-context.md` avec les règles IA |

## Planification & Suivi

| Skill | Commande | Usage |
|-------|----------|-------|
| Créer PRD | `/bmad-create-prd` | Rédiger un document de spécifications produit |
| Créer epics & stories | `/bmad-create-epics-and-stories` | Découper les exigences en epics et user stories |
| Créer une story | `/bmad-create-story` | Rédiger un fichier story complet prêt à implémenter |
| Sprint planning | `/bmad-sprint-planning` | Générer le suivi du sprint depuis les epics |
| Statut sprint | `/bmad-sprint-status` | Résumer l'avancement du sprint et les risques |

## Automatisation & Config

| Skill | Commande | Usage |
|-------|----------|-------|
| Planifier un agent | `/schedule` | Lancer un agent distant sur un schedule cron |
| Boucle récurrente | `/loop` | Exécuter un prompt ou slash-command à intervalle régulier |
| Configurer Claude Code | `/update-config` | Modifier `settings.json` : hooks, permissions, env vars |
| Réduire les prompts | `/fewer-permission-prompts` | Ajouter des allowlists pour réduire les confirmations |
| Raccourcis clavier | `/keybindings-help` | Personnaliser `~/.claude/keybindings.json` |

## Recherche & Analyse

| Skill | Commande | Usage |
|-------|----------|-------|
| Recherche technique | `/bmad-technical-research` | Rapport de recherche sur une technologie ou architecture |
| Brainstorming | `/bmad-brainstorming` | Session de brainstorming avec techniques d'idéation |
| Rétro | `/bmad-retrospective` | Revue post-epic : leçons apprises et bilan |

---

> Les skills sont chargés dynamiquement — si un skill ne répond pas, vérifier qu'il est bien dans la liste `available-skills` du contexte système.
