# 08 — État des lieux

> `jgit audit` · `jgit audit tickets` · `jgit audit demos [<nom>]`

## À quoi ça sert

Savoir, en une commande, **où en sont tous les tickets et toutes les démos du
projet**, ce qu'il faut faire pour les remettre d'équerre, **dans quel ordre**,
et **qui est concerné** quand quelque chose coince.

Rien n'est modifié : tout est simulé.

---

## La commande

```bash
jgit audit                   # tous les tickets du serveur, puis toutes les démos
jgit audit tickets           # les tickets seulement
jgit audit demos             # les démos, et les tickets qu'elles contiennent
jgit audit demos client-a    # une seule démo
```

`--json` donne le rapport complet, ticket par ticket, pour une IA ou un job
planifié ([contrat `jgit.audit/1`](../06-contrat-cli.md)). Le code de sortie vaut
**3** dès que quelque chose coince — un rebase qui ne passera pas, une base
disparue, une démo bloquée — et le rapport est émis quand même.

L'audit ne touche ni à votre espace de travail (même en cours de modification),
ni à votre branche, ni au serveur. Il fonctionne même pendant qu'un conflit
attend.

---

## Les tickets

Chaque branche `feature/…` et `hotfix/…` du serveur est comparée à **sa base** :
celle choisie à sa création (`--based-on`), à défaut la préprod pour une feature
et la production pour un hotfix.

| État | Ce que ça veut dire | Que faire |
| --- | --- | --- |
| ✔ **à jour** | le ticket contient la dernière version de sa base | rien |
| ✔ **livré** | le ticket est déjà dans sa base | rien |
| ↻ **à rebaser** | sa base a avancé ; son rebase passera sans conflit | `jgit feature rebase <id>` |
| ✖ **son rebase coince** | sa base a avancé et touche les mêmes lignes que lui | `jgit feature rebase <id> --on-conflict pause`, par son propriétaire |
| ✖ **base disparue** | la branche dont il est parti n'existe plus | `jgit feature rebase <id> --based-on <branche>` |

Pour un rebase qui coince, l'audit dit **qui est concerné** : le commit du
ticket qui ne passera pas et son auteur, les fichiers, et **en face** le dernier
commit de la base qui les a touchés, avec son auteur. Le **propriétaire** d'un
ticket est l'auteur du dernier commit de sa branche.

```
TICKETS (303)
  ✖ feature/FACT-1 — en retard de 1 commit(s) sur develop, son rebase coince
      commit 36de45e « Affiche le total TTC »
      par Yann <yann@j2s.net>, le 2026-10-19
      src/accueil.txt (modifié des deux côtés)
        en face : 131aa37 « Nouveau message d'accueil » par Camille <camille@j2s.net> (develop)
      → jgit feature rebase FACT-1 --on-conflict pause   (propriétaire : Yann · démos : client-a)
  ↻ feature/MENU-3 — en retard de 1 commit(s) sur develop, son rebase passe
      → jgit feature rebase MENU-3   (propriétaire : Yann · démos : client-a)
  ↻ 300 autre(s) ticket(s) en retard sur leur base, rebase sans conflit — par propriétaire : Yann (180), Dominique (120)
  La liste complète, ticket par ticket : jgit audit tickets --json
```

Sur un projet de centaines de branches, le rapport détaille ce qui coince et les
tickets des démos ; les autres tickets à rebaser sont **comptés par
propriétaire**. La liste complète est dans `--json`.

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

```
DÉMOS (1)

  demo/client-a  (base develop)
    Dans l'ordre :
      jgit feature rebase FACT-1 --on-conflict pause
        d'abord rebaser le ticket chez lui : son rebase sur develop coince (voir TICKETS) — propriétaire : Yann
      jgit feature rebase MENU-3
        d'abord rebaser le ticket chez lui : en retard de 1 commit(s) sur develop — propriétaire : Yann
      jgit demo rebase client-a --from feature/FACT-1
        base develop en retard de 1 commit(s) ; reprend feature/FACT-1 depuis leur branche
    ⚠ feature/FACT-1 : à simuler de nouveau une fois rebasé(s) chez eux.

Bilan : tickets — 0 à jour, 301 à rebaser, 2 en conflit, 0 base disparue, 0 livré(s) ; démos — 0 à jour, 0 faisable(s), 1 en conflit, 0 bloquée(s).
```

| État d'une démo | Ce que ça veut dire |
| --- | --- |
| ✔ **à jour** | rien à faire |
| ✔ **faisable** | les commandes passeront sans conflit |
| ✖ **en conflit** | un conflit est prévu dans la démo, ou un de ses tickets doit d'abord être résolu chez lui |
| ✖ **bloquée** | sa base a disparu, ou un commit de fusion a été poussé à la main sur la démo |

Pour un conflit dans la démo, le rapport dit le ticket, l'étape où il apparaît
(rebase de la démo, reprise du ticket depuis sa branche, ajout de ses nouveaux
commits), le commit qui ne passe pas et son auteur, et en face le commit qui a
touché les mêmes fichiers et d'où il vient (un autre ticket, la base, ou un
commit ajouté à la main) — avec les deux issues : résoudre dans la démo, ou
retirer le ticket. Un ticket en conflit est écarté et la simulation reprend
sans lui : **tous les conflits sont signalés**, pas seulement le premier.

---

## Scénarios

### Un lundi matin : la préprod a bougé

```bash
jgit audit
```

Les tickets dont le rebase passe : chacun lance `jgit feature rebase` sur le
sien. Ceux dont le rebase coince : leur propriétaire le lance avec
`--on-conflict pause` et résout. Une fois les tickets à jour, relancez
`jgit audit demos` : il ne reste que les commandes de démo.

### Un ticket rebasé par son auteur

Yann a rebasé `feature/FACT-1` et résolu son conflit avec la préprod. Le segment
de `FACT-1` dans la démo, lui, est l'ancienne version : rejoué sur la nouvelle
préprod, il coincerait. L'audit le voit et propose
`jgit demo rebase client-a --from feature/FACT-1` : la démo reprend la version
résolue, sans nouveau conflit.

---

## Ce qui bloque

| Situation | Réponse |
| --- | --- |
| `jgit audit demos <nom>` d'une démo archivée | refusé (`read_only`) : une archive ne se met pas à jour |
| démo à l'ancien format (`demo_<nom>`) | ignorée et comptée à part : la convertir avec `jgit demo migrate` |
| démo inconnue | refusé (`demo_not_found`) |
| un nom de démo avec `jgit audit` ou `jgit audit tickets` | refusé (`usage`) : seul `audit demos` en prend un |
| serveur injoignable | refusé (code 6) ; `--no-fetch` audite les références déjà rapatriées |

---

## Limites connues

- Le rebase d'un ticket est jugé **sur l'ensemble de ses modifications**, comme
  une fusion avec sa base. Rarement, un rebase commit par commit peut s'arrêter
  sur un commit intermédiaire alors que l'ensemble passe : `jgit feature rebase`
  s'arrête alors comme d'habitude sur le conflit.
- Un ticket dont le rebase coince n'est pas simulé dans la démo : sa version
  résolue n'existe pas encore. Relancez l'audit une fois le ticket rebasé.
- L'audit lit la version du serveur au moment où il tourne : un collègue peut
  pousser juste après.
