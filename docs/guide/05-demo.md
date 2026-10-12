# 05 — Démo

> `jgit demo list` · `show` · `candidates` · `create` · `add` · `drop` · `refresh` · `rebase` · `continue` · `abort` · `archive` · `unarchive` · `delete` · `migrate`

---

## À quoi ça sert

Assembler plusieurs tickets sur une branche pour les **montrer ensemble** — à un
client, en fin de sprint, sur un environnement de démonstration — avant de
décider ce qui part réellement en version.

Une démo vit longtemps : on y ajoute des tickets, on en retire, on la remet à
jour quand la préprod avance. `jgit` s'occupe de la mécanique ; vous décidez de
ce qu'elle contient.

---

## Le principe : une démo est une recette

Une démo, c'est **une base** (la préprod, le plus souvent) et **une liste de
tickets**, dans un ordre donné. Elle vit sur une branche `demo/<nom>`.

```
  develop ──┬───────────────────────────────────────────────
            │
            └── demo/sprint12 ── ① ① ⟦412⟧ ── ② ⟦88⟧ ── ③ ③ ⟦500⟧

            ① MONPROJET-412    ② MONPROJET-88    ③ MONPROJET-500
```

- Les commits de chaque ticket sont **recopiés tels quels** (cherry-pick), puis
  un commit repère `⟦…⟧` ferme le ticket. La recette est écrite dans la branche
  elle-même : il n'y a rien d'autre à configurer, rien à synchroniser.
- Comme la démo **contient** ses tickets, elle sait dire, ticket par ticket,
  s'il est à jour, s'il a avancé depuis, s'il a été livré entre-temps.
- **Retirer un ticket ou changer de base reconstruit la démo** à partir
  d'elle-même : les conflits que vous avez déjà résolus le restent.

**On ne livre jamais depuis une démo.** Quand elle est validée, on repasse par
`jgit release merge` avec les mêmes tickets, une fois leurs PR validées : ce qui
part en version, c'est le code relu.

### Ce que `jgit` sait dire de chaque ticket

| État | Ce que ça veut dire | Ce qu'on fait |
| --- | --- | --- |
| ✔ **à jour** | la démo contient tout le ticket | rien |
| ↻ **a avancé** | le ticket a de nouveaux commits, pas encore dans la démo | `jgit demo add` les ajoute à la suite |
| ≠ **réécrit** | le ticket a été squashé ou modifié depuis son ajout | `jgit demo refresh` le reprend en entier |
| ✖ **branche supprimée** | le ticket n'existe plus sur le serveur | il sera retiré au prochain `rebase` |
| ✔ **livré dans develop** | le ticket est déjà dans la base | il sera retiré au prochain `rebase` — son code y reste, puisqu'il est dans la base |

Un ticket rebasé avec `jgit feature rebase` **reste reconnu à jour** : `jgit`
reconnaît ses commits à leur auteur, leur date et leur message, que le rebase
conserve.

---

## Regarder

### `demo list` — toutes les démos

```bash
jgit demo list
```

```
Démos sur origin

  NOM                      BASE         TICKETS     ETAT
  client-a                 develop      3 tickets   ⚠ en retard de 4 commit(s) sur develop · 1 ticket(s) à reprendre
  sprint12                 develop      5 tickets   ✔ à jour
  recette                  main         1 ticket    ✔ à jour

Détail d'une démo : jgit demo show <nom>
2 démo(s) archivée(s) : jgit demo list --archived
```

`--archived` montre les démos archivées, `--all` toutes.

### `demo show` — le détail d'une démo

```bash
jgit demo show client-a
```

```
Démo client-a (demo/client-a)
  Base         develop — en retard de 4 commit(s)
  Mise à jour  2026-10-12 09:14 par Yann

Tickets
   1. feature/MONPROJET-412        ✔ à jour
   2. feature/MONPROJET-88         ↻ 2 commits pas encore dans la démo
      → jgit demo add client-a --from feature/MONPROJET-88
   3. hotfix/MONPROJET-500         ✔ livré dans develop
      → retiré au prochain « jgit demo rebase client-a »

À faire
  jgit demo rebase client-a

Pour livrer ces tickets (une fois leurs PR validées)
  jgit release merge --from feature/MONPROJET-412 --from feature/MONPROJET-88
```

Chaque ligne qui demande une action donne **la commande à lancer**. Lancée
depuis une branche `demo/…`, `jgit demo show` sans nom montre cette démo-là.

### `demo candidates` — ce qu'on peut ajouter

```bash
jgit demo candidates client-a
```

Liste les tickets du serveur (`feature/…`, `hotfix/…`) qui ne sont pas encore
dans la démo, du plus récent au plus ancien, et met à part ceux déjà livrés dans
la base — inutile de les ajouter.

Ces trois commandes **ne font que lire** : elles ne touchent ni à votre espace de
travail ni à votre branche, et fonctionnent même pendant qu'un conflit attend.

---

## Fabriquer

Toutes les commandes qui modifient une démo :

- partent de la **version du serveur** — jamais de votre copie locale ;
- travaillent sur une branche temporaire `jgit_demo_<nom>` : **vous restez sur
  votre branche**, et votre espace de travail doit être propre ;
- ne publient qu'à la fin, d'un seul geste, et **seulement si personne n'a
  modifié la démo entre-temps** — sinon rien n'est écrasé (code 4) ;
- ne publient **rien** quand il n'y avait rien à faire ;
- acceptent `--dry-run` pour voir ce qui serait fait, sans rien faire.

### `demo create` — créer une démo

```bash
jgit demo create sprint12
jgit demo create sprint12 --from feature/MONPROJET-412 --from hotfix/MONPROJET-500
jgit demo create recette --based-on main
```

Le nom est obligatoire : lettres, chiffres, `.`, `_` ou `-`. La base est la
préprod, sauf `--based-on`. `jgit` annonce ce qu'il va créer et demande
confirmation.

### `demo add` — ajouter des tickets

```bash
jgit demo add sprint12 --from feature/MONPROJET-88
jgit demo add sprint12 --from feature/MONPROJET-88 --from feature/MONPROJET-90
```

Les tickets s'ajoutent **à la suite**, dans l'ordre donné, sans rien réécrire :
la démo avance simplement. Pour un ticket **déjà présent** qui a avancé, seuls
ses nouveaux commits sont ajoutés. Un ticket déjà à jour ne change rien.

### `demo drop` — retirer des tickets

```bash
jgit demo drop sprint12 --from feature/MONPROJET-88
```

La démo est **reconstruite sans le ticket** : ce qui le précède ne bouge pas, ce
qui le suit est rejoué depuis la démo elle-même. `jgit` montre ce qu'il va
retirer et demande confirmation.

### `demo refresh` — reprendre un ticket réécrit

```bash
jgit demo refresh sprint12 --from feature/MONPROJET-412
```

Quand un ticket a été squashé ou modifié depuis son ajout, ses commits ne
s'ajoutent plus à la suite. `refresh` le reprend **en entier depuis sa branche**,
à sa place dans la démo.

### `demo rebase` — remettre la démo à jour sur sa base

```bash
jgit demo rebase sprint12
jgit demo rebase sprint12 --based-on main
```

La démo est reconstruite sur la **version actuelle** de sa base. Au passage :

- les tickets **livrés** dans la base sont retirés (`--keep-delivered` pour les
  garder) ;
- les tickets dont la **branche a disparu** sont retirés (`--keep-missing` pour
  les garder : la démo contient leurs commits) ;
- les commits **ajoutés à la main** sur la démo sont rejoués à la fin et
  signalés (`--drop-foreign` pour les écarter).

Une démo déjà à jour n'est pas republiée.

---

## Les conflits

Les tickets d'une démo n'ont pas été écrits ensemble : ils peuvent se marcher
dessus. `jgit` les traite comme pendant un [rebase](03-rebase.md#les-conflits),
avec `--on-conflict` :

| Conduite | Quand | Sur un conflit |
| --- | --- | --- |
| `ask` | défaut en interactif | attend que vous ayez résolu et commité dans un autre terminal |
| `abort` | défaut avec `--no-interaction` ou `--json` | annule tout, rien n'a été publié |
| `pause` | sur demande | s'arrête et vous laisse résoudre ; `jgit demo continue` reprend |

```bash
jgit demo add sprint12 --from feature/MONPROJET-88 --on-conflict pause
```

```
Conflit pendant l'ajout de tickets à la démo demo/sprint12, sur le ticket feature/MONPROJET-88.
Commit en cause : 4f5a6b7 « Refonte de la facturation » (branche jgit_demo_sprint12)
Fichiers en conflit :
  - src/facturation.php (modifié des deux côtés)

L'opération est en pause : rien n'a été poussé.
Résolvez les conflits dans les fichiers, marquez-les résolus (git add <fichier>), puis :
  jgit demo continue sprint12
Pour tout annuler :
  jgit demo abort sprint12
```

**La résolution fait partie de la démo.** Retirer plus tard un autre ticket, ou
rebaser la démo sur une préprod qui a avancé, la rejoue sans vous la redemander.

> C'est aussi ainsi qu'une IA gère une démo pour vous : elle lance la commande
> avec `--on-conflict pause --json`, lit les fichiers en conflit, les résout, puis
> lance `jgit demo continue`.

---

## Archiver, restaurer, supprimer

### `demo archive` — mettre une démo de côté

```bash
jgit demo archive client-a
```

La démo est renommée `demo-archive/2026-10-12_client-a` : **son nom est libéré**
pour une nouvelle démo, et la précédente reste consultable (`jgit demo show
demo-archive/2026-10-12_client-a`, `jgit demo list --archived`). Une seconde
archive du même nom le même jour devient `demo-archive/2026-10-12.2_client-a`.

Rien n'est réécrit : la branche change de nom, pas de contenu. Une archive est
**en lecture seule**.

### `demo unarchive` — reprendre une démo archivée

```bash
jgit demo unarchive client-a                          # s'il n'y a qu'une archive de ce nom
jgit demo unarchive demo-archive/2026-10-12_client-a  # sinon, en la nommant
```

Refusé si une démo active porte déjà ce nom : archivez-la d'abord. Une démo
restaurée est peut-être en retard sur sa base : `jgit demo show` le dit.

### `demo delete` — supprimer une démo

```bash
jgit demo delete client-a
jgit demo delete demo-archive/2026-10-12_client-a
```

Après confirmation, la démo disparaît du serveur, et votre copie locale avec elle
si elle n'a rien de plus. Pour une démo active, `jgit` rappelle que l'archive est
souvent préférable.

### Les anciennes démos `demo_<nom>` : `demo migrate`

Les démos fabriquées par la première version de `jgit` (`demo_<nom>`) restent
lisibles, mais ne se modifient plus. `migrate` les recrée au format actuel, avec
les mêmes tickets à jour :

```bash
jgit demo migrate vitrine
jgit demo migrate vitrine --based-on develop    # si l'ancienne ne dit pas de quelle base elle est partie
```

L'ancienne est conservée : `jgit demo delete demo_vitrine` quand vous n'en avez
plus besoin.

### Les anciennes commandes

`jgit demo start`, `merge` et `remove` restent acceptées, avec un avertissement,
et fabriquent des démos au format actuel :

| Ancienne forme | Forme actuelle |
| --- | --- |
| `jgit demo start [<nom>]` | `jgit demo create <nom>` (sans nom : celui de la base) |
| `jgit demo merge --from <ticket> [--into <nom>]` | `jgit demo add <nom> --from <ticket>` |
| `jgit demo remove` (depuis la démo) | `jgit demo delete <nom>` |
| `jgit demo list` (depuis la démo) | `jgit demo show <nom>` |

---

## Scénarios

### Scénario 1 — Préparer la démo du sprint

> **Yann** prépare la démonstration du vendredi.

```bash
jgit demo candidates
jgit demo create sprint12 --from feature/MONPROJET-412 \
                          --from feature/MONPROJET-88 \
                          --from hotfix/MONPROJET-500
```

La branche `demo/sprint12` est publiée ; l'environnement de démonstration la
déploie.

### Scénario 2 — Un ticket a avancé depuis

> Mercredi, Camille pousse deux commits de plus sur `MONPROJET-88`.

```bash
jgit demo show sprint12
#  2. feature/MONPROJET-88   ↻ 2 commits pas encore dans la démo
#     → jgit demo add sprint12 --from feature/MONPROJET-88
jgit demo add sprint12 --from feature/MONPROJET-88
```

Seuls les deux nouveaux commits sont ajoutés, à la suite.

### Scénario 3 — Le client ne veut plus voir un ticket

```bash
jgit demo drop sprint12 --from hotfix/MONPROJET-500
```

### Scénario 4 — La préprod a avancé, et un ticket y a été livré

```bash
jgit demo rebase sprint12
```

```
JGit va reconstruire la démo demo/sprint12 sur la version actuelle de develop
  - feature/MONPROJET-412 (déjà livré dans develop)
Souhaitez-vous continuer ? (Y/n)
```

### Scénario 5 — De la démo à la livraison

```bash
jgit demo show sprint12
# Pour livrer ces tickets (une fois leurs PR validées)
#   jgit release merge --from feature/MONPROJET-88 --from hotfix/MONPROJET-500
```

**Ce qui part en version n'est pas ce qui était dans la démo**, mais le code
relu et validé des mêmes tickets.

### Scénario 6 — Remplacer une démo sans perdre la précédente

> Le client veut une nouvelle démo `client-a`, mais on garde l'ancienne sous le
> coude.

```bash
jgit demo archive client-a
jgit demo create client-a --from feature/MONPROJET-120
```

L'ancienne reste consultable dans `jgit demo list --archived`.

---

## Ce qui bloque

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Espace de travail modifié | refuse, et donne la commande pour le mettre de côté | une démo se fabrique, elle ne se travaille pas |
| Nom de démo invalide, ou démo déjà existante (`create`) | refuse (code 2) | |
| Base inconnue (`--based-on` ou base enregistrée) | refuse en la nommant, sans rien créer | [même refus, mot pour mot, que pour une feature](07-regles-communes.md#si-la-branche-de-base-nexiste-pas) |
| Ticket au mauvais format ou absent du serveur | refuse : *« le format attendu est feature/\<ticket\> ou hotfix/\<ticket\> »* | |
| `add` d'un ticket réécrit depuis son ajout | refuse et propose `refresh` | ses commits ne s'ajoutent plus à la suite |
| `add` d'un ticket déjà livré dans la base | refuse | son code est déjà dans la démo |
| `drop` d'un ticket absent de la démo | refuse | |
| Démo inconnue | refuse ; si elle a des archives, les liste | |
| Un commit de **fusion** a été poussé à la main sur la démo | `drop`, `refresh` et `rebase` refusent, sauf `--drop-foreign` | une fusion ne se rejoue pas commit par commit |
| Quelqu'un a modifié la démo pendant l'opération | ne publie rien (code 4) | son travail n'est jamais écrasé |
| Une opération est en pause sur un conflit | toute commande qui modifie refuse (code 5) ; les commandes de lecture restent possibles | l'opération occupe l'espace de travail |
| Conflit avec `--no-interaction` | annule tout, rien n'a été publié (code 3) | un conflit demande quelqu'un pour le résoudre |
| Modifier une archive | refuse, et donne la commande `unarchive` | une archive est en lecture seule |
| Modifier une démo `demo_<nom>` | refuse, et donne la commande `migrate` | l'ancien format ne se modifie plus |
| `unarchive` d'un nom qui a plusieurs archives | refuse en les listant | |
| `unarchive` alors qu'une démo active porte le nom | refuse | archivez d'abord celle-ci |
| `migrate` d'une démo sans base enregistrée | refuse et demande `--based-on` | `jgit` ne devine pas une base |

---

## Limites connues

- **Un ticket est reconnu à ses commits** (auteur, date, message). Un squash, un
  commit amendé ou réécrit à la main le fait passer en « réécrit » : `refresh` le
  reprend.
- **La résolution d'un conflit dépend des tickets qui l'entourent.** Retirer un
  ticket avec lequel un autre était en conflit fait réapparaître le conflit :
  c'est normal, le code n'est plus le même.
- **« Livré » se lit dans les traces jgit** que la release fait remonter dans la
  base. Un ticket fusionné autrement (à la main, hors jgit) n'est pas reconnu
  comme livré.
- **Les anciennes démos `demo_<nom>`** restent lisibles (`demo list`, `demo
  show`) mais ne se modifient plus : `migrate` les convertit. Un ticket dont la
  branche a disparu depuis ne peut pas être repris par `migrate`.
- **L'archive porte la date du jour du poste** qui archive.

---

**Suite :** [06 — Utilitaires](06-utilitaires.md)
