# 03 — Rebase

> `jgit feature rebase` · `jgit hotfix rebase`

---

## À quoi ça sert

Rattraper ce qui a été livré en préprod pendant que vous travailliez, **sans
casser votre pull request**.

---

## Le problème que ça résout

Vous avez ouvert votre ticket il y a une semaine. Depuis, trois collègues ont
livré en préprod. Votre branche est partie d'un état qui n'existe plus.

La solution habituelle — fusionner la préprod dans votre branche — produit un
historique enchevêtré et une PR illisible. `jgit` fait l'inverse : il **rejoue
votre travail par-dessus** la préprod à jour, comme si vous aviez commencé
aujourd'hui.

```
  AVANT                                APRÈS

  develop ──A──B──C  (livré depuis)     develop ──A──B──C
     │                                              │
     └── votre travail ──1──2──3                    └── votre travail ──1'──2'──3'
```

Comme les deux branches sont réécrites, `jgit` doit ensuite les **republier en
écrasant** celles du serveur. C'est normal et attendu — mais c'est pour cette
raison que la commande vous demande **deux fois** confirmation.

---

## Comment ça marche

```bash
jgit feature rebase MONPROJET-123
```

1. `jgit` vérifie que tout est en ordre (voir *Ce qui bloque*) ;
2. si votre branche est partie d'ailleurs que de la référence du projet, il vous
   le dit et propose **sa vraie base** (voir *Sur quelle branche il vous rebase*) ;
3. il vous montre la liste des commits qu'il va rejouer, et sur quelle branche il
   va se baser, puis demande : **« Souhaitez-vous continuer ? »** ;
4. il reconstruit les deux branches sur des copies temporaires, en rejouant vos
   commits **un par un** ;
5. il vous affiche l'historique obtenu et demande : **« Confirmez-vous que le
   rebase s'est bien passé ? »** ;
6. seulement alors, il republie les deux branches sur le serveur, puis fait le
   ménage.

> **Tant que vous n'avez pas répondu à la seconde question, le serveur n'a pas
> bougé.** Si vous répondez non, les deux branches réécrites sont supprimées de
> votre machine et votre branche de travail est récupérée telle qu'elle est sur le
> serveur : vous revenez à l'état d'avant.

---

## Sur quelle branche il vous rebase

Par défaut, le rebase vise la **référence du projet** : la préprod pour une
`feature`, la production pour un `hotfix`.

Sauf que votre branche n'en est peut-être pas partie. Si vous l'avez démarrée avec
`--based-on`, depuis une démo ou depuis une release, la rejouer sur `develop` la
déplacerait là où elle n'a rien à faire — silencieusement, ce qui était le
comportement des versions précédentes.

`jgit` note désormais le point de départ à la création
([la branche d'origine](01-concepts.md#6-la-branche-dorigine)) et vous le rappelle
quand il diffère :

```
La branche feature/MONPROJET-412 est partie de demo_sprint12, et non de la
référence du projet develop.
Rebaser sur demo_sprint12 ? (Y/n)
```

| Votre réponse | Ce qui se passe |
| --- | --- |
| Entrée ou `y` | le rebase vise `demo_sprint12`, votre vraie base |
| `n` | le rebase vise `develop`, la référence du projet — votre branche change officiellement de base |

La majuscule le dit : **votre base d'origine est la réponse par défaut**, et c'est
donc elle que `--no-interaction` applique.

Deux cas où la question ne se pose pas :

- vous avez passé `--based-on` : il fait autorité, sans rien demander ;
- votre branche est partie de la référence du projet — il n'y a rien à signaler.

Dans tous les cas, le rebase **met la trace à jour** : après lui, la branche
enregistre la base sur laquelle il vient de la reconstruire. C'est aussi ainsi
qu'une branche d'avant ce mécanisme en acquiert une.

> Si la base enregistrée n'existe plus — une release livrée, une démo supprimée —
> `jgit` le signale et se rabat sur la référence du projet, sans poser de question.

---

## Les conflits

Comme vos commits sont rejoués **un par un**, chacun peut produire son propre
conflit. Quand ça arrive, `jgit` s'arrête et vous laisse la main :

```
Erreur lors du cherry-pick du commit a1b2c3d. Conflit détecté.
Merci de ne rien faire ici tant que le conflit n'est pas résolu et commité
Avez vous résolu et commité la résolution de conflit ? (Y/n)
```

Vous résolvez le conflit **dans un autre terminal**, vous commitez, puis vous
répondez `y` dans celui de `jgit`, qui reprend où il en était.

Si vous répondez `n`, tout est annulé : rien n'a été publié.

### Réduire les conflits à un seul : `--squash`

Sur une PR volumineuse, résoudre dix conflits d'affilée est pénible. L'option
`--squash` regroupe **tous vos commits de travail en un seul** avant de rejouer.
Il ne reste alors qu'un conflit à traiter.

```bash
jgit feature rebase MONPROJET-123 --squash
```

**Votre code n'est jamais modifié** — seul l'historique de votre branche est
réécrit. `jgit` vous demande le message du commit unique ; laisser vide reprend le
message du premier commit regroupé.

Au-delà de **8 commits de travail**, `jgit` vous propose spontanément le squash :

```
La branche feature/MONPROJET-123 contient 12 commits de travail.
Les squasher en un seul commit (option --squash) limiterait les conflits à résoudre à un seul.
Souhaitez-vous squasher ces commits avant le rebase ? (y/N)
```

Remarquez la majuscule sur le **N** : la réponse par défaut est **non**. Regrouper
votre historique doit rester une décision explicite ; valider sans rien saisir le
conserve intact. Le seuil de 8 est configurable.

Si vous interrompez le rebase après un squash — en refusant une confirmation, ou
sur un conflit impossible à résoudre — **votre historique d'origine est restauré**.

---

## Options

| Option | Effet |
| --- | --- |
| `--based-on <branche>` | se rebaser sur une autre branche que la référence habituelle — fait autorité, aucune question n'est posée |
| `--squash` | regrouper vos commits de travail en un seul avant de rejouer |
| `--no-interaction` | ne rien demander — **ne déclenche jamais le squash** et **ne peut pas traiter un conflit** |

---

## Scénarios

### Scénario 1 — Rattraper la préprod avant de faire relire

> **Camille** a fini son export CSV. Entre-temps, deux livraisons sont passées en
> préprod.

```bash
jgit feature rebase MONPROJET-412
```

`jgit` liste ses trois commits, annonce qu'il se basera sur `develop`, elle répond
`y`. Pas de conflit. Il affiche l'historique obtenu : son travail est bien au
sommet de la préprod à jour. Elle répond `y` à la seconde question.

```
Rebase terminé avec succès
```

Sa PR sur GitHub ne montre plus que ses changements à elle.

### Scénario 2 — Un conflit à résoudre

> Sam se rebase, un collègue a touché le même fichier.

```
Cherry-picking commit: 4f5a6b7
Erreur lors du cherry-pick du commit 4f5a6b7. Conflit détecté.
Merci de ne rien faire ici tant que le conflit n'est pas résolu et commité
Avez vous résolu et commité la résolution de conflit ? (Y/n)
```

Sam **ouvre un second terminal**, règle le conflit dans son éditeur, commite la
résolution. Il revient dans le terminal de `jgit`, répond `y`. Le rebase continue.

> Ne fermez pas le terminal de `jgit` et ne répondez pas `y` avant d'avoir
> commité : il reprendrait sur un état incomplet.

### Scénario 3 — Une grosse PR, un seul conflit

> Alex a 14 commits sur son ticket et sait que le fichier de configuration a bougé
> en préprod.

```bash
jgit feature rebase MONPROJET-88 --squash
```

```
Message du commit squashé (Entrée pour conserver « Ajoute le socle de facturation ») :
> Socle de facturation complet
```

Un seul commit à rejouer, donc un seul conflit. Il le résout une fois. Tout son
code est là — seul l'historique a été condensé.

### Scénario 4 — Trop de commits, on lui propose

```bash
jgit feature rebase MONPROJET-88
```

```
La branche feature/MONPROJET-88 contient 14 commits de travail.
Souhaitez-vous squasher ces commits avant le rebase ? (y/N)
```

Alex appuie sur Entrée sans réfléchir : la réponse par défaut étant **non**, son
historique est conservé. C'est voulu — une réécriture d'historique ne se déclenche
pas par inattention.

### Scénario 5 — Se rebaser sur la production plutôt que la préprod

```bash
jgit feature rebase MONPROJET-412 --based-on main
```

Utile quand un ticket doit finalement partir en correctif urgent.

---

## Ce qui bloque

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Votre branche ou sa branche de PR n'existe pas sur le serveur | refuse en la nommant | il n'y a rien à republier |
| Votre PR a **déjà été mergée** | refuse : *« n'est PAS un fast-forward … Cela peut se produire si vous avez déjà cloturé la PR »* | le cas n'est pas géré ; faites un `restart` à la place |
| Un **commit de fusion** est présent dans l'historique | refuse en le nommant | une fusion ne se rejoue pas commit par commit ; ne mélangez pas merge et rebase |
| La base enregistrée n'existe plus sur le serveur | le signale et se rabat sur la référence du projet | on ne rejoue pas sur une branche disparue |
| Vous répondez `n` à la première question | s'arrête : rien n'a été touché | |
| Vous répondez `n` à la seconde question | supprime les branches réécrites et récupère votre branche de travail du serveur | l'état d'avant est rétabli, le serveur n'a jamais bougé |
| Conflit **avec** `--no-interaction` | s'arrête proprement, annule tout, restaure votre historique | un conflit demande un humain : il n'est jamais validé tout seul |
| `--based-on` sur une branche inconnue | refuse en la nommant | |
| Votre branche a divergé du serveur | s'arrête sans rien modifier | |

> **Le remote n'est poussé qu'en toute dernière étape.** Quel que soit le motif
> d'arrêt avant cela, ce qui est sur le serveur est intact.

---

## Limites connues

- **Un `rebase` ne sait pas traiter une PR déjà mergée puis rouverte.** Le message
  vous oriente vers `restart`.
- **Les commits de fusion sont rédhibitoires.** Si vous avez fusionné la préprod
  dans votre branche par le passé, `jgit` ne pourra plus la rebaser : il faudra la
  reprendre à la main, ou passer par un `restart` après validation de la PR.
- **`--no-interaction` ne fait jamais de squash**, même au-delà du seuil : il
  applique la réponse par défaut, qui est non.
- **`--squash` regroupe uniquement vos commits de travail**, c'est-à-dire ceux
  posés après le repère de démarrage. Ce qui est déjà passé par la branche de PR
  n'est pas touché.
- **Les branches créées avant ce mécanisme n'ont pas de base enregistrée.** Le
  rebase se comporte alors comme avant — il vise la référence du projet — et leur
  donne leur trace au passage.

---

**Suite :** [04 — Release](04-release.md)
