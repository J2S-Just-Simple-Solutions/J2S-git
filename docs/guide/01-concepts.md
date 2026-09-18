# 01 — Les concepts

Six notions suffisent à comprendre tout le reste. Prenez dix minutes ici, les
autres fiches iront beaucoup plus vite.

---

## 1. La paire de branches

Quand vous démarrez un ticket, `jgit` ne crée pas une branche mais **deux** :

| Branche | Rôle | Qui écrit dessus |
| --- | --- | --- |
| `feature/MONPROJET-123` | **votre branche de travail** : vous y commitez | vous |
| `__PR__feature/MONPROJET-123` | **la branche de PR** : elle reçoit le code validé | la relecture, via GitHub |

Votre pull request va de la branche de travail **vers** la branche de PR — jamais
directement vers la préprod.

```
  develop ──────────────────────────────────────────────

     └── __PR__feature/MONPROJET-123  ← votre PR pointe ici
              └── feature/MONPROJET-123  ← vous travaillez ici
```

### Pourquoi deux branches

Parce que la branche de PR sert de **sas**. Tant que votre PR n'est pas validée,
elle ne contient aucun de vos changements : elle est vide de code métier. Le jour
où quelqu'un valide la PR, GitHub y écrase tout votre travail **en un seul
commit** (« Squash and merge »), propre et relu.

C'est ensuite cette branche de PR — et elle seule — qui part en release. Autrement
dit : **ce qui est livré est ce qui a été relu**, jamais ce qui est en cours.

### Ce que ça change pour vous

Au quotidien, rien : vous travaillez sur `feature/MONPROJET-123` comme sur
n'importe quelle branche, avec vos `git commit` et vos `git push` habituels. La
branche de PR ne vous concerne pas — `jgit` la supprime même de votre machine
après l'avoir créée, pour ne pas encombrer votre liste de branches. Elle continue
d'exister sur le serveur.

---

## 2. La branche de référence

C'est la branche **dont part** votre travail. `jgit` la choisit selon ce que vous
faites :

| Vous démarrez… | Ça part de… | Parce que… |
| --- | --- | --- |
| une `feature` | la **préprod** (`develop`) | une évolution s'intègre à ce qui est en cours de validation |
| un `hotfix` | la **production** (`main`) | un correctif urgent ne doit pas embarquer ce qui n'est qu'en préprod |
| une `release` | la **production** (`main`) | une version se construit à partir de ce qui tourne |
| une `demo` | la **préprod**, sauf indication contraire | une démo montre l'état à venir |

Vous pouvez toujours imposer un autre point de départ avec `--based-on`.

> **Le piège que ça évite.** Un correctif urgent démarré depuis la préprod
> embarquerait en production tout ce qui n'y est pas encore. C'est la principale
> raison d'être de cette distinction : `hotfix` n'est pas un synonyme décoratif de
> `feature`.

Si votre projet n'utilise pas les noms `develop` et `main`, dites-le à `jgit` une
fois pour toutes dans un petit fichier de configuration — voir
[07 — Règles communes](07-regles-communes.md#configurer-jgit-pour-votre-projet).

---

## 3. « Travailler sur la version du serveur »

C'est la règle la plus importante de `jgit`, et celle qui explique la plupart de
ses messages.

**Avant chaque action, `jgit` remet la branche concernée au niveau du serveur.**
Pas de fusion, pas de bricolage : il rejoue simplement ce qui manque. Trois cas :

| Votre branche locale… | `jgit` |
| --- | --- |
| est **en retard** sur le serveur | la met à jour, et vous le dit |
| est **en avance** (vous avez commité sans pousser) | l'accepte telle quelle, et vous le signale |
| a **divergé** (des commits des deux côtés) | **s'arrête**, sans rien modifier |

Deux garanties en découlent :

- **`jgit` ne pousse jamais à votre place.** Avoir des commits d'avance est le cas
  normal d'une branche sur laquelle vous venez de travailler — ça ne bloque rien.
- **`jgit` ne choisit pas entre deux historiques.** Si votre branche a divergé, à
  vous de réconcilier, puis de relancer.

> Il existe deux exceptions, toutes deux expliquées le moment venu : pendant un
> rebase, et sur les commandes `release` et `demo`, qui sont plus strictes
> ([07 — Règles communes](07-regles-communes.md#lespace-de-travail-doit-etre-au-propre)).

---

## 4. Le cycle complet d'un ticket

Voici le chemin que suit un ticket, de son ouverture à sa mise en production.
Chaque étape a sa fiche.

```
  1. jgit feature start MONPROJET-123     → vos deux branches + votre PR
         ↓
  2. vous codez : git commit, git push    → jgit ne s'en mêle pas
         ↓
  3. (si la préprod a bougé)
     jgit feature rebase MONPROJET-123    → vous rattrapez sans casser la PR
         ↓
  4. quelqu'un valide la PR sur GitHub    → le code relu arrive sur __PR__
         ↓
  5. jgit release merge --from feature/MONPROJET-123
                                          → le code relu entre dans la version
         ↓
  6. jgit release finish                  → fusion en production, tag, release
```

Entre 4 et 5, vous pouvez repartir pour un second lot de travail sur le même
ticket : c'est `jgit feature restart`.

---

## 5. Les commits `[jgit]`

En lisant l'historique, vous croiserez des commits **vides** dont le message
commence par `[jgit]`. Ils ne contiennent aucun code : ce sont des **repères**.

| Ce que vous voyez | Ce que ça veut dire |
| --- | --- |
| `[jgit] INIT feature/MONPROJET-123` | la branche de PR a été créée ici |
| `[jgit] commit for automatic PR creation … START …` | votre branche de travail a été créée ici |
| `[jgit] … RESTART …` | un nouveau lot de travail a démarré ici |
| `[jgit] INIT release release/1.4.0.` | la branche de version a été créée ici |
| `[jgit] Release merge feature branch : …` | ce ticket a été intégré à la version |
| `[jgit] INIT demo demo_sprint12` | la branche de démo a été créée ici |
| `[jgit] DEMO merge feature feature/… ` | ce ticket a été ajouté à la démo |

Ils servent à `jgit` à se repérer — savoir où commence votre travail, ce qui a
déjà été intégré, ce qu'il doit rejouer. **Ne les supprimez pas** : plusieurs
commandes cessent de fonctionner sans eux.

Ils disparaissent d'eux-mêmes du produit fini : le « Squash and merge » de la PR
les absorbe.

---

## 6. La branche d'origine

Une branche ne dit pas d'où elle vient. Git sait retrouver l'endroit où deux
branches se séparent, jamais **laquelle a servi de point de départ** : six commits
plus tard, une feature partie d'une démo ressemble en tout point à une feature
partie de la préprod.

`jgit` note donc le point de départ au moment où il crée la branche, dans le
**corps** du commit `[jgit]` correspondant :

```
[jgit] INIT feature/MONPROJET-123 [empty_commit]

jgit-branch: feature/MONPROJET-123
jgit-based-on: develop
```

Vous ne verrez jamais ces deux lignes : ni dans `git log --oneline`, ni dans la
liste des commits de GitHub. Elles voyagent avec la branche, résistent aux rebases
et disparaissent avec le commit `[jgit]` quand la PR est mergée.

Elles servent à deux choses :

- **savoir où vous en êtes**, sans avoir à vous rappeler d'où vous étiez parti :
  `jgit util check_rebase` ([06 — Utilitaires](06-utilitaires.md)) ;
- **rebaser au bon endroit** : `jgit feature rebase` vous propose votre vraie base
  plutôt que la référence du projet ([03 — Rebase](03-rebase.md)).

> **Et les branches d'avant ?** Celles créées par une version antérieure de `jgit`
> — ou à la main — n'ont pas cette trace, et `jgit` ne l'invente pas.
> `util check_rebase` vous répond alors qu'il ne sait pas, plutôt que de supposer
> la préprod et de vous donner une réponse fausse. Un `feature rebase` la leur
> donne au passage : après lui, la branche redevient lisible.

---

## Le vocabulaire en un coup d'œil

| Terme | Ce que ça désigne |
| --- | --- |
| **branche de travail** | `feature/…` ou `hotfix/…` — la vôtre, vous commitez dessus |
| **branche de PR** | `__PR__feature/…` — le sas qui reçoit le code validé |
| **branche de référence** | ce dont part votre travail : préprod ou production |
| **préprod** | `develop` par défaut — ce qui est en cours de validation |
| **production** | `main` par défaut — ce qui tourne réellement |
| **branche de version** | `release/1.4.0` — la version en préparation |
| **branche de démo** | `demo_sprint12` — un assemblage temporaire, jetable |
| **branche d'origine** | la branche dont la vôtre est réellement partie, notée par `jgit` à la création |
| **le serveur** | `origin`, c'est-à-dire GitHub |

---

**Suite :** [02 — Feature et hotfix](02-feature-et-hotfix.md)
