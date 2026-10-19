---
name: jgit-demo
description: Gérer les démos jgit d'un projet J2S (branches demo/<nom>) et faire l'état des lieux des tickets — lister, montrer leur contenu et leur état, créer, ajouter ou retirer des tickets, remettre à jour sur la préprod, résoudre les conflits, archiver ; dire quels tickets sont à rebaser, lesquels coinceront et qui est concerné. À utiliser dès qu'on parle de « démo », de branche demo/…, de montrer des tickets ensemble, de préparer un environnement de démonstration, ou d'« état des lieux » / « où en sont les tickets », dans un dépôt où jgit est installé.
---

# Piloter les démos avec jgit

`jgit` est l'outil git maison de J2S. Une **démo** est une branche `demo/<nom>`
qui assemble des tickets (`feature/<ticket>`, `hotfix/<ticket>`) au-dessus d'une
base (la préprod `develop`, le plus souvent) pour les montrer ensemble. Tu la
pilotes **exclusivement par la ligne de commande `jgit`**, en lisant ses
documents JSON. Tu ne manipules jamais une branche de démo à la main avec git.

## Vocabulaire

| Terme | Sens |
| --- | --- |
| démo | branche `demo/<nom>` ; une **recette** : une base + une liste ordonnée de tickets |
| ticket | une branche `feature/<id>` ou `hotfix/<id>` du serveur |
| base | la branche dont la démo part (`develop`, parfois `main`) |
| segment | les commits d'un ticket recopiés dans la démo, fermés par un commit repère `[jgit] DEMO ticket …` |
| livré | le ticket est déjà dans la base (sa PR a été validée et livrée) |
| archive | `demo-archive/<AAAA-MM-JJ>_<nom>` : une ancienne démo mise de côté, en lecture seule |
| ancien format | `demo_<nom>` : première version des démos, lecture seule, à convertir (`migrate`) |

## Règles de conduite

1. **Toujours `--json`** pour lire le résultat : la sortie standard porte un seul
   document JSON ; les messages humains sont sur la sortie d'erreur. Lis
   `ok`, `schema`, et en cas d'échec `error.code` et `error.hint`. Le code de
   sortie donne la famille (voir plus bas).
2. **Regarder avant d'agir** : `jgit demo show <nom> --json` avant toute
   modification. Il donne, pour chaque ticket, `status` et `suggested_action`.
3. **`--dry-run` avant toute réécriture** (`drop`, `refresh`, `rebase`,
   `archive`) et montrer le plan à l'humain. `add` ne réécrit rien.
4. **Demander l'accord de l'humain** avant : un `drop`, un `rebase` qui retire
   des tickets (`dropped` non vide au `--dry-run`), un `archive`, un `delete`,
   tout `--drop-foreign`, tout `--keep-*`. Pas besoin d'accord pour lire ni pour
   `add` un ticket qu'il a demandé.
5. **Conflits : toujours `--on-conflict pause`** quand tu modifies une démo, pour
   pouvoir les résoudre (voir la procédure). Sans cette option, `--json` annule
   tout au premier conflit.
6. **Jamais** de `git push`, `git push --force`, `git reset` ou `git checkout`
   sur une branche `demo/…`, `jgit_demo_…` ou un ticket. Seules exceptions,
   pendant un conflit en pause : éditer les fichiers en conflit et `git add`.
7. Une seule opération peut être en pause dans un dépôt. Si une commande répond
   `operation_in_progress` (code 5), termine-la (`continue`) ou annule-la
   (`abort`) avant toute autre chose.

## Les commandes

```bash
jgit demo list [--archived|--all] --json         # toutes les démos et leur état
jgit demo show [<nom>] --json                    # le détail, ticket par ticket
jgit demo candidates [<nom>] --json              # tickets que l'on peut ajouter
jgit demo candidates --based-on <base> --json    # … à une démo encore à créer sur cette base
jgit demo bases --json                           # branches dont une démo peut partir
jgit audit --json                                # état des lieux : tous les tickets, puis toutes les démos
jgit audit tickets --json                        # les tickets seulement
jgit audit demos [<nom>] --json                  # les démos : quoi lancer, dans l'ordre ; conflits ; qui ?
jgit audit --apply [--dry-run] --json            # applique ce qui passe sans conflit (accord de l'humain)

jgit demo create <nom> [--based-on <base>] [--from <ticket>]... --json
jgit demo add <nom> --from <ticket>... --on-conflict pause --json
jgit demo drop <nom> --from <ticket>... --on-conflict pause --json
jgit demo refresh <nom> --from <ticket>... --on-conflict pause --json
jgit demo rebase <nom> [--based-on <base>] [--from <ticket>]... [--keep-delivered] [--keep-missing] [--drop-foreign] --on-conflict pause --json
jgit demo continue [<nom>] --json                # reprendre après résolution d'un conflit
jgit demo abort [<nom>] --json                   # tout annuler, rien n'est publié

jgit demo archive <nom> --json                   # → demo-archive/<date>_<nom>, libère le nom
jgit demo unarchive <archive|nom> --json
jgit demo delete <nom|archive> --json
jgit demo migrate <nom> [--based-on <base>] --json   # convertir une démo demo_<nom>
```

`--json` implique `--no-interaction` : aucune question n'est posée, la réponse
par défaut est appliquée. `--dry-run` montre le plan sans rien publier.

## Lire l'état d'une démo (`jgit.demo.show/1`)

- `demo.behind_base` > 0 ou `demo.needs_rebase` : la base a avancé →
  proposer `jgit demo rebase <nom>`.
- `demo.foreign_commit_count` > 0 : des commits ont été poussés à la main sur la
  démo. Ils sont gardés par défaut. Les signaler à l'humain ; ne jamais
  `--drop-foreign` sans son accord.
- Pour chaque ticket, `status` :

| `status` | Sens | `suggested_action` |
| --- | --- | --- |
| `up_to_date` | la démo contient tout le ticket | `none` |
| `ahead` | `commits_not_in_demo` nouveaux commits pas encore dans la démo | `add` (ajoute les nouveaux commits à la suite) |
| `diverged` | le ticket a été squashé ou réécrit depuis son ajout | `refresh` (le reprend en entier, à sa place) |
| `missing` | la branche du ticket a été supprimée | `drop` (fait par le prochain `rebase`) |
| `unknown` | ancien format | — (`migrate`) |

- `delivered: true` : le ticket est livré dans la base → il sera retiré par le
  prochain `rebase` (son code reste, il est dans la base).
- `release_command` : la commande `jgit release merge` pour livrer les tickets
  de la démo, une fois leurs PR validées. Ne la lance pas toi-même sans demande
  explicite.

## Procédures

### Montrer où en est une démo
1. `jgit demo show <nom> --json`.
2. Résumer pour l'humain : base et retard, tickets avec leur état, actions
   suggérées, commits ajoutés à la main. Proposer les commandes, ne pas les
   lancer d'office si elles réécrivent la démo.

### Créer une démo
1. **Demander la base à l'humain** s'il ne l'a pas dite : `jgit demo bases --json`
   donne les choix (préprod et production en tête, puis releases) et `default`.
   Ne jamais la choisir en silence.
2. `jgit demo candidates --based-on <base> --json` si l'humain ne sait pas quels
   tickets mettre (les tickets déjà livrés dans cette base sont signalés).
3. `jgit demo create <nom> --based-on <base> --from … --on-conflict pause --json`
   — toujours avec `--based-on`, explicite. Un nom : lettres,
   chiffres, `.`, `_`, `-`. Si `already_exists` : la démo existe ; proposer `add`,
   ou `archive` puis `create` pour la remplacer.

### Faire l'état des lieux (`jgit.audit/1`)
`jgit audit --json` (ou `jgit audit demos <nom> --json`) simule tout, sans rien
modifier — c'est la première chose à faire quand l'humain demande « où en sont
les démos », « où en sont les tickets » ou « peut-on les mettre à jour ». Code
de sortie 3 si quelque chose coince ; le document est émis quand même.

- `tickets[]` : pour chaque ticket du serveur, `pr_title` (le titre de sa PR),
  `status` (`up_to_date`, `to_rebase`, `conflicts`, `base_missing`, `no_init`,
  `delivered`), `base` et `base_source` (`inferred` : base supposée, la
  commande la donne par `--based-on`), `concerned` (**qui doit intervenir** :
  pour un conflit, les auteurs des commits en cause), `command`, et pour
  `conflicts` le détail : `conflict.commit` et, par fichier, `other.author` (qui
  a modifié le même fichier dans la base).
- `demos[]` : `status`, `actions` — les commandes **dans l'ordre** : d'abord
  `kind: ticket` (rebaser chez eux les tickets en retard sur leur base), puis
  `kind: demo` (`jgit demo rebase` avec ses `--from`, `jgit demo add`) —,
  `held` (tickets dont le rebase coince : la démo attend que leur auteur les
  résolve), `conflicts` (entre tickets, à résoudre dans la démo :
  `commands.resolve` ou `commands.drop`).

Présenter à l'humain : qui doit intervenir sur quoi (`concerned`), et les
commandes dans l'ordre — pas le détail des fichiers, sauf s'il le demande.

`jgit audit --apply --json` lance ce qui passe sans conflit : le rebase des
tickets de l'humain (son identité git), puis les démos faisables. Montrer
d'abord le plan (`jgit audit --apply --dry-run --json`, `apply.operations`) et
**demander son accord** : ce sont des réécritures. Lire ensuite
`apply.operations[].status` (`done`, `failed` avec `error`) et
`apply.left_aside` (tickets des autres, bases supposées).
Le rebase d'un ticket (`jgit feature rebase`) appartient à son propriétaire : ne
le lance pas sans demande explicite.

### Mettre une démo à jour
1. `jgit audit demos <nom> --json`, puis `jgit demo show <nom> --json`.
2. Les `actions` `kind: ticket` d'abord : à faire par les propriétaires (ou avec
   leur accord). Relancer l'audit ensuite.
3. Tickets `ahead` : `jgit demo add <nom> --from <ticket> --on-conflict pause --json`.
4. Tickets `diverged` : `--dry-run`, accord, puis `jgit demo refresh …`.
5. Base en retard, ou tickets livrés/supprimés : la commande `jgit demo rebase`
   de l'audit (avec ses `--from`), d'abord en `--dry-run --json` : montrer
   `dropped` à l'humain, accord, puis sans `--dry-run` et avec
   `--on-conflict pause`. `--from <ticket>` reprend le ticket depuis sa branche
   (sa version rebasée et résolue par son auteur) au lieu de son segment.

### Résoudre un conflit (`jgit.conflict/1`, code 3, `paused: true`)
1. Lire `context.ticket` (le ticket en cours d'ajout), `commit.subject`,
   `conflicted_files[]` (`path`, `kind`).
2. Pour chaque fichier : l'ouvrir, comprendre les deux côtés (`<<<<<<<` = ce
   qui est déjà dans la démo, `>>>>>>>` = le commit du ticket). La démo doit
   montrer **les deux tickets fonctionnels ensemble** : fusionner les intentions,
   ne pas choisir un côté par facilité. En cas de doute sur l'intention métier,
   s'arrêter et demander à l'humain.
3. Retirer tous les marqueurs `<<<<<<<`, `=======`, `>>>>>>>`, puis
   `git add <fichier>` pour chaque fichier.
4. `jgit demo continue <nom> --json` (la conduite `pause` est conservée).
   - `ok: true` → terminé, la démo est publiée.
   - nouveau `jgit.conflict/1` : un autre commit conflicte → recommencer en 1.
   - `error.code` = `unresolved_files` : des fichiers ne sont pas `git add` ;
     `conflict_markers_left` : des marqueurs restent dans des fichiers ajoutés.
5. Si la résolution est hors de portée : `jgit demo abort <nom> --json` — rien
   n'a été publié — et expliquer le conflit à l'humain.

La résolution devient un commit de la démo : les reconstructions suivantes
(`drop` d'un autre ticket, `rebase`) la rejouent sans la redemander. Retirer un
des deux tickets en conflit fait en revanche disparaître le besoin de résolution.

### Remplacer une démo en gardant l'ancienne
`archive` (accord), puis `create` avec le même nom.

## Codes de sortie et erreurs fréquentes

| Code | Famille | Que faire |
| --- | --- | --- |
| 0 | succès (`changed: false` : rien n'avait à changer, rien n'a été publié) | — |
| 1 | usage ou erreur git (`usage`, `worktree_dirty`, `git_failed`…) | lire `error.hint` ; `worktree_dirty` : l'espace de travail n'est pas propre — ne pas le nettoyer sans l'accord de l'humain |
| 2 | refus, rien n'a été modifié | lire `error.code` / `error.hint` ci-dessous |
| 3 | conflit | procédure de résolution (si `paused: false`, relancer avec `--on-conflict pause`) |
| 4 | `lease_rejected` : quelqu'un a modifié la démo pendant l'opération | rien n'a été écrasé ; relire (`show`) puis relancer |
| 5 | `operation_in_progress` : une opération attend une résolution | `continue` ou `abort` d'abord |
| 6 | serveur injoignable | réessayer plus tard |

| `error.code` (code 2) | Réponse |
| --- | --- |
| `demo_not_found` | `jgit demo list --json` ; si `error.hint` liste des archives, proposer `unarchive` |
| `already_exists` | proposer `add`, ou `archive` puis `create` |
| `ticket_diverged` | `refresh` au lieu de `add` |
| `ticket_delivered` | inutile : le code est déjà dans la base ; proposer `rebase` si la démo est en retard |
| `ticket_not_found`, `bad_ticket_format` | `jgit demo candidates --json` pour les noms exacts |
| `archived` | `unarchive` d'abord (accord) |
| `legacy_format` | `migrate` d'abord |
| `base_not_found`, `base_unknown` | demander à l'humain la base, puis `--based-on` |
| `foreign_merge` | un commit de fusion a été poussé à la main : demander à l'humain ; `--drop-foreign` seulement avec son accord |

Le contrat complet des documents JSON est dans `docs/06-contrat-cli.md` du dépôt
jgit, le guide utilisateur dans `docs/guide/05-demo.md`.
