# jgit — notes pour travailler sur ce dépôt

`jgit` est l'outil git de J2S : des scripts bash qui appliquent les conventions
de l'équipe (feature/hotfix et leurs branches `__PR__`, releases, démos). Tout
le projet — code, messages, documentation, tests — est **en français**.

## Où est quoi

| Fichier | Rôle |
| --- | --- |
| `jgit.sh` | point d'entrée : options, aide (`help()`), aiguillage des commandes |
| `functions.sh` | socle : couleurs, garde-fous, branche d'origine, `switch_branch` (seul `git checkout` du dépôt) |
| `json.sh` | contrat `--json` : fragments JSON, `json_emit`, `jgit_fail` |
| `replay.sh` | moteur de rejeu commun (cherry-pick, pause/reprise sur conflit, état `.git/jgit/operation.state`) |
| `feature.sh`, `rebase.sh`, `release.sh` | feature/hotfix, rebase, release |
| `demo.sh`, `demo_model.sh`, `demo_engine.sh`, `demo_lifecycle.sh` | démos : commandes et vues, lecture de la recette, fabrication, archive/migration |
| `docs/` | contrat, choix techniques, règles de codage, parcours couverts ; `docs/guide/` pour les utilisateurs |
| `tests/` | suite Gherkin en français, moteur maison en bash (`tests/README.md`) |
| `ui.sh`, `ui/` | `jgit ui` : interface en terminal (TypeScript + Ink), qui n'appelle que `jgit … --json` |
| `Dockerfile`, `docker-compose.yml`, `docker/` | image `j2s/jgit:local` : ligne de commande et interface |
| `.claude/skills/jgit-demo/` | skill pour piloter les démos depuis Claude Code, dans un projet J2S |

## Règles qui ne se devinent pas

Elles sont détaillées dans `docs/04-regles-de-codage.md`. Les plus importantes :

- **Code, aide, documentation et tests changent ensemble** : `help()` dans
  `jgit.sh`, `README.md`, `docs/`, `docs/guide/`, et les scénarios. Le scénario
  « L'aide décrit exactement… » de `02_ligne_de_commande.feature` liste chaque
  commande et option.
- **bash 3.2** (macOS) **et 5.2** (Linux) : pas de tableaux associatifs, pas de
  `${var,,}`, remplacements `${s//a/b}` entre guillemets, outils système limités
  à POSIX (`docs/05-portabilite.md`).
- **Un seul `git checkout`** : celui de `switch_branch`.
- **Une erreur s'arrête par `jgit_fail <code> <exit> <message> [remède]`** ;
  avec `--json`, rien d'autre que `json_emit` n'écrit sur la sortie standard.
- **Couleurs** : variables `C_RED`… et `jgit_tput`, jamais `\033[` ni `tput`.
- Les questions passent par `confirm_action "<question>" <y|n>` (la majuscule
  du suffixe montre la réponse par défaut).
- Une branche de travail sur un dépôt partagé ne se pousse en force qu'avec
  `--force-with-lease=<ref>:<sha lu au départ>`.

## Tester

```bash
./tests/run.sh                 # macOS, bash 3.2 (≈ 6 min)
./tests/run.sh demo -v         # un sous-ensemble, avec le déroulé
./tests/run-in-docker.sh       # Linux, bash 5.2 (≈ 1 min) — même arguments
./tests/steps/generate_vscode_glue.sh   # après avoir ajouté une étape Gherkin
(cd ui && npm ci && npm test)           # l'interface : build TypeScript + tests Ink
```

Une modification n'est terminée que si les deux suites passent. Les scénarios
partent d'états réels (« reproduire, jamais fabriquer » : `tests/README.md`).
