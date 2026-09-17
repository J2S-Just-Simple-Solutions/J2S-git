# J2S Git (`jgit`)

## Présentation

`jgit` est un ensemble de scripts Bash destiné à automatiser les opérations Git quotidiennes au sein des projets J2S : création de branches, ouverture de pull requests, préparation de releases ou encore gestion de branches de démonstration. L'objectif est d'appliquer les conventions de l'équipe tout en limitant les erreurs manuelles.

## Installation

1. Clonez ce dépôt dans le répertoire de votre choix :
   ```bash
   cd /chemin/vers/votre/espace-de-travail
   git clone git@github.com:J2S-Just-Simple-Solutions/J2S-git.git
   ```
2. Ajoutez un alias dans votre shell afin d'appeler `jgit` depuis n'importe quel projet.
   - Sous macOS avec `zsh`, éditez `~/.zprofile` :
     ```bash
     nano ~/.zprofile
     ```
   - Ajoutez la ligne suivante en adaptant le chemin d'installation :
     ```bash
     alias jgit='/chemin/vers/J2S-git/jgit.sh'
     ```
   - Rechargez votre terminal ou exécutez `source ~/.zprofile`.

## Prérequis

- **macOS.** `jgit` refuse de démarrer sur un autre système : plusieurs commandes
  s'appuient sur des outils BSD dont l'équivalent GNU se comporte différemment, et
  un `feature rebase` lancé ailleurs écraserait la branche de travail au lieu de
  la rejouer. Le détail et l'état d'avancement sont dans
  [`docs/05-portabilite.md`](docs/05-portabilite.md).
- Un dépôt Git avec un remote nommé `origin` pointant vers GitHub (organisation J2S).
- Git installé en local (`git --version` doit répondre).
- Le client GitHub CLI (`gh`) installé et configuré : https://cli.github.com/
- Une branche de référence (`develop`, `develop2`, `master`, `main`…) présente sur le remote. Elle n'a pas besoin d'exister en local : `jgit` la récupère au besoin, y compris sur un clone tout neuf.

Configurez ensuite GitHub CLI sur chaque dépôt projet :

```bash
gh repo set-default
```

## Paramètres par défaut et surcharge locale

Après installation, `jgit` utilise automatiquement :

```bash
j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
```

Pour adapter ces réglages à un projet précis, créez un fichier `.jgit/conf_local.sh` à la racine du dépôt (le dossier `.jgit` peut être ajouté à votre `.gitignore`). Exemple :

```bash
#!/bin/bash

j2s_remote="origin"
branch_prod="master2"
branch_preprod="develop2"
squash_threshold=8
```

Ce fichier sera automatiquement chargé par `jgit.sh` et aura priorité sur les valeurs par défaut.

## Utilisation générale

Positionnez-vous dans un dépôt Git de projet :

```bash
cd /chemin/vers/mon-projet
jgit <scope> <action> [<cible>] [options...]
```

### Scopes disponibles

- `feature` / `hotfix`
- `release`
- `demo`
- `util`

### Options globales

- `--based-on <branche>` : force la branche de référence lors d'un `start` ou d'un `rebase`.
- `--from <branche>` : ajoute une source à fusionner (option répétable).
- `--into <branche>` : définit explicitement la branche de destination.
- `--no-interaction` : ne pose aucune question et applique la réponse par défaut de chacune. Cette réponse par défaut est **toujours** celle signalée par la majuscule dans le suffixe de la question — `(Y/n)` quand valider sans rien saisir revient à dire oui, `(y/N)` quand cela revient à dire non. Il n'existe aucune question affichée `(y/n)`. Un conflit de rebase, qui exige une intervention humaine, n'est jamais validé automatiquement : la commande s'arrête proprement (voir ci-dessous).
- `--no-open` : n'ouvre pas automatiquement la pull request lors d'un `start` ou `restart`.
- `--squash` : lors d'un `rebase`, squash tous les commits de la branche de travail en un seul avant de rejouer l'historique.
- `jgit help` / `jgit -h` : affiche l'aide complète.

## Fraîcheur des branches

`jgit` travaille toujours sur la version du serveur. Chaque fois qu'il bascule
sur une branche — la vôtre, la branche de PR, `develop`, `main`, une release —
il la remet au niveau du remote en **fast-forward strict**, avant d'agir.

Trois situations, trois comportements :

| Votre branche locale | Ce que fait `jgit` |
| --- | --- |
| en retard sur le serveur | la met à jour et vous le dit |
| **en avance** (commits non poussés) | ne touche à rien et vous le signale — c'est le cas normal d'une branche sur laquelle vous venez de travailler |
| a **divergé** du serveur | s'arrête, sans rien modifier ni en local ni sur le serveur |

Deux garanties qui découlent de cette règle :

- **`jgit` ne pousse jamais à votre place.** Avoir des commits d'avance n'est pas
  une anomalie et ne bloque rien.
- **`jgit` ne choisit pas entre deux historiques.** En cas de divergence, à vous
  de réconcilier la branche (`git rebase` ou `git merge`) puis de relancer :

  ```
  La branche feature/MONPROJET-123 a divergé de origin/feature/MONPROJET-123.
  2 commit(s) uniquement en local, 1 commit(s) uniquement sur le serveur.
  jgit ne choisit pas à votre place : réconciliez la branche (rebase ou merge) puis relancez.
  ```

Deux exceptions, toutes deux explicites :

- Pendant un `rebase`, une fois l'historique réécrit, les branches divergent du
  serveur **par construction** — c'est précisément ce que le `push --force` final
  va publier. `jgit` ne les resynchronise donc pas à ce moment-là.
- Les commandes de release exigent que la branche de production soit **alignée sur
  le serveur**. Si elle porte des commits non poussés, `jgit` propose de les
  **mettre de côté** sur une branche `jgit_stash_<branche>` :

  ```
  La branche main porte 2 commit(s) que vous n'avez pas poussé(s).
  Une release doit partir de la version du serveur : jgit peut les mettre de côté sur jgit_stash_main.
  Mettre ces commits de côté ? (Y/n)
  ```

  Avec `release start`, `main` est **remise en place telle quelle** en fin de
  commande et la branche de sauvegarde est supprimée. Avec `release finish`, qui
  fait légitimement avancer `main`, les commits **restent sur la branche de
  sauvegarde** et `jgit` vous indique où les retrouver. Refuser la proposition
  arrête la commande sans rien modifier.

## Commandes par scope

### Feature & Hotfix

- `jgit feature start <ticket> [--based-on <branche>] [--no-open]` : crée ou reprend la branche `feature/<ticket>` et sa branche PR `__PR__feature/<ticket>`, pousse les commits d'initialisation et ouvre la PR (sauf `--no-open`). Identique avec `hotfix`.
- `jgit feature restart <ticket> [--no-open]` : recrée la branche de travail depuis la branche PR après vérification de l'alignement du code, supprime l'ancienne branche distante et ré-ouvre la PR si nécessaire.
- `jgit feature rebase <ticket> [--based-on <branche>] [--squash]` : orchestre le rebase complet (branches temporaires `jgit_rebase_*`, cherry-pick, force-push final). Disponible également pour `hotfix`.

#### Squash avant rebase

Le rebase rejoue les commits un par un : chaque commit peut donc générer son propre conflit. Sur une PR volumineuse, cela devient vite fastidieux.

L'option `--squash` regroupe, avant le rebase, tous les commits de la branche de travail postérieurs au commit d'initialisation `jgit` en un unique commit : il ne reste alors **qu'un seul conflit à résoudre**. Le code n'est jamais modifié (`git reset --soft`), seul l'historique de la branche est réécrit.

```bash
jgit feature rebase MONPROJET-123 --squash
```

Le message du nouveau commit est demandé de façon interactive ; laisser la saisie vide reprend le message du premier commit squashé (le message est repris automatiquement avec `--no-interaction`).

Sans l'option, si la branche contient plus de 8 commits, `jgit` vous le rappelle et propose le squash. La réponse par défaut est **non** : le squash reste une décision explicite, valider sans rien saisir conserve l'historique complet. Le seuil est modifiable via `squash_threshold` dans `.jgit/conf_local.sh`.

Pour la même raison, `--no-interaction` ne déclenche jamais le squash : il applique la réponse par défaut, donc conserve tous les commits.

Le squash n'est appliqué localement qu'après votre validation, et l'historique initial est restauré si vous interrompez le rebase à l'écran de confirmation.

#### Conflits pendant un rebase

Le rebase rejoue les commits par cherry-pick : en cas de conflit, `jgit` s'interrompt et vous laisse le résoudre puis le commiter dans un autre terminal avant de reprendre.

Avec `--no-interaction`, un conflit ne peut pas être résolu : la commande s'arrête sur un message d'erreur explicite après avoir remis l'environnement en ordre — cherry-pick abandonné, branches temporaires `jgit_rebase_*` supprimées, historique de la branche de travail restauré si un squash avait été appliqué. Le remote n'étant poussé qu'en toute fin de rebase, il reste intact. Relancez alors la commande sans `--no-interaction` pour traiter le conflit à la main.

### Release

- `jgit release start [<x.y.z>]` : sans argument, calcule la prochaine version à partir du dernier tag, crée ou reprend `release/x.y.z` et pousse le commit initial. Avec `x.y.z`, prépare la branche correspondante.
- `jgit release merge [<x.y.z>] --from <branche> [--into <branche>]` : s'assure que la branche de release est prête, puis fusionne en série chaque branche fournie avec `--from`. Les noms avec ou sans préfixe `__PR__` sont pris en charge.
- `jgit release finish [--into <release/x.y.z>]` : vérifie la cohérence, fusionne sur la branche de production (`branch_prod`), crée le tag, supprime la branche de release en local/distante et génère la release GitHub.

#### Conflits pendant une release

Une release ne part **jamais à moitié**. Si une fusion conflicte, `jgit` annule le
merge et s'arrête :

- pendant `release merge`, la branche de release n'est pas poussée et les sources
  restantes ne sont pas tentées — à vous de résoudre le conflit à la main, puis de
  relancer `jgit` pour les sources qui restent ;
- pendant `release finish`, **aucun tag n'est posé, rien n'est poussé** et la
  branche de release reste disponible.

Dans les deux cas l'espace de travail est rendu propre : rien n'est perdu.

### Demo

- `jgit demo start [<nom_demo>] [--based-on <branche>]` : prépare une branche `demo_<nom>` existante (checkout + fast-forward) ou en crée une nouvelle à partir de la branche fournie après confirmation.
- `jgit demo merge [--into <branche_demo>] --from feature/<ticket> [--from hotfix/<ticket>]...` : intègre successivement chaque branche listée dans la démo cible (branche courante par défaut). L'intégration procède par **rebase de la branche de démo sur la source**, suivi d'un `push --force-with-lease` : l'historique de la démo est réécrit à chaque ajout, ce qui le garde linéaire. Une branche de démo est jetable et ne doit servir qu'à la démonstration. En cas de conflit, `jgit` s'arrête et vous laisse la main (`git rebase --continue` ou `git rebase --abort`).
- `jgit demo list` : parcourt les commits `[jgit] DEMO …`, affiche les branches déjà fusionnées et suggère les commandes `jgit release merge --from ...` correspondantes.
- `jgit demo remove [--no-interaction]` : supprime la branche de démonstration sur le remote puis en local, et replace l'utilisateur sur la branche de référence.

### Utilitaires

- `jgit util clean` : supprime les branches locales temporaires créées par `jgit` (`jgit_rebase_*`, `jgit_verify_rebase_*`, `__PR__*`). Les branches `jgit_stash_*`, qui portent du travail mis de côté, ne sont **pas** touchées.
- `jgit util verify_rebase --from <branche_source> --into <branche_cible>` : vérifie si la branche source peut être rebasée sur la branche cible sans conflit. Affiche `true` ou `false` et ne laisse aucune modification en local ou sur le remote.

### Syntaxes dépréciées

Deux commandes ont changé de forme. Les anciennes restent acceptées et
fonctionnent à l'identique, mais affichent un avertissement et seront retirées
dans une prochaine version.

| Ancienne forme | Forme actuelle |
| --- | --- |
| `jgit release merge <branche>` | `jgit release merge --from <branche>` |
| `jgit clean` | `jgit util clean` |

La distinction entre les deux formes de `release merge` se fait sur le format de
l'argument : `1.2.0` ou `release/1.2.0` est une version cible, tout le reste est
traité comme une branche source. Mélanger les deux — `jgit release merge
feature/X --from feature/Y` — est refusé explicitement.

## Tests

`jgit` est couvert par une suite de tests « grandeur nature ». Les scénarios sont
écrits en Gherkin (style Cucumber), en français, et déroulent de vraies commandes
git — vrais commits, vraies branches, vrais tags — dans un dépôt jetable dont le
remote est local. Seul le client `gh` est simulé, de sorte qu'aucun test ne touche
les dépôts de l'organisation.

```gherkin
Scénario: Une feature est développée puis livrée dans une release
  Quand je lance "jgit feature start TEST-123" et que je réponds aux questions :
    | Souhaitez-vous continuer | y |
  Alors jgit se termine sans erreur
  Et la branche distante "feature/TEST-123" existe
  Et GitHub a reçu "--base=__PR__feature/TEST-123"
```

```bash
./tests/run.sh          # joue tous les scénarios
./tests/run.sh -v       # avec le déroulé complet
./tests/run.sh release  # uniquement les fichiers dont le nom contient "release"
```

Les scénarios interactifs sont joués dans un pseudo-terminal : le test vérifie
que chaque question est bien posée par `jgit` avant d'y répondre, et échoue si une
question disparaît ou si une question inattendue apparaît.

Pour écrire ou relire des scénarios confortablement, installez l'extension
Cucumber recommandée par le dépôt (VS Code la propose à l'ouverture du projet) :

```bash
code --install-extension CucumberOpen.cucumber-official
```

- Mode d'emploi des tests (lancer, écrire un scénario, étapes disponibles) :
  [`tests/README.md`](tests/README.md)
- Stratégie de test, parcours couverts, choix techniques, règles de codage et
  portabilité : [`docs/`](docs/)
