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
  comme avant ; leur document porte le code précis (`worktree_dirty`…) ;
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

Les documents propres aux démos (`jgit.demo.list/1`, `jgit.demo.show/1`…) sont
décrits avec les commandes de démo.

---

## Autres options utiles à un programme

| Option | Effet |
| --- | --- |
| `--no-interaction` | aucune question : la réponse par défaut est appliquée |
| `--no-fetch` | ne contacte pas le serveur, travaille sur les références déjà rapatriées — pour un affichage répété |
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
