# Tests de `jgit`

Les scénarios sont écrits en **Gherkin** (style Cucumber), en français, dans
`tests/features/*.feature`. Ils jouent de **vraies commandes git** — vrais
commits, vraies branches, vrais tags — dans un dépôt jetable. Seul GitHub est
simulé, afin de ne jamais polluer les dépôts de l'organisation.

```gherkin
Scénario: Une feature est développée puis livrée dans une release
  Quand je lance "jgit feature start TEST-123" et que je réponds aux questions :
    | Souhaitez-vous continuer | y |
  Alors jgit se termine sans erreur
  Et la branche distante "feature/TEST-123" existe
  Et GitHub a reçu "--base=__PR__feature/TEST-123"
```

## Lancer les tests

```bash
./tests/run.sh
```

| Commande | Effet |
| --- | --- |
| `./tests/run.sh` | joue tous les scénarios |
| `./tests/run.sh release` | ne joue que les fichiers dont le nom contient `release` |
| `./tests/run.sh -l` | liste les fichiers de scénarios |
| `./tests/run.sh -v` | affiche le déroulé complet (sinon, uniquement en cas d'échec) |
| `./tests/run.sh -k` | conserve les bacs à sable pour inspection après coup |

Le lanceur retourne un code de sortie non nul dès qu'un scénario échoue : il est
directement utilisable en CI ou dans un hook.

Un fichier seul peut aussi être joué directement :

```bash
./tests/lib/run_feature.sh tests/features/01_feature_vers_release.feature
```

Prérequis : `git`, `bash` et `python3` (livré avec macOS). Le vrai client `gh`
n'est **pas** nécessaire, il est remplacé par un mock.

## Ce que voit un scénario

L'étape `Étant donné un projet git initialisé pour jgit` construit un
environnement jetable et totalement isolé (`HOME` dédié, aucune configuration git
de la machine n'est lue) :

```
$SANDBOX/
  origin.git/    le remote : joue le rôle de GitHub côté git (dépôt bare local)
  repo/          le dépôt de travail, celui où jgit est exécuté
  github/        clone technique servant à simuler les actions faites sur GitHub
  bin/gh         mock du client GitHub CLI
  gh-calls.log   journal de tous les appels à gh
  home/          HOME isolé
```

Le dépôt de travail est livré avec : une branche `main`, une branche `develop`,
un tag `1.0.0` (exigé par `jgit release start`), un `.gitignore` et un fichier
`.jgit/conf_local.sh` correspondant à la configuration J2S standard.

**Chaque scénario repart d'un bac à sable neuf**, détruit à la fin (sauf avec
`-k`). Un scénario en échec n'empêche pas les suivants de tourner.

### GitHub est simulé, git est réel

- Les `git push`, `fetch`, `merge`, `rebase`, tags… sont **réellement exécutés**
  contre le remote local `origin.git`.
- Le client `gh` est remplacé par [`tests/mocks/bin/gh`](mocks/bin/gh), qui
  journalise chaque appel au lieu de contacter GitHub. Les scénarios vérifient
  donc précisément ce que `jgit` *aurait* demandé à GitHub
  (`Et GitHub a reçu "release create 1.1.0 --generate-notes"`).
- Les actions réalisées *sur* GitHub par un humain (valider et merger une PR,
  supprimer une branche) sont rejouées par des étapes dédiées
  (`Quand la PR de "…" est squash-mergée sur GitHub avec le message "…"`).

### Les scénarios interactifs sont vraiment interactifs

`jgit` pose ses questions avec `read -p`, qui n'affiche son invite que face à un
terminal. Les tests lancent donc `jgit` dans un **pseudo-terminal**
([`lib/expect.py`](lib/expect.py)) : le tableau de l'étape liste les questions
attendues et les réponses à taper.

```gherkin
Quand je lance "jgit feature start TEST-123" et que je réponds aux questions :
  | Souhaitez-vous continuer | y |
```

Si `jgit` oublie de poser une question, le scénario échoue ; s'il en pose une qui
n'était pas prévue, le scénario échoue sur un timeout au lieu de rester bloqué.

## Écrire un scénario

Créez `tests/features/<numero>_<nom>.feature` :

```gherkin
Fonctionnalité: Rebase d'une feature sur develop

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Un hotfix est créé sans ouvrir de PR
    Quand je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "hotfix/URGENT-1" existe
    Et GitHub n'a pas reçu "pr create"
```

Le fichier est automatiquement découvert par le lanceur.

Mots-clés reconnus : `Fonctionnalité:`, `Contexte:`, `Scénario:`,
`Étant donné`, `Quand`, `Alors`, `Et`, `Mais` (et leurs équivalents anglais),
les tableaux `| … | … |` et les commentaires `#`. Les étapes du `Contexte:` sont
rejouées avant chaque scénario.

## Étapes disponibles

Les valeurs sont toujours entre guillemets.

### Contexte

| Étape |
| --- |
| `Étant donné un projet git initialisé pour jgit` |

### Actions du développeur

| Étape |
| --- |
| `Quand je lance "jgit …"` |
| `Quand je lance "jgit …" et que je réponds aux questions :` + tableau `\| question \| réponse \|` |
| `Quand je commite le fichier "…" contenant "…" avec le message "…"` |
| `Quand je modifie le fichier "…" avec "…"` (sans commit : espace de travail sale) |
| `Quand je pousse la branche courante` |
| `Quand je me place sur la branche "…"` |
| `Quand je récupère les nouveautés du remote` |
| `Quand je merge la branche "…" dans la branche courante` (crée un commit de fusion) |

### Préparation du dépôt

| Étape |
| --- |
| `Étant donné je crée la branche locale "…"` / `… depuis "…"` |
| `Étant donné je supprime la branche locale "…"` |
| `Étant donné le dépôt n'a plus de remote` |
| `Étant donné le tag "…" est supprimé partout` |
| `Étant donné je note l'état de la branche distante "…"` (pour `est inchangée`) |

### Actions sur GitHub (simulé)

| Étape |
| --- |
| `Quand la PR de "…" est squash-mergée sur GitHub avec le message "…"` |
| `Quand la branche "…" est supprimée sur GitHub` |
| `Quand un autre développeur pousse le fichier "…" contenant "…" sur la branche "…" avec le message "…"` |
| `Quand le client gh échoue pour les commandes "…"` (motif `grep -E`) |

### Vérifications

| Étape |
| --- |
| `Alors jgit se termine sans erreur` / `en erreur` |
| `Et la sortie contient "…"` / `ne contient pas "…"` |
| `Et la branche locale "…" existe` / `n'existe pas` |
| `Et la branche distante "…" existe` / `n'existe pas` |
| `Et la branche distante "…" est inchangée` / `a changé` |
| `Et la branche distante "…" a N commits d'avance sur "…"` |
| `Et la branche locale "…" a N commits d'avance sur "…"` |
| `Et je suis sur la branche "…"` |
| `Et le tag "…" existe sur le remote` / `n'existe pas sur le remote` |
| `Et le fichier "…" existe sur la branche distante "…"` / `n'existe pas sur…` |
| `Et le fichier "…" de la branche distante "…" contient "…"` |
| `Et le fichier "…" existe dans le tag "…"` |
| `Et le dernier commit de "…" contient "…"` |
| `Et le dernier commit local de "…" contient "…"` |
| `Et l'historique de "…" contient "…"` / `ne contient pas "…"` |
| `Et l'historique local de "…" contient "…"` / `ne contient pas "…"` |
| `Et le fichier de travail "…" contient "…"` |
| `Et l'espace de travail est propre` / `contient encore mes modifications` |
| `Et GitHub a reçu "…"` / `n'a pas reçu "…"` |
| `Et GitHub a reçu exactement N appels` |

Une étape qui ne correspond à aucune définition fait échouer le scénario avec un
message explicite : rien ne passe silencieusement.

## Coloration et étapes dans VS Code

Le dépôt recommande l'extension officielle `CucumberOpen.cucumber-official`
(VS Code la propose à l'ouverture du projet, via `.vscode/extensions.json`) :

```bash
code --install-extension CucumberOpen.cucumber-official
```

Deux points sont déjà réglés dans `.vscode/settings.json` :

- la ligne `# language: fr` en tête de chaque `.feature` fait reconnaître les
  mots-clés français (`Fonctionnalité`, `Étant donné`…) ;
- l'extension souligne en jaune (« Undefined step ») toute étape dont elle ne
  trouve pas la définition, et elle ne sait pas lire du bash. Le fichier généré
  `tests/steps/vscode_glue.py` lui redéclare les mêmes phrases dans un format
  qu'elle comprend. Il n'est jamais exécuté par les tests.

Après avoir ajouté ou modifié une phrase dans `tests/steps/*.steps.sh` :

```bash
./tests/steps/generate_vscode_glue.sh          # régénère le fichier
./tests/steps/generate_vscode_glue.sh --check  # vérifie qu'il est à jour
```

## Ajouter une étape

Les étapes sont définies dans [`tests/steps/jgit.steps.sh`](steps/jgit.steps.sh).
Une phrase, une fonction bash ; les valeurs entre guillemets sont passées en
arguments :

```bash
step_tag_absent() {
    assert_remote_tag_missing "$1"
}
step_def "le tag {chaine} n'existe pas sur le remote" step_tag_absent
```

Marqueurs disponibles dans une phrase : `{chaine}` (valeur entre guillemets, non
vide), `{texte}` (valeur éventuellement vide), `{nombre}`.

Les fonctions utilisables dans une définition d'étape :

| Fonction | Rôle |
| --- | --- |
| `run_jgit <args…>` | lance `jgit` ; remplit `$JGIT_OUTPUT` et `$JGIT_STATUS` |
| `run_jgit_interactive <args…>` | idem, dans un pseudo-terminal |
| `expect_reset` / `expect_wait` / `expect_answer` | scénario de questions/réponses |
| `repo_git …` / `origin_git …` / `github_git …` | `git` dans le dépôt de travail / le remote / le clone « GitHub » |
| `repo_commit_file <chemin> <contenu> <message>` | vrai commit sur la branche courante |
| `repo_write_file <chemin> <contenu>` | écrit sans commiter (espace de travail sale) |
| `repo_push_current_branch`, `repo_current_branch` | |
| `repo_create_local_branch`, `repo_delete_local_branch`, `repo_merge_branch` | |
| `repo_remove_remote`, `repo_delete_tag` | |
| `github_squash_merge_pr <branche> [message]` | simule le « Squash and merge » d'une PR |
| `github_delete_branch <branche>` | simule la suppression d'une branche sur GitHub |
| `github_commit_file <branche> <chemin> <contenu> <message>` | simule le travail d'un autre développeur |
| `remote_snapshot_save <branche>` | mémorise l'état du remote pour `assert_remote_branch_unchanged` |
| `gh_calls` | journal des appels à `gh` |
| `assert_jgit_success` / `assert_jgit_failure` / `assert_jgit_output_contains` | |
| `assert_local_branch_exists` / `_missing` | |
| `assert_remote_branch_exists` / `_missing` | |
| `assert_current_branch`, `assert_remote_tag_exists` | |
| `assert_remote_file_exists` / `_missing` / `_content`, `assert_tag_file_exists` | |
| `assert_commit_subject_contains`, `assert_remote_log_contains` / `_not_contains` | |
| `assert_local_log_contains` / `_not_contains`, `assert_local_commit_subject_contains` | |
| `assert_remote_commit_count_since`, `assert_local_commit_count_since` | |
| `assert_remote_branch_unchanged` / `_changed` | |
| `assert_worktree_file_content`, `assert_worktree_clean` / `_dirty` | |
| `assert_gh_called` / `assert_gh_not_called` / `assert_gh_call_count` | |
| `assert_equals`, `assert_contains`, `assert_matches`, `info` | assertions et traces génériques |

Une assertion en échec affiche son contexte (branches présentes, sortie de la
commande…) et interrompt immédiatement le scénario.

## Échappatoire : un test en bash pur

Pour un cas trop tordu pour le Gherkin, le lanceur exécute aussi les fichiers
`tests/cases/*.test.sh` :

```bash
#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/bootstrap.sh"

test_name "un cas particulier"
sandbox_create
step "1. …"
run_jgit feature start TEST-1 --no-interaction
assert_jgit_success
test_passed
```

## Organisation

| Fichier | Rôle |
| --- | --- |
| `run.sh` | lanceur : découverte, filtrage, rapport |
| `features/*.feature` | les scénarios |
| `steps/*.steps.sh` | les définitions d'étapes |
| `lib/gherkin.sh` | moteur Gherkin (analyse + exécution) |
| `lib/sandbox.sh` | dépôt jetable, remote local, simulation de GitHub |
| `lib/interactive.sh` + `lib/expect.py` | pilotage de `jgit` dans un pseudo-terminal |
| `lib/assert.sh`, `lib/git_assert.sh` | assertions |
| `lib/bootstrap.sh` | chargement de l'ensemble |
| `mocks/bin/gh` | mock du client GitHub CLI |
| `steps/vscode_glue.py` | fichier généré, uniquement pour l'extension Cucumber de VS Code |

## Scénarios existants

116 scénarios répartis par domaine fonctionnel.

| Fichier | Couverture |
| --- | --- |
| `01_feature_vers_release.feature` | `feature start` (interactif) → commits réels → squash-merge de la PR → `release merge` → `release finish` (merge sur `main`, tag, release GitHub) |
| `02_ligne_de_commande.feature` | aide, scopes et actions inconnus, options sans valeur, options inconnues, positionnels superflus, `--`, garde-fou `ensure_remote` |
| `03_feature_start.feature` | référence `develop`/`main` selon le scope, `--based-on`, `--no-open`, refus de confirmation, les 4 combinaisons local/distant, repli de branche de référence, réponses par défaut |
| `04_feature_restart.feature` | restart après squash-merge, refus si le code diffère, `--no-open`, hotfix, cas d'une feature inconnue |
| `05_feature_rebase.feature` | rebase nominal, hotfix, `--based-on`, `--squash`, seuil de squash, refus des deux confirmations, conflits, PR déjà mergée, commit de fusion, branches non publiées |
| `06_release.feature` | `release start` (calcul de version, version explicite, sans tag, dépôt sale, reprise), `release merge` (`--from`, `--into`, sources multiples, PR non mergée), `release finish` (tag, merge, release vide, bascule de branche) |
| `07_demo.feature` | `demo start` (nom par défaut, `--based-on`, reprise, refus), `demo merge` (sources multiples, doublon, formats invalides, `--into`), `demo list`, `demo remove` |
| `08_util_et_stash.feature` | `util clean`, `util verify_rebase` (tous les refus, true/false, absence de trace), stash automatique accepté et refusé |
| `09_parcours_complets.feature` | hotfix de bout en bout, feature rebasée puis redémarrée puis livrée, démo servant de répétition, deux releases successives |

### Anomalies figées par les tests

Cinq scénarios documentent un comportement **constaté mais non souhaitable**.
Ils sont signalés par un commentaire `# ANOMALIE CONNUE` et passeront au rouge
le jour où le défaut sera corrigé — c'est voulu : la correction doit se voir.

| Scénario | Défaut |
| --- | --- |
| `04` — restart d'une feature inconnue | le garde-fou « la branche de PR n'existe pas » ne se déclenche jamais (`git ls-remote` sans `--exit-code`) : jgit publie une feature partie de nulle part |
| `06` — `release merge --into` sans fetch | `checkout_release_branch` ne rafraîchit pas les références distantes : jgit croit à tort que la PR n'est pas mergée |
| `06` — échec de `gh release create` | le code de retour n'est pas contrôlé : jgit se termine en succès alors qu'aucune release GitHub n'a été créée |
| `07` — `demo list` | le nom des branches est tronqué (`%-_-_-` et `IFS=$'-_-_-'`) : les commandes `release merge` suggérées sont inutilisables |
| `03` — aucune branche de référence | `get_reference_branch` est appelée dans une substitution de commande : son `exit_safe` ne quitte que le sous-shell et son message d'erreur ressort comme un nom de branche |
| `02_ligne_de_commande.feature` | aide, scopes et actions inconnus, options mal formées, absence de remote — et l'absence d'effet de bord après un refus |
| `03_feature_start.feature` | `feature start` / `hotfix start` en détail : branche de référence, `--based-on`, `--no-open`, refus de la confirmation, reprise d'une branche existante |
| `04_feature_restart.feature` | `feature restart` après squash-merge de la PR, refus si la PR n'est pas mergée, `--no-open`, et un scénario de caractérisation d'un comportement à corriger |

La description fonctionnelle de ces parcours est dans
[`docs/02-parcours-couverts.md`](../docs/02-parcours-couverts.md).
