# Portabilité : macOS et Linux

`jgit` tourne sur **macOS**, le poste des développeurs, et sous **Linux**, pour
les conteneurs Docker et les agents Jenkins. Les deux plateformes sont jouées
par la suite de tests :

```bash
./tests/run.sh             # macOS, bash 3.2 d'Apple
./tests/run-in-docker.sh   # Linux (Debian bookworm), bash 5.2, outils GNU
```

Tout autre système est refusé avant la moindre action. Le garde-fou est posé
dans `ensure_supported_platform` (`functions.sh`), appelé juste avant
`ensure_remote` : aucune commande ne s'exécute, seule l'aide reste accessible.

```
jgit ne fonctionne que sur macOS et Linux (système détecté : FreeBSD).
Les outils de base de ce système n'ont pas été vérifiés, et un écart de comportement peut détruire du travail.
Voir docs/05-portabilite.md pour le détail.
```

## Pourquoi un refus plutôt qu'un avertissement

Parce qu'une panne de portabilité peut être **silencieuse et destructrice**.
C'est arrivé.

`feature rebase` construisait la liste des commits à rejouer avec
`git rev-list … | tail -r`. `tail -r` n'existe que sur BSD/macOS : sous GNU, la
commande échouait sans rien écrire, la liste ressortait **vide**, et le rebase se
déroulait normalement… sur une liste vide. La branche de travail était
force-pushée **vidée de tous les commits du développeur**, et `jgit` annonçait
« Rebase terminé avec succès ».

C'est pour cela que `jgit` a d'abord refusé tout autre système que macOS, et
c'est pour cela qu'il refuse encore tout système qui n'est pas joué par la suite
de tests.

## Ce qui a été levé pour Linux

| Point | Où | Correctif |
| --- | --- | --- |
| `tail -r` (BSD seulement) | `rebase.sh` | `git rev-list --reverse` |
| `tput` sans `TERM` exploitable | partout : messages colorés | couleurs centralisées (`jgit_init_colors`), coupées hors terminal, sans `TERM`, avec `NO_COLOR` |
| Expression `\?` (extension GNU) passée à `git log --grep` | `get_last_commit_with_pattern` | BRE POSIX, interprétation imposée par `--basic-regexp` |
| `\s` dans `grep -E` | `clean_branches` | classe POSIX `[[:space:]]` |
| Appel par un lien symbolique (`$0`) | `jgit.sh` et les modules | résolution du lien (`jgit_resolve_home`) |
| Deux tags créés dans la même seconde | `release start`, `release finish` | à date égale, le plus haut numéro l'emporte (`--sort=-v:refname --sort=-creatordate`) |

Ce dernier point n'est pas propre à Linux, mais c'est la vitesse d'exécution
sous Linux qui l'a révélé : sur un poste, deux releases ne se livrent pas dans
la même seconde ; dans un script ou une CI, si.

## Ce qu'un agent de CI apporte en plus

Un conteneur ou un agent Jenkins n'est pas un poste de développeur. Trois écarts
sont traités explicitement :

| Situation | Ce que fait `jgit` |
| --- | --- |
| Clone superficiel (`--depth`) | refuse avant toute action : les commits d'init et la branche d'origine n'y sont pas (`ensure_full_history`) |
| Clone réduit à une branche (`--single-branch`) | fonctionne : le fetch de `jgit` nomme explicitement toutes les branches du serveur |
| Aucune identité git | refuse avant toute action, sauf `util clean` qui ne commite jamais (`ensure_git_identity`) |

## Règles pour la suite

- Rester en **bash 3.2** (macOS) tout en passant sous **bash 5.2** (Linux) :
  pas de tableaux associatifs, pas de `${var,,}`, et attention à
  `patsub_replacement` de bash 5.2 — le remplacement de `${s//motif/remplacement}`
  doit être **entre guillemets**, sinon `&` y prend un sens spécial.
- N'utiliser des outils système que leur partie **POSIX** : pas de `sed -i`, pas
  de `\t` dans `sed`, pas de `date -j` ni `date -d`, pas de `stat -f`, pas de
  `readlink -f`, pas de `tail -r`. `awk` doit se contenter de ce que comprend
  `mawk` (Debian) comme l'`awk` BSD.
- Toute nouvelle fonction passe par les deux suites (`./tests/run.sh` et
  `./tests/run-in-docker.sh`).

## Comment le garde-fou est testé

Le bac à sable place déjà `$SANDBOX/bin` en tête du `PATH`. L'étape
`Étant donné le système détecté est "…"` y dépose un faux `uname`, ce qui suffit à
faire croire à `jgit` qu'il tourne ailleurs. Les scénarios vérifient que le
refus intervient **avant** toute action, en particulier avant qu'un
`feature rebase` n'ait touché au remote.
