## Project setup

### Installation

First clone the repo

```sh
cd /path-to-your-j2sgit-project/
git clone git@github.com:J2S-Just-Simple-Solutions/J2S-git.git
```

### Add a jgit shortcut in your terminal

Edit your zprofile

```sh
nano ~/.zprofile
```

Add the line

```sh
alias jgit='/path-to-your-j2sgit-project/J2S-Git/jgit.sh'
```

Restart your terminal.

### prerequisites

You should have 1 remote named `origin` that head to a J2S github repository on all your local projects.
You must have your reference branch existing on local (`develop` or `master`)

You must have git install on your local.

You must have github client install on your local https://cli.github.com/

Configure you gh envrionment

```sh
gh repo set-default
```

By default jgit use the following parameters

```sh
j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
```

You can ovveride those variable for each git projects by creating a specific configuration file.

In your git project, create a file `.jgit/conf_local.sh` (create the `.jgit` folder if needed)

With the content (update with your needs)

```sh
#!/bin/bash

j2s_remote="origin"
branch_prod="master2"
branch_preprod="develop2"
```

PS : you can add `.jgit/*` in the .gitignore of your git project.

## Usage

jgit se pilote directement depuis le dossier de votre projet :

```sh
cd /chemin/vers/mon-projet
jgit <scope> <action> [<target>] [options…]
```

### Scopes disponibles

- `feature` / `hotfix`
- `release`
- `demo`
- `util`

### Options communes

- `--based-on <branch>` : branche de référence lors d'un `start` ou d'un `rebase`.
- `--from <branch>` : source d'un merge (option répétable).
- `--into <branch>` : destination explicite du merge (sinon la branche courante est utilisée quand pertinent).
- `--yes` : valide automatiquement toutes les confirmations.
- `--no-open` : n'ouvre pas automatiquement la PR lors d'un `feature/hotfix start` ou `restart`.
- `jgit help` ou `jgit -h` : affiche l'aide détaillée.

### Feature & Hotfix

- `jgit feature start <ticket> [--based-on <branch>] [--no-open]` — crée ou reprend `feature/<ticket>` ainsi que la branche PR `__PR__feature/<ticket>`. Une PR GitHub est ouverte sauf si `--no-open` est présent. Le comportement est identique avec `hotfix`.
- `jgit feature restart <ticket> [--no-open]` — recrée `feature/<ticket>` depuis la branche PR après vérification du code. Supprime et repousse la branche de travail avant de rouvrir la PR (optionnellement sans l'ouvrir grâce à `--no-open`).
- `jgit feature rebase <ticket> [--based-on <branch>]` — gère le rebase complet : vérifications, cherry-pick sur des branches temporaires `jgit_rebase_*`, renommage et force-push final. Disponible également pour `hotfix`.

### Release

- `jgit release start [<x.y.z>]` — sans cible, calcule le prochain numéro de version (`x.y.z`) à partir du dernier tag, crée ou reprend la branche `release/x.y.z` et pousse le commit d'initialisation. Avec une cible explicite, la branche `release/<x.y.z>` correspondante est préparée.
- `jgit release merge [<x.y.z>] --from <branch> [--into <branch>]` — garantit que la branche de release est prête (création ou simple checkout) puis fusionne chaque branche listée avec `--from` dans la release. Les noms avec ou sans préfixe `__PR__` sont acceptés.
- `jgit release finish [--into <release/x.y.z>]` — vérifie la cohérence de la release courante (ou de celle indiquée), fusionne dans `branch_prod`, crée le tag, supprime la branche de release localement/distante et génère la release GitHub.

### Demo

- `jgit demo start [<demo_name>] [--based-on <branch>]` — prépare une branche `demo_<nom>` existante (checkout + fast-forward) ou en crée une nouvelle basée sur la branche fournie, après confirmation.
- `jgit demo merge [--into <demo_branch>] --from feature/<ticket> [--from hotfix/<ticket>]…` — merge en série chaque branche fournie dans la démo cible (branche courante par défaut). La branche est tenue linéaire via rebase et `--force-with-lease`.
- `jgit demo list` — liste les marqueurs `[jgit] DEMO …` depuis le commit d'initialisation, affiche les branches fusionnées et suggère les commandes `jgit release merge --from …` correspondantes.
- `jgit demo remove [--yes]` — après confirmation, supprime la branche de démo sur le remote puis en local et vous replace sur la branche de référence.

### Utility

- `jgit util clean` — supprime les branches locales temporaires utilisées par jgit (`jgit_rebase_*`, `__PR__*`).
