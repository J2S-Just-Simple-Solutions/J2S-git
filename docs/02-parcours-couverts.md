# Parcours couverts

Ce document décrit, fonctionnellement, ce que valident les scénarios de
`tests/features/`. Il se lit sans connaître le code des tests.

---

## Parcours 01 — D'une feature à sa mise en production

Fichier : [`tests/features/01_feature_vers_release.feature`](../tests/features/01_feature_vers_release.feature)

C'est le parcours nominal complet d'un ticket J2S : un développeur ouvre une
feature, la développe, la fait valider, puis elle part en production dans une
release.

### Situation de départ

Un dépôt avec une branche de production `main`, une branche de préprod `develop`,
un tag `1.0.0` et une configuration `.jgit/conf_local.sh` standard.

### Déroulé

```
  develop ──┬─────────────────────────────────────────────────────────────
            │
            └── __PR__feature/TEST-123 ──────────── (2) ──────────────┐
                    │                                                 │
                    └── feature/TEST-123 ── (1) ── commits ── (2)      │
                                                                       │
  main ────────────────────────────────────────┬────────── (3) ────────┤
                                               │                       │
                                               └── release/1.1.0 ──────┴── (4) ── tag 1.1.0
```

**(1) `jgit feature start TEST-123`** — en mode interactif.

`jgit` annonce ce qu'il va faire et demande confirmation. Le scénario vérifie que
la question est réellement posée, y répond `y`, puis contrôle que :

- la branche de travail `feature/TEST-123` existe en local et sur le remote, et
  que le développeur est laissé dessus ;
- la branche de PR `__PR__feature/TEST-123` existe **sur le remote uniquement** :
  elle est supprimée en local, c'est une branche de service ;
- les deux branches portent bien leur commit d'initialisation `jgit` ;
- une PR a été demandée à GitHub **de la branche de travail vers la branche de
  PR**, et pas vers `develop`.

Ce dernier point est le cœur de la convention J2S : la PR ne vise jamais
directement la préprod.

**(2) Le développeur travaille, puis la PR est validée.**

Deux vrais commits sont poussés sur la branche de travail. Le scénario vérifie
qu'à ce stade le code est bien sur la branche de travail et **pas encore** sur la
branche de PR : tant que la PR n'est pas validée, la branche de PR reste vide de
tout code métier.

La validation de la PR est ensuite rejouée comme le ferait GitHub : un
« Squash and merge », qui écrase le travail en un commit unique sur la branche de
PR. Le code s'y retrouve alors, sous le message de la PR.

**(3) `jgit release merge --from feature/TEST-123`**

Sans numéro de version, `jgit` calcule la suivante à partir du dernier tag :
`1.0.0` → `release/1.1.0`. Le scénario vérifie que :

- la branche de release est créée à partir de la production et poussée ;
- c'est bien la **branche de PR** qui est intégrée, pas la branche de travail —
  autrement dit le code validé, pas le code en cours ;
- le contenu attendu est présent dans la release ;
- l'historique porte les commits de traçabilité `[jgit]` ;
- **`main` n'a pas bougé** : une release en préparation ne touche pas la
  production.

**(4) `jgit release finish`**

Le scénario vérifie l'ensemble des effets, qui sont tous irréversibles :

- la release est mergée sur `main` et le contenu y est ;
- le tag `1.1.0` existe sur le remote et **pointe sur un commit contenant
  réellement le code de la feature** (un tag posé au bon endroit, pas seulement un
  tag présent) ;
- la branche de release a disparu du local **et** du remote ;
- `develop` n'a pas été touchée ;
- une release GitHub a été demandée pour le tag `1.1.0` ;
- au total, **exactement deux appels à GitHub** ont eu lieu sur tout le parcours :
  la création de la PR et la création de la release. Rien d'autre n'a été envoyé.

### Ce que ce parcours protège

| Régression qui serait attrapée |
| --- |
| Une PR ouverte vers `develop` au lieu de la branche `__PR__` |
| La branche de PR laissée en local, polluant la liste des branches du développeur |
| Une release construite depuis la branche de travail (code non validé) au lieu de la branche de PR |
| Un tag posé avant le merge, donc sur un commit sans le code |
| Une branche de release oubliée sur le remote |
| `main` ou `develop` modifiée à un moment où elle ne devrait pas l'être |
| Un appel à GitHub en trop (release créée deux fois, PR rouverte…) |
| Une question de confirmation supprimée par mégarde : le développeur ne serait plus prévenu avant une action irréversible |

---

## Parcours 02 — Le garde-fou de la ligne de commande

Fichier : [`tests/features/02_ligne_de_commande.feature`](../tests/features/02_ligne_de_commande.feature)

Avant même de manipuler des branches, `jgit` doit se comporter correctement face
à une commande mal formée. C'est la première protection de l'utilisateur : une
faute de frappe ne doit jamais se traduire par une action partielle sur le dépôt.

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| `jgit` sans argument | affiche l'aide, sans erreur |
| `jgit -h`, `--help`, `help` | affichent la même aide complète |
| Scope inconnu (`jgit bidule`) | refus explicite nommant le scope |
| Action inconnue (`jgit feature bidule`) | refus explicite, pour chacun des cinq scopes |
| Scope sans action (`jgit feature`) | affiche l'aide **et** sort en erreur |
| `feature`/`hotfix` sans identifiant | refus explicite nommant le type attendu |
| Option privée de sa valeur (`--based-on` en fin de ligne, ou suivie d'une autre option) | refus explicite nommant l'option |
| Option inconnue (`--bidule`) | refus explicite |
| Arguments positionnels en trop | refus explicite les nommant |
| `release merge` / `demo merge` sans `--from` | refus explicite |
| Dépôt sans remote `origin` | refus explicite… |
| …sauf pour l'aide | qui reste accessible sans remote |

### Ce que ce parcours protège

La garantie centrale est la même partout : **un refus ne laisse aucune trace sur
le dépôt**. Plusieurs scénarios le vérifient explicitement après le refus — la
branche que la commande aurait créée n'existe pas sur le remote. Une régression
qui créerait les branches *avant* de valider les arguments serait attrapée ici.

Le second acquis est la qualité des messages : ils sont vérifiés au mot près.
Un message d'erreur qui deviendrait vague ou trompeur casse le test.

---

## Parcours 03 — Création d'une feature ou d'un hotfix, cas par cas

Fichier : [`tests/features/03_feature_start.feature`](../tests/features/03_feature_start.feature)

Là où le [parcours 01](#parcours-01--dune-feature-à-sa-mise-en-production) suit le
chemin nominal de bout en bout, celui-ci explore en profondeur la seule commande
`start` et ses variantes.

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| `feature start` | se base sur `develop`, la préprod |
| `hotfix start` | se base sur `main`, la production — et ne récupère donc pas ce qui n'est qu'en préprod |
| Après création | la branche de PR n'est pas laissée en local |
| `--based-on <branche>` | impose la branche de référence à la place de la valeur par défaut |
| `--based-on <branche inconnue>` | refus explicite |
| `--no-open` | crée les branches sans demander de PR à GitHub |
| Confirmation refusée | **aucun effet** : pas de branche créée, ni en local ni sur le remote, rien envoyé à GitHub |
| `start` relancé sur une feature existante | la branche locale est réutilisée, pas recréée |
| Feature présente sur GitHub mais absente en local | elle est rapatriée depuis le remote |
| Branche locale sans équivalent distant | `jgit` le signale (la feature a probablement déjà été mergée) |
| Aucune branche de référence disponible | refus explicite et lisible, sans rien créer |
| `gh pr create` en échec | `jgit` sort en erreur en précisant que les branches sont poussées et qu'il ne reste que la PR à ouvrir |

### Ce que ce parcours protège

Le point le plus sensible est le choix de la branche de référence : un `hotfix`
basé par erreur sur `develop` embarquerait en production du code qui n'était
qu'en préprod. Le scénario le vérifie en plaçant, dans le contexte, un commit
présent uniquement sur `develop` et en contrôlant qu'il n'apparaît pas dans le
hotfix.

Le second est le respect du refus : quand l'utilisateur répond « non » à la
confirmation, le dépôt doit être exactement dans l'état où il était.

Le troisième est la qualité du diagnostic quand quelque chose échoue à la marge.
Deux scénarios s'en assurent : le message d'absence de branche de référence doit
rester lisible, et un échec côté GitHub ne doit ni passer inaperçu, ni laisser
croire qu'il faut tout recommencer.

---

## Parcours 04 — Relancer une feature après validation de sa PR

Fichier : [`tests/features/04_feature_restart.feature`](../tests/features/04_feature_restart.feature)

`jgit feature restart` sert à repartir d'une feature dont la PR vient d'être
mergée : la branche de travail est recréée depuis la branche de PR, pour repartir
sur une base propre sans ouvrir un nouveau ticket.

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| PR squash-mergée, puis `restart` | la branche de travail est recréée depuis la branche de PR et une nouvelle PR est demandée |
| Après le `restart` | le développeur peut recommencer à commiter et pousser normalement |
| PR pas encore mergée | refus : le `restart` n'est possible que si les deux branches portent le même code |
| `--no-open` | recrée la branche sans demander de PR |
| `hotfix restart` | se comporte comme `feature restart` |
| Feature inexistante | refus : aucune branche créée, rien de poussé |

### D'un scénario de caractérisation à un test de non-régression

Le dernier scénario a une histoire. Il figeait au départ un comportement
**constaté mais non souhaité** : un `restart` sur une feature inexistante créait
et poussait une branche de travail au lieu de refuser, parce que le garde-fou
reposait sur un `git ls-remote` sans `--exit-code` — une commande qui renvoie 0
même sans correspondance, donc une condition toujours fausse.

Le scénario portait un commentaire `# ANOMALIE CONNUE` annonçant qu'il passerait
au rouge le jour de la correction. C'est exactement ce qui s'est produit
(issue #34) : il a été inversé et décrit maintenant le refus attendu. Un
comportement discutable mais connu valait mieux qu'un angle mort.
