# Les commits que jgit écrit, et ceux qu'il relit

> Écrit à l'occasion du hotfix `commit_init_du_ticket`, après qu'un commit dont
> le *message* citait un commit d'init a été pris pour le début d'un ticket : la
> démo a été publiée sans la majeure partie de son contenu, sans un mot. La
> colonne « Défaut » du § 2 décrit l'état **d'avant** ce hotfix ; tous les
> lecteurs suivent depuis la règle du § 3, par le module du § 4.

jgit ne tient aucun état hors de git : tout ce qu'il sait d'une branche, il le
relit dans les commits qu'il y a posés lui-même. Ce document dit **qui écrit
quoi, à quel moment, sur quelle branche, ce que ce commit devient ensuite, et
qui le relit pour en déduire quoi**. Il fixe ensuite la règle unique de lecture
et le module qui la porte.

---

## 1. Ce que jgit écrit

Tous les sujets commencent par `[jgit]` (`prefix_commit`) ; ceux des commits
vides finissent par `[empty_commit]` (`suffix_init_commit`). `<T>` est un ticket
(`feature/X`, `hotfix/X`, ou depuis 1.1.0 une branche quelconque d'une démo).

| # | Sujet exact | Corps (trailers) | Écrit par, quand | Sur quelle branche | Ce qu'il devient |
| --- | --- | --- | --- | --- | --- |
| E1 | `[jgit] INIT <T> [empty_commit]` | `jgit-branch: __PR__<T>`, `jgit-based-on: <base>` | `feature/hotfix start` | `__PR__<T>` | reste sur `__PR__<T>` ; remonte dans la release puis dans la base au `release merge` (trace de livraison) |
| E2 | `[jgit] commit for automatic PR creation - this commit will be deleted by squash and merge - START <T> [empty_commit]` | `jgit-branch: <T>`, `jgit-based-on: <base>` | `feature/hotfix start` | `<T>` | **disparaît** au squash-and-merge de la PR… mais son **sujet est recopié** dans le corps du message de squash GitHub (`* <sujet>`) |
| E3 | idem avec `RESTART <T>` | `jgit-branch: <T>`, `jgit-based-on: <base de __PR__>` (rien si inconnue) | `feature/hotfix restart` | `<T>` recréée depuis `__PR__<T>` | comme E2 |
| E4 | E1/E2/E3 rejoués | trailers **réécrits** (`restamp_based_on_head`) avec la nouvelle base | `feature rebase` (moteur de rejeu) | `__PR__<T>` puis `<T>` | comme l'original |
| E5 | `[jgit] INIT release release/<x.y.z>. [empty_commit]` | `jgit-branch`, `jgit-based-on: <prod>` | `release start` | `release/<x.y.z>` | remonte dans la production au `release finish` |
| E6 | `[jgit] Release merge feature branch : __PR__<T>` | — | `release merge` (`merge --no-ff`) | `release/<x.y.z>` | trace de livraison dans la base |
| E7 | `Merge release branch : release/<x.y.z>` (**sans** `[jgit]`) | — | `release finish` | production | — |
| E8 | `[jgit] INIT demo demo/<nom> [empty_commit]` | `jgit-branch`, `jgit-based-on`, `jgit-demo-format: 2` | `demo create`, et toute reconstruction | `demo/<nom>` | reste |
| E9 | `[jgit] DEMO ticket <T> [empty_commit]` | `jgit-demo-ticket: <T>`, `jgit-demo-commits: <n>` | toute opération de démo, après les commits d'un ticket | `demo/<nom>` | reste ; clôt le segment du ticket |
| E10 | message choisi par l'utilisateur (défaut proposé) | — | `feature rebase --squash` | `<T>` | commit ordinaire |

Formats anciens, encore **lus**, plus jamais écrits : `[jgit] Merge feature
branch : __PR__<T> [[empty_commit]]` (ancien E6), `[jgit] INIT demo demo_<nom>
…` et `[jgit] DEMO merge <type> <branche>` (démos du premier format), commits
d'init sans trailers (d'avant la branche d'origine).

**Ce qui circule hors de jgit et ressemble à ses commits :**

- le **message de squash GitHub** d'une PR : sujet = titre de la PR (`… (#N)`),
  corps = la liste des sujets de ses commits, `* [jgit] … START <T>
  [empty_commit]` compris ;
- un commit **repris** (cherry-pick, ou recopié à la main comme lors de la
  linéarisation de `2026-POC-colorisation-ripolin-BP`) garde ce message entier ;
- les commits d'init **des autres tickets** : la release fait remonter E1 et E6
  dans la base, donc dans les ancêtres de toute branche partie ensuite de cette
  base.

## 2. Ce que jgit relit

| # | Qui | Pour savoir | Règle actuelle | Défaut |
| --- | --- | --- | --- | --- |
| L1 | `demo_ticket_range` (démos) | où commencent les commits d'un ticket | `[empty_commit]` **n'importe où dans le message**, sur la lignée principale de la branche | **le bug** : un message de squash recopié devient le début du ticket ; un ticket sans init à lui prend celui d'un autre ticket hérité de la base — *corrigé sur la branche du hotfix* |
| L2 | `audit_ticket_eval` (audit) | idem, pour simuler le rebase | 1) commit le plus récent portant le trailer `jgit-branch: <T>` ; 2) à défaut, comme L1 dans `base..ticket` | le 2) — *corrigé sur la branche du hotfix* |
| L3 | `feature_rebase` | les commits de `__PR__<T>` à rejouer | ligne commençant par `[jgit] INIT <type>` (`get_last_commit_with_pattern`), **n'importe quelle ligne**, **n'importe quel ticket**, tout l'historique (pas la lignée principale) | peut prendre l'E1 d'un autre ticket remonté par une release plus récente |
| L4 | `find_last_init_commit_index` (squash au rebase) | après quel commit squasher | `[empty_commit]` dans le **sujet** | prend aussi un E9, ou l'init d'un autre ticket repris |
| L5 | `replay_restamp_if_init` (rejeu) | quels commits rejoués reçoivent la nouvelle base | `[empty_commit]` dans le **sujet** | idem L4 : réécrirait les trailers d'un commit qui n'est pas l'init de cette branche |
| L6 | `release merge` (garde-fou) | la PR a-t-elle été validée ? | sujet du dernier commit **égal** à E1 reconstruit sur place | correct ; texte recopié |
| L7 | `audit_ticket_eval` | idem (`pr_validated`) | sujet **égal** à E1 reconstruit sur place | correct ; texte recopié |
| L8 | `release finish` | la release est-elle vide ? | sujet **égal** à E5 reconstruit sur place | correct ; texte recopié |
| L9 | `read_based_on`, `audit_tickets_table` | la base d'une branche | trailer `jgit-branch: <branche>` exact, puis dernier `jgit-based-on` | sûr : le trailer nomme la branche |
| L10 | `demo_read` | init de la démo, sa base, ses segments | ligne commençant par `[jgit] INIT demo ` ; trailer `jgit-based-on` ; repères E9 par une **expression régulière qui réécrit en dur** `[jgit]` et `[empty_commit]` | le ticket du repère n'est pas recoupé avec `jgit-demo-ticket` ; constantes dupliquées |
| L11 | `demo_read_legacy` | démos du premier format | découpe du sujet en mots | à garder tel quel (lecture seule) |
| L12 | `demo_delivered_cache_load` | tickets livrés dans la base | `sed` sur les sujets E1, E6 et ancien E6 | correct ; troisième façon d'analyser un sujet |

## 3. Ce qui ne se discute plus

1. **Le sujet fait foi, jamais le message entier.** Un message (`%B`) peut citer
   n'importe quoi : liste de squash, commit recopié, trailers. Une recherche
   `--grep` (qui lit tout le message) ne sert qu'à présélectionner ; la décision
   se prend sur `%s`.
2. **Un commit d'init n'est un commit d'init que de la branche qu'il nomme.** Le
   début d'un ticket est son E1/E2/E3 à lui, jamais le premier `[empty_commit]`
   venu. Une branche sans init à elle se lit depuis sa base.
3. **Le trailer confirme quand il existe.** Si un candidat porte `jgit-branch`,
   ce trailer doit désigner la même branche (`<T>` ou `__PR__<T>`) ; un
   désaccord l'écarte. Sans trailer (commit ancien), le sujet suffit.
4. **On remonte la lignée principale** (`--first-parent`) : c'est elle que jgit
   a construite ; un ancêtre arrivé par une fusion n'est pas à la branche.
5. **Écrire et relire viennent de la même source.** Le texte d'un sujet n'existe
   qu'à un endroit ; la reconnaissance compare à ce qui serait écrit, elle ne
   recopie pas le texte.

## 4. La cible : un module, deux sens

Une section unique de `functions.sh` (« Sujets des commits jgit ») porte tout ce
qui touche aux sujets jgit.

**Fabriquer** — une fonction, un sujet par sorte :

| Fonction | Sorte |
| --- | --- |
| `jgit_subject init_pr <T>` | E1 |
| `jgit_subject start <T>` / `restart <T>` | E2 / E3 |
| `jgit_subject init_release <release>` | E5 |
| `jgit_subject release_merge <__PR__T>` | E6 |
| `jgit_subject init_demo <demo>` / `demo_marker <T>` | E8 / E9 (remplacent `demo_init_subject` / `demo_marker_subject`) |

**Reconnaître** — un seul analyseur, tous les lecteurs en dérivent :

| Fonction | Rend | Remplace |
| --- | --- | --- |
| `jgit_subject_parse <sujet>` | `<sorte> <branche>` si le sujet est **exactement** l'un de ceux que `jgit_subject` écrit (formats anciens compris), rien sinon | les comparaisons, regex et `sed` de L4 à L8, L10, L12 |
| `is_init_subject_of <sujet> <T>` | vrai si sorte ∈ {init_pr, start, restart} et branche = `<T>` | — (déjà sur la branche du hotfix, à réécrire sur l'analyseur) |
| `last_init_commit_of <T> <plage> [sortes]` | le dernier commit de la lignée principale qui est un init de `<T>` (règles 1 à 4) | L1, L2, L3 |

**Chaque lecteur, une fois migré :**

| Lecteur | Devient |
| --- | --- |
| L1, L2 | `last_init_commit_of <T> …` |
| L3 | `last_init_commit_of <T> __PR__<T> init_pr` (le dernier E1 de ce ticket sur sa branche de PR) |
| L4 | index du dernier commit dont `is_init_subject_of … <T>` |
| L5 | `is_init_subject_of <sujet> <ticket de la phase>` |
| L6, L7 | `jgit_subject_parse` = `init_pr <T>` |
| L8 | `jgit_subject_parse` = `init_release <release>` |
| L10 | repères par `jgit_subject_parse` = `demo_marker`, recoupés avec `jgit-demo-ticket` |
| L12 | `jgit_subject_parse` sur les sujets de la base : `init_pr` et `release_merge` (formats anciens compris) |
| L9, L11 | inchangés |

## 5. Ce qui le prouve

Les tests restent **par l'extérieur** (choix n°1) : chaque défaut se prouve par
un scénario, joué en échec sur l'ancien code avant d'être corrigé.

| Défaut | Scénario |
| --- | --- |
| L1 : un commit repris d'une PR squash-mergée délimitait le ticket | 17 — « Un commit qui cite un commit d'init dans son message ne délimite pas le ticket » (le mock GitHub écrit désormais, comme GitHub, la liste des commits dans le message de squash) |
| L3 : une branche renommée était rebasée sur l'init d'un autre nom, et poussée | 05 — « Une branche renommée à la main n'est pas rebasée » (`init_commit_missing`) |
| Écritures (E1 à E9) inchangées au caractère près | toute la suite : les sujets écrits sont relus par les parcours de ticket, de release et de démo |

Non couverts par un scénario, faute de pouvoir les obtenir par un parcours réel
(« reproduire, jamais fabriquer ») : l'alerte sur un trailer contradictoire
(vérifiée à la main sur un dépôt jetable), et les défauts latents de L4 / L5
(il faudrait un commit d'init d'un autre ticket dans les commits de travail).

## 6. Décisions

1. **Où** : dans `functions.sh` pour l'instant (section « Sujets des commits
   jgit »), pas de nouveau fichier.
2. **Le trailer** (règle 3) : une contradiction entre le sujet et `jgit-branch`
   **ne bloque pas** mais **lève une alerte** visible (sortie d'erreur, aussi en
   `--json`) : le commit est retenu d'après son sujet. On mesurera l'impact avant
   d'en faire un refus ; l'essentiel est qu'aucune incohérence ne passe en silence.
3. **Branches renommées, init introuvable** : `feature rebase` **refuse**
   (`init_commit_missing`) au lieu de prendre l'init d'un autre ticket. jgit ne
   traite que les branches qu'il gère proprement. (Les démos, ouvertes depuis
   1.1.0 aux branches quelconques, gardent leur lecture depuis la base pour une
   branche sans init à elle.)
4. **Périmètre** : tout dans ce hotfix.
