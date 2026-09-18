# Portabilité : jgit ne tourne que sur macOS

`jgit` refuse de démarrer ailleurs que sur macOS. Ce n'est pas un choix de
confort : plusieurs commandes s'appuient sur des outils **BSD**, dont
l'équivalent GNU se comporte différemment — et dans un cas au moins, la
différence détruit du travail sans le dire.

Le garde-fou est posé dans `ensure_supported_platform` (`functions.sh`), appelé
juste avant `ensure_remote` : aucune commande ne s'exécute, seule l'aide reste
accessible.

```
jgit ne fonctionne que sur macOS (système détecté : Linux).
Certaines commandes s'appuient sur des outils BSD et détruiraient du travail ailleurs.
Voir docs/05-portabilite.md pour le détail et l'état d'avancement.
```

## Pourquoi un refus plutôt qu'un avertissement

Parce que la panne est **silencieuse et destructrice**.

### `feature rebase` — perte du travail poussé (bloquant)

`rebase.sh` construit la liste des commits à rejouer avec :

```bash
local commits=($(git rev-list "$branch_PR..$branch" | tail -r))
```

`tail -r` (afficher les lignes en ordre inverse) **n'existe que sur BSD/macOS**.
GNU coreutils ne connaît pas cette option : la commande échoue, n'écrit rien, et
comme aucun code de retour n'est contrôlé, `commits` ressort **vide**.

La suite du rebase se déroule alors normalement… sur une liste vide :

1. la branche `jgit_rebase___PR__…` est construite correctement ;
2. la branche `jgit_rebase_…` est créée par-dessus, **sans aucun cherry-pick** ;
3. les deux branches écrasent les branches historiques ;
4. `git push --force` publie le résultat ;
5. `jgit` affiche **« Rebase terminé avec succès »** et sort en code 0.

Résultat : la branche de travail est publiée **vidée de tous les commits du
développeur**, sans le moindre message d'erreur. Le comportement a été reproduit
en simulant un `tail` GNU (scénario `12_portabilite.feature`).

Le correctif est connu — `git rev-list --reverse` rend le `tail` inutile — mais
il ne suffit pas à rendre `jgit` portable : il faut d'abord inventorier le reste.

### Ce qu'il reste à inventorier

Avant de lever la restriction, il faut passer en revue les autres dépendances au
système :

| Point à vérifier | Où |
| --- | --- |
| `tail -r` | `rebase.sh` (2 occurrences) — correctif connu |
| `tput` sans `TERM` exploitable | partout : les messages colorés |
| Comportement de `sed` BSD vs GNU | `functions.sh` (`get_last_commit_with_pattern`, `util_verify_rebase`) |
| `bash` 3.2 vs 5.x | tout le dépôt (voir [choix technique n°8](03-choix-techniques.md)) |
| Le bac à sable de test lui-même | `tests/lib/sandbox.sh` |

## Conséquence sur les tests

La suite de tests s'exécute donc **uniquement sur macOS**, ce qui exclut pour
l'instant une CI GitHub Actions sur `ubuntu-latest`. Deux options le jour où on
voudra une CI :

- lever les dépendances ci-dessus, puis retirer le garde-fou ;
- ou utiliser un runner `macos-latest`.

## Comment le garde-fou est testé

Le bac à sable place déjà `$SANDBOX/bin` en tête du `PATH`. L'étape
`Étant donné le système est "…" et non macOS` y dépose un faux `uname`, ce qui
suffit à faire croire à `jgit` qu'il tourne ailleurs — sans machine Linux et sans
conteneur.

Les scénarios vérifient que le refus intervient **avant** toute action, en
particulier avant qu'un `feature rebase` n'ait touché au remote.
