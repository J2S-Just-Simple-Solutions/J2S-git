# 08 — État des lieux

> `jgit audit` · `jgit audit tickets` · `jgit audit demos [<nom>]` · `--apply`

## À quoi ça sert

Savoir, en une commande, **où en sont tous les tickets et toutes les démos du
projet**, ce qu'il faut faire pour les remettre d'équerre, **dans quel ordre**,
et surtout **qui doit intervenir**.

Rien n'est modifié : tout est simulé. Avec `--apply`, jgit lance ensuite ce qui
passe sans conflit (voir « Appliquer ce qui passe » plus bas).

---

## La commande

```bash
jgit audit                   # tous les tickets du serveur, puis toutes les démos
jgit audit tickets           # les tickets seulement
jgit audit demos             # les démos, et les tickets qu'elles contiennent
jgit audit demos client-a    # une seule démo
```

Le rapport dit, pour chaque ticket ou démo qui demande une action, **qui doit
intervenir et quoi lancer** — pas le détail des fichiers et des commits.
Le détail est dans `--json`, pour une IA ou un job planifié
([contrat `jgit.audit/1`](../06-contrat-cli.md)).

Le code de sortie vaut **3** dès que quelque chose coince — un rebase qui ne
passera pas, une base disparue, un ticket sans commit d'init, une démo bloquée —
et le rapport est émis quand même.

L'audit ne touche ni à votre espace de travail (même en cours de modification),
ni à votre branche, ni au serveur. Il fonctionne même pendant qu'un conflit
attend.

---

## Les tickets

Chaque branche `feature/…` et `hotfix/…` du serveur est comparée à **sa base**,
et son rebase est simulé **comme le ferait `jgit feature rebase`** : seuls ses
propres commits, ceux qui suivent son commit d'init, sont rejoués.

### Sa base

C'est celle choisie à sa création (`--based-on`). Un ticket créé avant que jgit
l'enregistre n'en a pas : sa base est alors **supposée** — parmi la préprod, la
production et les branches qu'un ticket ou une démo a déjà prises pour base,
celle dont il s'écarte le moins. Le rapport l'écrit
`ripolin (base supposée)`, et la commande proposée la donne explicitement
(`--based-on ripolin`) : sans elle, `jgit feature rebase` partirait sur la
préprod.

### Ses états

| État | Ce que ça veut dire | Que faire |
| --- | --- | --- |
| ✔ **à jour** | le ticket contient la dernière version de sa base | rien |
| ✔ **livré** | le ticket est déjà dans sa base | rien |
| ↻ **à rebaser** | sa base a avancé ; son rebase passera sans conflit | `jgit feature rebase <id>` |
| ✖ **son rebase coince** | sa base a avancé et touche les mêmes lignes que lui | `jgit feature rebase <id> --on-conflict pause` |
| ✖ **base disparue** | la branche dont il est parti n'existe plus | `jgit feature rebase <id> --based-on <branche>` |
| ✖ **sans commit d'init** | la branche n'a pas été créée par jgit : rien ne dit quels commits sont les siens | à rebaser à la main |

### Qui doit intervenir

- Pour un rebase qui coince : **les auteurs des commits du ticket qui touchent
  les fichiers en conflit** — pas tous ceux qui ont travaillé sur la branche.
- Sinon : le dernier à avoir travaillé sur la branche.

### Le titre de la PR

Sous chaque ticket, le titre de sa PR sur GitHub, sans la clé qu'il répète
souvent en tête. Il est lu avec `gh` ; sans `gh`, sans réseau ou avec
`--no-fetch`, le rapport s'en passe.

```
TICKETS (68)
  ✖ feature/MONPROJET-88 — en retard de 7 commit(s) sur ripolin (base supposée) : son rebase coince
      « Export public de la page »
      à faire par : Camille
      → jgit feature rebase MONPROJET-88 --based-on ripolin --on-conflict pause
  ✖ 1 autre(s) ticket(s) en retard, sans commit d'init : à rebaser à la main
      à faire par : Dominique (1)
  ↻ feature/MONPROJET-412 — en retard de 3 commit(s) sur develop, son rebase passe
      « Affiche le total TTC »
      à faire par : Yann
      → jgit feature rebase MONPROJET-412   (démos : client-a)
  ↻ 18 autre(s) ticket(s) en retard sur leur base, rebase sans conflit
      à faire par : Yann (8), Camille (6), Dominique (4)
  ✔ 1 à jour sur leur base, 31 déjà livré(s)
  Le détail, ticket par ticket (fichiers, commits) : jgit audit tickets --json
```

Sur un projet de centaines de branches, le rapport détaille ce qui coince et les
tickets des démos ; les autres tickets à rebaser, ou sans commit d'init, sont
**comptés par personne**.

---

## Les démos

Pour chaque démo, l'audit donne les commandes **dans l'ordre où il faut les
lancer** :

1. **D'abord les tickets, chez eux.** Un ticket de la démo en retard sur sa base
   se rebase sur sa propre branche (`jgit feature rebase`). C'est là que ses
   conflits avec la base se résolvent, **par son auteur** — pas dans la démo.
2. **Puis la démo** : `jgit demo rebase <nom>`, avec `--from <ticket>` pour
   chaque ticket à reprendre depuis sa branche plutôt que depuis la démo — un
   ticket réécrit (squash), un ticket dont l'auteur aura résolu un conflit, ou
   dont la version rebasée règle un conflit que la démo rencontrerait sinon.
3. **Enfin les nouveaux commits** des tickets qui ont avancé :
   `jgit demo add <nom> --from <ticket>`.

Les conflits qui restent dans la démo sont ceux **entre tickets** : ils se
résolvent dans la démo (`--on-conflict pause`), ou en retirant l'un des deux.
Pour chacun, le rapport dit **qui est concerné** : l'auteur du commit qui ne
passe pas, et en face ceux qui ont touché les mêmes fichiers, avec leur ticket.

```
DÉMOS (1)

  demo/client-a  (base develop)
    ✖ Conflit : feature/MENU-3 (à l'ajout de ses nouveaux commits)
        concerne : Yann (feature/MENU-3), Dominique (feature/CLIENT-4)
        → résoudre dans la démo : jgit demo add client-a --from feature/MENU-3 --on-conflict pause
        → ou retirer : jgit demo drop client-a --from feature/MENU-3
    Dans l'ordre :
      jgit feature rebase FACT-1 --on-conflict pause
        d'abord rebaser le ticket chez lui : son rebase sur develop coince — à faire par : Yann
      jgit demo rebase client-a --from feature/FACT-1
        base develop en retard de 1 commit(s) ; reprend feature/FACT-1 depuis leur branche
      jgit demo add client-a --from feature/MENU-3 --on-conflict pause
        feature/MENU-3 a de nouveaux commits
    ⚠ feature/FACT-1 : à simuler de nouveau une fois rebasé(s) chez eux.
```

| État d'une démo | Ce que ça veut dire |
| --- | --- |
| ✔ **à jour** | rien à faire |
| ✔ **faisable** | les commandes passeront sans conflit |
| ✖ **en conflit** | un conflit est prévu dans la démo, ou un de ses tickets doit d'abord être résolu chez lui |
| ✖ **bloquée** | sa base a disparu, ou un commit de fusion a été poussé à la main sur la démo |

Un ticket en conflit est écarté et la simulation reprend sans lui : **tous les
conflits sont signalés**, pas seulement le premier.

---

## Appliquer ce qui passe : `--apply`

```bash
jgit audit --apply              # l'état des lieux, puis ce qui passe sans conflit
jgit audit --apply --dry-run    # le plan seulement
jgit audit tickets --apply      # mes tickets seulement, pas les démos
jgit audit demos client-a --apply
```

Après l'état des lieux, jgit montre le plan, demande confirmation, puis lance,
dans l'ordre :

1. **le rebase de mes tickets** en retard sur leur base dont le rebase passe
   sans conflit — « mes » tickets : ceux où je suis parmi les personnes qui
   doivent intervenir (même nom ou même adresse que mon identité git) ;
2. **la mise à jour des démos faisables**, avec les commandes que l'audit a
   données.

```
APPLICATION — ce qui passe sans conflit
  À appliquer, dans l'ordre :
    jgit feature rebase MONPROJET-412
    jgit demo rebase client-a
  Laissé de côté :
    feature/MONPROJET-88 — base supposée ripolin, à vérifier avant de lancer : jgit feature rebase MONPROJET-88 --based-on ripolin
    3 ticket(s) d'autres personnes, à rebaser par elles : Camille (2), Dominique (1)
Appliquer le plan ci-dessus (2 opération(s)) ? (Y/n)
  ✔ jgit feature rebase MONPROJET-412
  ✔ jgit demo rebase client-a
  Appliqué : 2 sur 2.
```

Ce qui est **laissé de côté** :

- **les tickets des autres** : leurs commits garderaient leur nom, mais leur
  branche locale divergerait sans qu'ils le sachent — à eux de lancer leur
  rebase ;
- **les tickets à base supposée** : une supposition ne réécrit pas une branche
  toute seule ; vérifiez la base, puis lancez la commande donnée ;
- tout ce qui coince (conflit, base disparue, ticket sans commit d'init, démo en
  conflit ou bloquée) : voir le rapport au-dessus.

Chaque opération est **la vraie commande jgit** : même rejeu, même protection
si quelqu'un a poussé entre-temps (rien n'est écrasé), même abandon propre si un
conflit survient malgré la simulation. Une opération qui échoue n'arrête pas les
suivantes ; le détail est dans `.git/jgit/audit-apply.log`. À la fin, vous êtes
ramené sur votre branche, et les branches locales que les rebases ont dû créer
sont retirées.

L'espace de travail doit être **propre** : comme pour une démo, jgit ne range pas
votre travail en cours à votre place. Avec `--json` (ou `--no-interaction`), le
plan est appliqué sans question. Le code de sortie vaut 3 si une opération a
échoué, ou si quelque chose coince encore.

---

## Scénarios

### Un lundi matin : la préprod a bougé

```bash
jgit audit
```

Chacun lit les lignes « à faire par » qui le concernent. Les tickets dont le
rebase passe : `jgit feature rebase` sur le sien. Ceux dont le rebase coince :
avec `--on-conflict pause`, et l'on résout. Une fois les tickets à jour,
relancez `jgit audit demos` : il ne reste que les commandes de démo.

### Un ticket rebasé par son auteur

Yann a rebasé `feature/FACT-1` et résolu son conflit avec la préprod. Le segment
de `FACT-1` dans la démo, lui, est l'ancienne version : rejoué sur la nouvelle
préprod, il coincerait. L'audit le voit et propose
`jgit demo rebase client-a --from feature/FACT-1` : la démo reprend la version
résolue, sans nouveau conflit.

### Un ancien ticket parti d'une branche de projet

`feature/MONPROJET-88` a été créé depuis `ripolin`, une branche de projet,
avant que jgit enregistre la base. L'audit le compare à `ripolin`, pas à la
préprod, et propose `jgit feature rebase MONPROJET-88 --based-on ripolin`.

---

## Ce qui bloque

| Situation | Réponse |
| --- | --- |
| `jgit audit demos <nom>` d'une démo archivée | refusé (`read_only`) : une archive ne se met pas à jour |
| démo à l'ancien format (`demo_<nom>`) | ignorée et comptée à part : la convertir avec `jgit demo migrate` |
| démo inconnue | refusé (`demo_not_found`) |
| un nom de démo avec `jgit audit` ou `jgit audit tickets` | refusé (`usage`) : seul `audit demos` en prend un |
| `--apply` sur un espace de travail modifié | refusé (`worktree_dirty`) : mettez votre travail de côté (`git stash`) puis relancez |
| `--apply` avec une autre commande que `jgit audit` | refusé (`usage`) |
| une opération en pause sur un conflit | `--apply` refusé (`operation_in_progress`) : `continue` ou `abort` d'abord |
| serveur injoignable | refusé (code 6) ; `--no-fetch` audite les références déjà rapatriées |

---

## Limites connues

- Le rebase d'un ticket est jugé **sur l'ensemble de ses commits**. Rarement, un
  rebase commit par commit peut s'arrêter sur un commit intermédiaire alors que
  l'ensemble passe : `jgit feature rebase` s'arrête alors comme d'habitude sur
  le conflit.
- Une base **supposée** reste une supposition : un ticket parti d'une branche
  que personne d'autre n'a prise pour base sera comparé à la plus proche des
  bases connues.
- Un ticket dont le rebase coince n'est pas simulé dans la démo : sa version
  résolue n'existe pas encore. Relancez l'audit une fois le ticket rebasé.
- Un même développeur peut apparaître sous deux noms s'il a commité avec deux
  identités git (« Yann », « Yann Martin »).
- L'audit lit la version du serveur au moment où il tourne : un collègue peut
  pousser juste après.
