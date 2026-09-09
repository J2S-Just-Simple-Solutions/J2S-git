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

- Un dépôt Git avec un remote nommé `origin` pointant vers GitHub (organisation J2S).
- Git installé en local (`git --version` doit répondre).
- Le client GitHub CLI (`gh`) installé et configuré : https://cli.github.com/
- Un remote de référence (`develop`, `develop2`, `master`, `main`…) disponible en local.

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
- `--no-interaction` : ne pose aucune question et applique la réponse par défaut de chacune (celle signalée par la majuscule dans le suffixe `(y/N)`).
- `--no-open` : n'ouvre pas automatiquement la pull request lors d'un `start` ou `restart`.
- `jgit help` / `jgit -h` : affiche l'aide complète.

## Commandes par scope

### Feature & Hotfix

- `jgit feature start <ticket> [--based-on <branche>] [--no-open]` : crée ou reprend la branche `feature/<ticket>` et sa branche PR `__PR__feature/<ticket>`, pousse les commits d'initialisation et ouvre la PR (sauf `--no-open`). Identique avec `hotfix`.
- `jgit feature restart <ticket> [--no-open]` : recrée la branche de travail depuis la branche PR après vérification de l'alignement du code, supprime l'ancienne branche distante et ré-ouvre la PR si nécessaire.
- `jgit feature rebase <ticket> [--based-on <branche>]` : orchestre le rebase complet (branches temporaires `jgit_rebase_*`, cherry-pick, force-push final). Disponible également pour `hotfix`.

### Release

- `jgit release start [<x.y.z>]` : sans argument, calcule la prochaine version à partir du dernier tag, crée ou reprend `release/x.y.z` et pousse le commit initial. Avec `x.y.z`, prépare la branche correspondante.
- `jgit release merge [<x.y.z>] --from <branche> [--into <branche>]` : s'assure que la branche de release est prête, puis fusionne en série chaque branche fournie avec `--from`. Les noms avec ou sans préfixe `__PR__` sont pris en charge.
- `jgit release finish [--into <release/x.y.z>]` : vérifie la cohérence, fusionne sur la branche de production (`branch_prod`), crée le tag, supprime la branche de release en local/distante et génère la release GitHub.

### Demo

- `jgit demo start [<nom_demo>] [--based-on <branche>]` : prépare une branche `demo_<nom>` existante (checkout + fast-forward) ou en crée une nouvelle à partir de la branche fournie après confirmation.
- `jgit demo merge [--into <branche_demo>] --from feature/<ticket> [--from hotfix/<ticket>]...` : fusionne successivement chaque branche listée dans la démo cible (branche courante par défaut) en conservant un historique linéaire.
- `jgit demo list` : parcourt les commits `[jgit] DEMO …`, affiche les branches déjà fusionnées et suggère les commandes `jgit release merge --from ...` correspondantes.
- `jgit demo remove [--no-interaction]` : supprime la branche de démonstration sur le remote puis en local, et replace l'utilisateur sur la branche de référence.

### Utilitaires

- `jgit util clean` : supprime les branches locales temporaires créées par `jgit` (`jgit_rebase_*`, `__PR__*`).
- `jgit util verify_rebase --from <branche_source> --into <branche_cible>` : vérifie si la branche source peut être rebasée sur la branche cible sans conflit. Affiche `true` ou `false` et ne laisse aucune modification en local ou sur le remote.
