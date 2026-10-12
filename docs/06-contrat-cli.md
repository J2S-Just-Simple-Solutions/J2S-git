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
  rebase de feature suit en revanche la table pour ce qui est nouveau : `3`
  conflit, `4` lease refusé, `5` opération en pause ; `continue` et `abort`
  suivent la table complète ;
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

`archive`, `unarchive` et `delete` produisent le même schéma, réduit à
l'essentiel :

```json
{"schema":"jgit.demo.result/1","ok":true,"command":"demo archive","operation":"archive",
 "demo":"sprint12","branch":"demo-archive/2026-10-12_sprint12","previous_branch":"demo/sprint12",
 "changed":true,"pushed":true,"dry_run":false,"sha":"…"}
```

`branch` est le nouveau nom (`null` après `delete`), `previous_branch` l'ancien.
`migrate` produit le schéma complet, comme `create`.

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
