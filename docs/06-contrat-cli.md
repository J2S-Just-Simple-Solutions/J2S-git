# Contrat de la ligne de commande (`--json`)

`jgit` a trois sortes d'utilisateurs : des humains, qui lisent des phrases, et
des programmes — une IA (Claude Code), l'interface en terminal, Jenkins — qui
lisent un document. L'option `--json` est faite pour les seconds.

Ce document est le **contrat** : ce qu'un programme peut attendre de `jgit`, et
que le code s'engage à ne pas casser sans changer de version de schéma.

---

## Les trois règles

1. **Avec `--json`, la sortie standard porte un seul document JSON**, sur une
   seule ligne, suivie d'un retour à la ligne. Rien d'autre : ni message, ni
   question, ni séquence de couleur.
2. **Tous les messages destinés aux humains partent sur la sortie d'erreur.** Ils
   restent utiles à afficher, ils ne sont pas à analyser.
3. **Le code de sortie donne la famille du résultat**, le document en donne le
   détail (`error.code`).

`--json` implique `--no-interaction` : les questions prennent leur réponse par
défaut (celle de la majuscule) et le disent sur la sortie d'erreur
(`[no-interaction] Souhaitez-vous continuer ? -> y`). git est configuré pour ne
rien demander non plus : ni identifiants (`GIT_TERMINAL_PROMPT=0`), ni message
dans un éditeur (`GIT_EDITOR=true`).

L'option est repérée **avant** toutes les autres : une erreur de syntaxe placée
n'importe où sur la ligne produit tout de même un document d'erreur.

```bash
jgit demo show sprint12 --json  > resultat.json  2> messages.txt
echo $?                                           # famille du résultat
```

---

## Codes de sortie

| Code | Famille | Exemples de `error.code` |
| --- | --- | --- |
| `0` | succès, **y compris quand il n'y avait rien à faire** | — |
| `1` | usage incorrect, ou échec inattendu d'une commande git | `usage`, `failed`, `platform_unsupported`, `shallow_repository`, `git_identity_missing`, `remote_missing` |
| `2` | précondition refusée : **rien n'a été modifié** | `worktree_dirty`, `branch_ahead`, et les refus des commandes de démo |
| `3` | conflit : l'opération est en pause, ou a été abandonnée | `conflict` |
| `4` | quelqu'un a poussé entre-temps : rien n'a été écrasé | `lease_rejected` |
| `5` | une opération attend déjà une résolution de conflit | `operation_in_progress` |
| `6` | serveur injoignable | `remote_unreachable` |

Deux réserves, héritées de l'existant et conservées pour ne casser aucun script :

- les commandes `feature`, `hotfix` et `release` sortent en `1` sur un refus,
  comme avant ; leur document porte le code précis (`worktree_dirty`…). Le
  rebase de feature suit en revanche la table pour ce qui est nouveau : `2`
  pour le rebase d'une PR validée refusé, `3` conflit, `4` lease refusé, `5`
  opération en pause ; `continue` et `abort` suivent la table complète ;
- `util check_rebase` garde ses propres codes (`0` à jour, `1` impossible de
  répondre, `2` en retard sans conflit, `3` en retard avec conflits).

Les commandes `demo` suivent la table complète.

---

## Les documents

Chaque document porte `schema` (nom et version majeure) et `ok`. Un champ
n'est jamais retiré ni change de sens sans changement de version majeure ; de
nouveaux champs peuvent apparaître à tout moment, un lecteur doit les ignorer.

### `jgit.result/1` — résultat générique

Produit par toute commande qui n'a pas de document propre.

```json
{"schema":"jgit.result/1","ok":true,"command":"feature start"}
```

### `jgit.error/1` — erreur

Produit par toute commande qui échoue, quelle que soit la façon dont elle
échoue.

```json
{"schema":"jgit.error/1","ok":false,"command":"release start",
 "error":{"code":"worktree_dirty","exit_code":1,
          "message":"Votre espace de travail contient des modifications non commitées.",
          "hint":"git stash push -u -m \"avant jgit\""}}
```

| Champ | Sens |
| --- | --- |
| `error.code` | identifiant stable de l'erreur, en `snake_case` ; `failed` quand l'erreur n'a pas été identifiée plus précisément |
| `error.exit_code` | le code de sortie du processus |
| `error.message` | la phrase affichée à l'humain, en français |
| `error.hint` | la commande ou l'action qui débloque la situation, ou `null` |

### `jgit.conflict/1` — conflit

Produit sur un conflit de rejeu (rebase de feature, reconstruction de démo),
qu'il soit mis en pause (`--on-conflict pause`) ou abandonné (`abort`). Code de
sortie `3`. Il porte un objet `error` comme `jgit.error/1`, pour qu'un lecteur
qui ne connaît que les erreurs le comprenne quand même.

```json
{"schema":"jgit.conflict/1","ok":false,"command":"feature rebase",
 "operation":"feature_rebase","target":"feature/TEST-1","paused":true,
 "error":{"code":"conflict","exit_code":3,
          "message":"Conflit pendant le rebase de feature/TEST-1 sur develop.",
          "hint":"jgit feature continue TEST-1"},
 "branch":"jgit_rebase_feature/TEST-1",
 "commit":{"sha":"a1b2…","subject":"Modifie app.txt côté feature"},
 "conflicted_files":[{"path":"src/app.txt","kind":"both_modified"}],
 "progress":{"done":2,"total":3},
 "commands":{"continue":"jgit feature continue TEST-1","abort":"jgit feature abort TEST-1"}}
```

| Champ | Sens |
| --- | --- |
| `paused` | `true` : le conflit attend dans l'espace de travail ; `false` : tout a été annulé |
| `error.code` | `conflict` ; à la reprise, `unresolved_files` (des fichiers sont encore en conflit) ou `conflict_markers_left` (des marqueurs `<<<<<<<` ont été marqués résolus) |
| `branch` | la branche temporaire sur laquelle résoudre, `null` si abandonné |
| `commit` | le commit dont le rejeu a conflicté |
| `conflicted_files[].kind` | `both_modified`, `both_added`, `both_deleted`, `added_by_us`, `added_by_them`, `deleted_by_us`, `deleted_by_them`, `conflict_markers` |
| `progress` | commits rejoués / à rejouer au total |
| `commands` | les deux issues, prêtes à lancer ; `null` si abandonné |
| `context` | facultatif : détails propres à l'opération (le ticket, pour une démo) |

**Procédure de résolution par un programme** : lire `conflicted_files`, éditer
chaque fichier pour retirer les marqueurs, `git add` chaque fichier, puis lancer
`commands.continue` (avec `--json`). Un nouveau `jgit.conflict/1` peut revenir :
c'est le commit suivant qui conflicte à son tour.

### `jgit.status/1` — `jgit util status`

Dit si une opération attend la résolution d'un conflit, sans rien toucher : ce
qu'il faut à quelqu'un — un collègue, une IA, l'interface — qui arrive au milieu.

```json
{"schema":"jgit.status/1","ok":true,"command":"util status","current_branch":"jgit_demo_sprint12",
 "operation_in_progress":{"operation":"demo_add","target":"demo/sprint12",
   "label":"l'ajout de tickets à la démo demo/sprint12","branch":"jgit_demo_sprint12",
   "commit":{"sha":"…","subject":"Modifie app.txt"},
   "conflicted_files":[{"path":"src/app.txt","kind":"both_modified"}],
   "progress":{"done":2,"total":3},
   "commands":{"continue":"jgit demo continue sprint12","abort":"jgit demo abort sprint12"},
   "context":{"demo":"sprint12","ticket":"feature/TEST-2"}}}
```

`operation_in_progress` est `null` quand rien n'est en pause. Une liste
`conflicted_files` vide signifie que tout est résolu : il reste à reprendre.

### `jgit.demo.list/1` — `jgit demo list`

```json
{"schema":"jgit.demo.list/1","ok":true,"command":"demo list","remote":"origin","scope":"active",
 "demos":[{"name":"sprint12","branch":"demo/sprint12","format":"v2",
           "archived":false,"archived_on":null,"read_only":false,
           "base":"develop","base_exists":true,"behind_base":4,
           "tip_sha":"…","updated_at":"2026-10-12T09:14:03+02:00","updated_by":"Yann",
           "ticket_count":3,"tickets_needing_attention":1,"foreign_commit_count":0,
           "needs_rebase":true,"operation_in_progress":false}],
 "archived_count":2}
```

| Champ d'une démo | Sens |
| --- | --- |
| `format` | `v2` (format actuel) ou `legacy` (ancienne démo `demo_<nom>`, lecture seule) |
| `read_only` | `true` pour une archive ou une ancienne démo |
| `behind_base` | commits de la base absents de la démo ; `null` si la base n'existe plus |
| `tickets_needing_attention` | tickets dont l'action suggérée n'est pas `none` |
| `foreign_commit_count` | commits poussés à la main, hors de tout ticket |
| `operation_in_progress` | une opération en pause concerne cette démo |

### `jgit.demo.show/1` — `jgit demo show`

```json
{"schema":"jgit.demo.show/1","ok":true,"command":"demo show",
 "demo":{ "…le même objet que dans la liste…" },
 "tickets":[{"ticket":"feature/MONPROJET-88","type":"feature","id":"MONPROJET-88","position":2,
             "status":"ahead","delivered":false,"delivered_with_pending_work":false,
             "remote_exists":true,"commits_in_demo":3,"commits_not_in_demo":2,
             "commits_only_in_demo":0,"segments":1,"suggested_action":"add"}],
 "foreign_commits":[{"sha":"…","subject":"Rustine","author":"Yann"}],
 "release_command":"jgit release merge --from feature/MONPROJET-412 --from feature/MONPROJET-88"}
```

| Champ d'un ticket | Valeurs |
| --- | --- |
| `status` | `up_to_date`, `ahead` (nouveaux commits pas encore dans la démo), `diverged` (ticket réécrit depuis son ajout), `missing` (branche supprimée du serveur), `unknown` (ancien format) |
| `delivered` | le ticket est livré dans la base de la démo |
| `delivered_with_pending_work` | livré, mais la branche de travail porte du code que la PR livrée n'a pas |
| `suggested_action` | `none`, `add`, `refresh` ou `drop` |
| `commits_*` | comptés à l'empreinte (auteur, date, sujet) ; `null` pour l'ancien format |

### `jgit.demo.candidates/1` — `jgit demo candidates`

```json
{"schema":"jgit.demo.candidates/1","ok":true,"command":"demo candidates",
 "demo":"sprint12","base":"develop",
 "candidates":[{"ticket":"feature/MONPROJET-90","type":"feature","id":"MONPROJET-90",
                "updated_at":"2026-10-12T08:01:00+02:00","last_subject":"…",
                "author":"Camille","delivered":false}]}
```

Avec `--based-on <branche>` (sans nom de démo), les candidats d'une démo encore
à créer sur cette base : `demo` vaut `null`, `base` la branche demandée, et
`delivered` se lit par rapport à elle. Une branche absente du serveur donne
`base_not_found` (code 2) ; `--based-on` avec un nom de démo, `usage`.

### `jgit.demo.bases/1` — `jgit demo bases`

```json
{"schema":"jgit.demo.bases/1","ok":true,"command":"demo bases","default":"develop",
 "bases":[{"branch":"develop","role":"preprod","updated_at":"…","last_subject":"…"},
          {"branch":"main","role":"prod","updated_at":"…","last_subject":"…"},
          {"branch":"release/1.5.0","role":"release","updated_at":"…","last_subject":"…"}]}
```

`role` vaut `preprod`, `prod`, `release` ou `other`. L'ordre est celui à
proposer : préprod, production, releases puis autres branches (des plus
récentes aux plus anciennes). `default` est la base que prend `demo create`
sans `--based-on`. Les branches de tickets, de PR, de démos et les branches
temporaires de jgit n'y figurent pas.

### `jgit.audit/1` — `jgit audit`, `jgit audit tickets`, `jgit audit demos [<nom>]`

L'état des lieux : chaque ticket du serveur par rapport à sa base, puis chaque
démo, avec les commandes à lancer dans l'ordre et qui doit intervenir. Tout est
simulé, rien n'est modifié. Le rapport humain ne dit que qui et quoi ; le
document donne aussi le détail (commits, fichiers, en face).

```json
{"schema":"jgit.audit/1","ok":true,"command":"audit","scope":"all",
 "tickets":[{"ticket":"feature/FACT-1","type":"feature","id":"FACT-1",
   "pr_title":"Affiche le total TTC",
   "base":"develop","base_source":"recorded","behind_base":1,"status":"conflicts",
   "delivered":false,"pr_validated":false,
   "owner":{"author":"Yann","email":"yann@j2s.net"},"last_activity":"2026-10-19T07:54:16+02:00",
   "concerned":[{"author":"Yann","email":"yann@j2s.net"}],
   "command":"jgit feature rebase FACT-1 --on-conflict pause",
   "conflict":{"commit":{"sha":"…","subject":"Affiche le total TTC","author":"Yann","email":"yann@j2s.net","date":"2026-10-19"},
     "files":[{"path":"src/accueil.txt","kind":"both_modified",
               "other":{"sha":"…","subject":"Nouveau message d'accueil","author":"Camille","email":"camille@j2s.net","origin":"develop"}}]},
   "demos":["client-a"]}],
 "demos":[{"name":"client-a","branch":"demo/client-a","base":"develop","behind_base":1,
   "status":"conflicts","message":null,
   "prerequisites":[{"ticket":"feature/FACT-1","status":"conflicts","command":"jgit feature rebase FACT-1 --on-conflict pause"}],
   "held":["feature/FACT-1"],
   "actions":[{"kind":"ticket","command":"jgit feature rebase FACT-1 --on-conflict pause","reason":"d'abord rebaser le ticket chez lui : … — à faire par : Yann"},
              {"kind":"demo","command":"jgit demo rebase client-a --from feature/FACT-1","reason":"base develop en retard de 1 commit(s) ; reprend feature/FACT-1 depuis leur branche"}],
   "dropped":[],"conflicts":[]}],
 "summary":{"tickets":{"total":1,"up_to_date":0,"to_rebase":0,"conflicts":1,"base_missing":0,"no_init":0,"delivered":0},
            "demos":{"total":1,"up_to_date":0,"feasible":0,"conflicts":1,"blocked":0,"skipped_legacy":0}}}
```

`scope` vaut `all`, `tickets` (`demos` est alors vide) ou `demos` (les tickets
sont alors ceux des démos auditées). Les tickets sont rangés du plus récemment
modifié au plus ancien.

**Les tickets**

| Champ | Sens |
| --- | --- |
| `pr_title` | le titre de sa PR ouverte sur GitHub, sans la clé du ticket qu'il répète en tête ; `null` sans PR, sans `gh`, ou avec `--no-fetch` |
| `base` | sa base |
| `base_source` | `recorded` : enregistrée à sa création ; `inferred` : supposée — parmi la préprod, la production et les bases enregistrées par des tickets ou des démos, celle dont il s'écarte le moins |
| `behind_base` | nombre de commits de la base absents du ticket |
| `status` | `up_to_date`, `to_rebase` (son rebase passera), `conflicts` (il coincera), `base_missing` (sa base n'existe plus), `no_init` (pas de commit d'init : jgit ne sait pas quels commits sont les siens), `delivered` (déjà dans sa base) |
| `pr_validated` | `false` : sa branche de PR n'a que son commit d'init ; `true` : elle a avancé ; `null` : pas de branche de PR |
| `owner` | l'auteur du dernier commit de la branche |
| `concerned` | qui doit intervenir : pour `conflicts`, les auteurs des commits du ticket qui touchent les fichiers en conflit ; sinon le propriétaire ; vide quand il n'y a rien à faire |
| `command` | ce qu'il faut lancer (avec `--based-on` quand la base est supposée), `null` s'il n'y a rien à faire ou que jgit ne sait pas le faire (`no_init`) |
| `conflict` | pour `conflicts` : `commit`, le dernier commit du ticket qui touche les fichiers en conflit ; `files[].other`, le dernier commit de la base qui a touché le fichier depuis le départ du ticket, son auteur, et `origin` (le nom de la base) |
| `demos` | les démos qui contiennent le ticket |

Comme `jgit feature rebase`, la simulation ne rejoue que les commits du ticket
qui suivent son commit d'init.

**Les démos**

| Champ | Sens |
| --- | --- |
| `status` | `up_to_date` (rien à faire), `feasible` (tout passe), `conflicts` (un conflit est prévu dans la démo, ou un ticket est `held`), `blocked` (base disparue, commit de fusion ajouté à la main : `message` dit quoi faire) |
| `prerequisites` | les tickets de la démo à rebaser d'abord, chez eux |
| `held` | ceux dont ce rebase coince : leur auteur résout le conflit chez lui ; la démo ne les simule pas avant, ils sont repris depuis leur branche (`--from`) |
| `actions` | les commandes dans l'ordre : `kind: ticket` (les prérequis), puis `kind: demo` (`jgit demo rebase` avec ses `--from`, puis `jgit demo add`) ; `--on-conflict pause` est ajouté là où un conflit est prévu |
| `dropped` | tickets que le rebase retirera (`delivered`, `missing`) |
| `conflicts[].step` | l'étape où le conflit apparaît : `rebase`, `fresh` (reprise du ticket depuis sa branche), `add`, `foreign` (commits ajoutés à la main ; `ticket` vaut alors `-`) |
| `conflicts[].commit` | le commit qui ne passe pas, et son auteur |
| `conflicts[].files[].other` | en face : le dernier commit qui a touché le fichier dans la démo en cours de reconstruction, son auteur, et `origin` (un ticket de la démo, `commit ajouté à la main`, ou le nom de la base) ; `null` si le fichier n'existe pas de ce côté |
| `conflicts[].commands` | `resolve` : la commande qui ouvrira le conflit en pause ; `drop` : retirer le ticket |

`kind` d'un fichier en conflit : les mêmes valeurs que `jgit.conflict/1`.

`jgit audit demos <archive>` est refusé (`read_only`, code 2) ; les démos à
l'ancien format sont ignorées (`summary.demos.skipped_legacy`). Une action
inconnue, ou un nom de démo ailleurs qu'après `audit demos`, donne `usage`.
**Code de sortie 3** dès qu'un ticket coincera, qu'une base a disparu, qu'un
ticket n'a pas de commit d'init, ou qu'une démo est en conflit ou bloquée ; 0
sinon — le document est émis dans les deux cas.

**`--apply`** ajoute au document ce qui a été lancé (`apply` vaut `null` sans
l'option) :

```json
"apply":{"dry_run":false,"confirmed":true,
  "operations":[{"kind":"ticket","target":"feature/FACT-3","command":"jgit feature rebase FACT-3","status":"done","error":null},
                {"kind":"demo","target":"client-a","command":"jgit demo rebase client-a","status":"failed",
                 "error":{"code":"lease_rejected","message":"…"}}],
  "left_aside":[{"ticket":"feature/MENU-3","reason":"not_mine","concerned":["Camille"],"command":"jgit feature rebase MENU-3"}]}
```

| Champ | Sens |
| --- | --- |
| `operations[]` | dans l'ordre : le rebase de mes tickets (`kind: ticket`), puis les commandes des démos faisables (`kind: demo`) |
| `operations[].status` | `done`, `failed` (`error` : le code et le message de la commande), `planned` (`--dry-run`), `cancelled` (plan refusé) |
| `left_aside[].reason` | `not_mine` : ticket d'autres personnes (`concerned`, leurs noms) ; `inferred_base` : base supposée, à vérifier avant de lancer `command` |

Avec `--apply`, l'espace de travail doit être propre (`worktree_dirty`, code 1),
et le code de sortie vaut aussi 3 si une opération a échoué. `--apply` ailleurs
qu'avec `jgit audit` donne `usage`.

### `jgit.demo.result/1` — `create`, `add`, `drop`, `refresh`, `rebase`, `continue`

```json
{"schema":"jgit.demo.result/1","ok":true,"command":"demo rebase","operation":"rebase",
 "demo":"sprint12","branch":"demo/sprint12",
 "changed":true,"pushed":true,"dry_run":false,
 "base":"develop","old_sha":"…","new_sha":"…",
 "added":[],"updated":[],
 "dropped":[{"ticket":"feature/MONPROJET-412","reason":"delivered"}],
 "warnings":[{"code":"foreign_commits_kept","ticket":null}]}
```

| Champ | Sens |
| --- | --- |
| `changed` | `false` : la démo était déjà dans l'état demandé, rien n'a été publié |
| `pushed` | `false` en `--dry-run` ou quand rien ne change |
| `dropped[].reason` | `requested`, `delivered`, `missing`, `foreign` (ticket `-` : les commits ajoutés à la main) |
| `warnings[].code` | `foreign_commits_kept`, `delivered_with_pending_work`, `local_branch_stale` |

Un conflit produit `jgit.conflict/1`, avec `context.demo` et `context.ticket`.

`jgit demo rebase <nom> --from <ticket>` reprend ce ticket depuis sa branche
au lieu de rejouer son segment : il figure dans `updated`. Un ticket absent de
la démo est refusé (`ticket_not_in_demo`, code 2).

`archive`, `unarchive` et `delete` produisent le même schéma, réduit à
l'essentiel :

```json
{"schema":"jgit.demo.result/1","ok":true,"command":"demo archive","operation":"archive",
 "demo":"sprint12","branch":"demo-archive/2026-10-12_sprint12","previous_branch":"demo/sprint12",
 "changed":true,"pushed":true,"dry_run":false,"sha":"…"}
```

`branch` est le nouveau nom (`null` après `delete`), `previous_branch` l'ancien.
`migrate` produit le schéma complet, comme `create`.

### Codes d'erreur du rebase de feature

| `error.code` | Code de sortie | Situation |
| --- | --- | --- |
| `branch_not_found` | 1 | ni la branche de travail ni la branche de PR n'existent |
| `branch_not_on_remote` | 1 | la branche de PR, ou la branche de travail en cours de développement, n'est pas sur le serveur |
| `history_diverged` | 1 | la branche de travail ne descend plus de sa branche de PR, alors que la PR n'a jamais été validée |
| `pr_validated_new_work` | 2 | PR validée, mais la branche de travail porte du code absent de la branche de PR : rien n'est modifié |
| `pr_not_validated` | 2 | branche de travail disparue et PR jamais validée : `hint` donne la commande qui supprime la branche de PR |
| `cancelled` | 1 | une confirmation a été refusée |
| `conflict`, `unresolved_files`, `conflict_markers_left` | 3 | conflit |
| `lease_rejected`, `push_failed` | 4, 1 | publication refusée : quelqu'un a poussé entre-temps, ou le serveur a refusé |

Une PR validée dont la branche de PR est déjà mergée dans sa base n'est pas une
erreur : la commande réussit (`jgit.result/1`), après avoir supprimé ses
branches si la confirmation l'a accepté.

### Codes d'erreur des démos

| `error.code` | Code de sortie | Situation |
| --- | --- | --- |
| `usage` | 1 | nom ou `--from` manquant |
| `invalid_name`, `already_exists`, `demo_not_found`, `not_a_demo` | 2 | la démo elle-même |
| `base_not_found`, `base_not_published` | 2 | la base |
| `bad_ticket_format`, `ticket_not_found`, `ticket_not_in_demo`, `ticket_diverged`, `ticket_delivered` | 2 | un ticket |
| `archived`, `legacy_format` | 2 | démo en lecture seule |
| `ambiguous` | 2 | `unarchive` d'un nom qui a plusieurs archives |
| `not_legacy`, `base_unknown` | 2 | `migrate` d'une démo déjà au format actuel, ou sans base enregistrée |
| `foreign_merge` | 2 | un commit de fusion poussé à la main empêche la reconstruction |
| `worktree_dirty` | 1 | l'espace de travail n'est pas propre |
| `conflict`, `unresolved_files`, `conflict_markers_left` | 3 | conflit |
| `lease_rejected` | 4 | la démo a été modifiée sur le serveur pendant l'opération |
| `operation_in_progress` | 5 | une opération est en pause |
| `remote_unreachable` | 6 | serveur injoignable |

---

## Autres options utiles à un programme

| Option | Effet |
| --- | --- |
| `--no-interaction` | aucune question : la réponse par défaut est appliquée |
| `--no-fetch` | ne contacte pas le serveur, travaille sur les références déjà rapatriées — pour un affichage répété |
| `--on-conflict <ask\|abort\|pause>` | conduite face à un conflit. `--json` n'implique **pas** `pause` : sans interaction, le défaut reste `abort`, qui ne laisse jamais le dépôt au milieu d'une opération. Un programme qui sait résoudre (une IA) demande `pause` explicitement ; Jenkins garde le défaut |
| `JGIT_COLOR=never` ou `NO_COLOR=1` | aucune séquence de couleur, même face à un terminal |

---

## Mise en œuvre

- `json.sh` : fabrication des fragments (`json_str`, `json_kv_*`, `json_object`,
  `json_array`), émission (`json_emit`), erreurs (`jgit_fail`, `jgit_error_set`).
  En bash pur — aucun `jq` n'est installé sur les postes —, compatible bash 3.2
  et 5.2.
- `jgit.sh` repère `--json`, duplique la sortie standard sur le descripteur 3 et
  envoie la sortie standard vers la sortie d'erreur. Le code existant écrit ses
  messages comme avant ; seul `json_emit` écrit sur le descripteur 3.
- Un `trap EXIT` garantit le document : une commande qui se termine sans en avoir
  émis produit `jgit.result/1` (code 0) ou `jgit.error/1` (autre code), avec le
  contexte laissé par `jgit_error_set`.

**Règle de codage qui en découle.** Une nouvelle erreur s'arrête par
`jgit_fail <code> <code_de_sortie> <message> [remède]`, ou, quand le message est
déjà affiché, par `jgit_error_set` suivi de `exit_safe`. Un `exit_safe 1` nu
reste lisible par un programme, mais seulement comme `failed`.
