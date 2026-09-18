# 07 — Règles communes

Ce qui s'applique à toutes les commandes : les options, la façon dont `jgit` pose
ses questions, ce qu'il exige de votre dépôt, et comment l'adapter à votre projet.

---

## Les options

| Option | Ce qu'elle fait | Où elle sert |
| --- | --- | --- |
| `--based-on <branche>` | impose le point de départ | `feature start`, `feature rebase`, `demo start` |
| `--from <branche>` | désigne une source à intégrer — **répétable** | `release merge`, `demo merge`, `util verify_rebase` |
| `--into <branche>` | désigne explicitement la cible | `release merge`, `release finish`, `demo merge`, `util verify_rebase` |
| `--no-open` | ne pas ouvrir de pull request | `feature start`, `feature restart` |
| `--squash` | regrouper les commits avant de rejouer | `feature rebase` |
| `--no-interaction` | ne poser aucune question | partout |
| `-h`, `--help` | afficher l'aide complète | partout |

Une option donnée à une commande qui ne la lit pas est **ignorée en silence** :
`jgit feature start MONPROJET-1 --squash` ne produit aucune erreur et ne fait
aucun squash.

En revanche, une option **inconnue** (`--bidule`) ou privée de sa valeur
(`--based-on` en fin de ligne) fait échouer la commande immédiatement, avant toute
action sur le dépôt.

---

## Les questions et leurs réponses par défaut

Quand `jgit` s'apprête à faire quelque chose d'irréversible, il demande. La
réponse appliquée si vous validez sans rien saisir est **toujours signalée par la
majuscule** :

```
Souhaitez-vous continuer ? (Y/n)                              ← Entrée = oui
Souhaitez-vous squasher ces commits avant le rebase ? (y/N)   ← Entrée = non
```

Il n'existe aucune question affichée `(y/n)` : la touche Entrée a toujours un
effet connu d'avance.

**Toute réponse autre que `y` vaut refus.** Taper `oui`, `Y` ou `bidule` annule
l'opération — c'est volontaire : dans le doute, `jgit` ne fait rien.

### `--no-interaction`

Cette option applique la réponse par défaut de **chaque** question, c'est-à-dire
celle en majuscule. Elle est faite pour les scripts et les enchaînements.

Deux conséquences à connaître :

- **Elle ne déclenche jamais un squash de rebase** (la réponse par défaut est non).
- **Elle ne peut pas résoudre un conflit.** Face à un conflit, la commande s'arrête
  proprement avec un message explicite, remet tout en ordre, et vous invite à
  relancer sans l'option. Un conflit demande un humain.

---

## La fraîcheur des branches

`jgit` travaille toujours sur la version du serveur. À chaque fois qu'il se place
sur une branche — la vôtre, une branche de PR, la préprod, la production, une
version — il la remet à niveau avant d'agir.

| Votre branche locale… | Ce que fait `jgit` |
| --- | --- |
| est **en retard** | la met à jour, et vous le dit |
| est **en avance** (commits non poussés) | l'accepte, et vous le signale — **il ne pousse pas** |
| a **divergé** | s'arrête, sans rien modifier ni chez vous ni sur le serveur |

```
La branche feature/MONPROJET-123 a divergé de origin/feature/MONPROJET-123.
2 commit(s) uniquement en local, 1 commit(s) uniquement sur le serveur.
jgit ne choisit pas à votre place : réconciliez la branche (rebase ou merge) puis relancez.
```

Réconciliez comme vous en avez l'habitude, puis relancez la commande.

### L'exception du rebase

Pendant un rebase, une fois l'historique réécrit, les branches divergent du serveur
**par construction** — c'est exactement ce que la republication finale va corriger.
`jgit` ne les remet donc pas à niveau à ce moment-là.

---

## L'espace de travail doit être au propre

Ici, `jgit` se comporte différemment selon ce que vous faites. La distinction est
volontaire.

### Avec `feature` et `hotfix` : il range pour vous

Ce sont des commandes avec lesquelles on **travaille**. Si vous avez des
modifications non commitées, `jgit` propose de les mettre de côté et **vous les
rend** en fin de commande :

```
You have uncommited modifications.
Do you want to stash and unstash changes at the end of process ? (Y/n)
```

Si vous refusez, la commande s'arrête sans rien toucher.

### Avec `release` et `demo` : il refuse

Ce sont des commandes qui **fabriquent** un livrable à partir d'un état connu du
serveur. Elles ne rangent rien à votre place — elles s'arrêtent et vous disent quoi
faire :

```
Votre espace de travail contient des modifications non commitées.
Une release ne se fabrique pas sur un dépôt en cours de modification.

Mettez-les de côté puis relancez :
  git stash push -u -m "avant jgit"
  # puis, une fois la commande terminée : git stash pop
```

Même logique pour les **commits non publiés** sur la branche de départ :

```
La branche main porte 2 commit(s) qui ne sont pas sur origin/main.
Une release doit partir de la version du serveur, et jgit ne décide pas à votre
place du sort de commits que vous n'avez pas publiés.

Publiez-les :
  git push origin main

…ou mettez-les de côté puis relancez :
  git switch main
  git branch sauvegarde-main
  git reset --hard origin/main
```

> **Pourquoi cette différence ?** Le sort d'un commit que vous n'avez pas choisi de
> publier vous appartient. `jgit` peut refuser d'avancer ; il ne peut pas décider à
> votre place de l'effacer ou de le pousser.

---

## Configurer `jgit` pour votre projet

Par défaut, `jgit` suppose une production nommée `main`, une préprod nommée
`develop`, et un serveur nommé `origin`.

Si votre projet diffère, créez un fichier `.jgit/conf_local.sh` à la racine du
dépôt — pensez à ajouter `.jgit/` à votre `.gitignore` :

```bash
#!/bin/bash

j2s_remote="origin"
branch_prod="master"
branch_preprod="integration"
squash_threshold=8
```

| Réglage | Ce qu'il change | Défaut |
| --- | --- | --- |
| `j2s_remote` | le nom du serveur | `origin` |
| `branch_prod` | la branche de production | `main` |
| `branch_preprod` | la branche de préprod | `develop` |
| `squash_threshold` | à partir de combien de commits le squash est proposé | `8` |

### Si la branche de base n'existe pas

Une commande qui part d'une branche — `feature start`, `hotfix start`,
`feature rebase`, `demo start` — tient cette branche de l'un de trois endroits :

| D'où vient la valeur | Exemple |
| --- | --- |
| votre saisie | `--based-on demo_sprint12` |
| la branche d'origine enregistrée à la création | un `feature rebase` sans `--based-on` |
| le calcul automatique de la référence du projet | `develop` pour une feature |

**Les trois peuvent désigner une branche qui n'existe pas** : une faute de frappe,
une release livrée puis supprimée, une démo effacée après la démo. `jgit` les
contrôle donc toutes les trois, au même endroit, et **refuse dans les mêmes
termes** — seule la ligne qui dit d'où vient la valeur change :

```
La branche de base demo_sprint12 n'existe pas (ni en local ni sur origin).
C'est la branche d'origine de feature/MONPROJET-412, enregistrée à sa création :
elle a sans doute été livrée puis supprimée depuis.
Rien n'a été modifié : ni vos branches, ni le serveur.

jgit ne devine pas sur quelle branche vous vouliez partir, et ne se rabat pas sur
une autre à votre place.

Relancez en nommant une branche qui existe :
  jgit feature rebase MONPROJET-412 --based-on <branche>

La référence du projet est develop. Si c'est bien elle que vous voulez :
  jgit feature rebase MONPROJET-412 --based-on develop
```

La ligne de provenance est la seule qui diffère :

| Provenance | Ce que dit `jgit` |
| --- | --- |
| `--based-on` | *« Elle a été demandée par --based-on : vérifiez son orthographe. »* |
| base enregistrée | *« C'est la branche d'origine de …, enregistrée à sa création : elle a sans doute été livrée puis supprimée depuis. »* |
| référence du projet | *« C'est la référence du projet, choisie automatiquement. »* |

**Pourquoi ne pas se rabattre sur `develop`.** Parce que ce n'est pas la même
opération. Rejouer vos commits sur `develop` au lieu de la démo dont ils partent
déplace la branche — et sur un `rebase`, le résultat part en `push --force`. Le
choix vous appartient ; `jgit` s'arrête et vous le rend.

### Si aucune branche de référence n'est trouvée

`jgit` cherche d'abord la branche configurée, puis se replie sur `develop`,
`master`, `main` — dans cet ordre, en regardant **aussi bien chez vous que sur le
serveur**. C'est ce qui permet de démarrer un ticket sur un dépôt fraîchement
cloné, où la préprod n'existe pas encore en local.

S'il ne trouve rien, il refuse clairement :

```
Erreur : aucune branche de référence valide trouvée.
```

C'est le signe qu'il faut renseigner `.jgit/conf_local.sh`.

---

## Les syntaxes dépréciées

Deux commandes ont changé de forme. Les anciennes fonctionnent encore **à
l'identique**, mais affichent un avertissement et seront retirées.

| Ancienne forme | Forme actuelle |
| --- | --- |
| `jgit release merge <branche>` | `jgit release merge --from <branche>` |
| `jgit clean` | `jgit util clean` |

```
[déprécié] « jgit clean » : utilisez désormais « jgit util clean ».
L'ancienne forme fonctionne encore mais sera retirée dans une prochaine version.
```

Pour `release merge`, `jgit` distingue les deux formes au **format de
l'argument** : `1.4.0` ou `release/1.4.0` est un numéro de version, tout le reste
est une branche source. Mélanger les deux — `jgit release merge feature/A --from
feature/B` — est refusé explicitement.

---

## Ce que `jgit` ne fera jamais

Quatre garanties, valables partout :

1. **Il ne pousse rien à votre place.** Avoir des commits non poussés n'est pas une
   anomalie et ne bloque pas votre travail quotidien.
2. **Il ne choisit pas entre deux historiques.** Face à une divergence, il
   s'arrête.
3. **Il ne supprime pas un travail que vous n'avez pas publié.** Il refuse
   d'avancer, en vous donnant les commandes possibles.
4. **Un refus ne laisse aucune trace.** Quand une commande s'arrête — argument
   invalide, confirmation refusée, conflit — rien n'a été créé ni modifié, chez
   vous comme sur le serveur.

La seule action qui échappe à la quatrième règle est un échec **après** la
publication : si GitHub refuse d'ouvrir une PR ou de publier une release, les
branches et les tags sont déjà partis. `jgit` le dit alors explicitement, en
précisant ce qui reste à faire à la main — et seulement cela.

---

## `jgit` ne fonctionne que sur Mac

L'outil refuse de démarrer sur un autre système. Ce n'est pas un confort : sur
Linux, certaines commandes se comporteraient mal **sans le signaler**, et un rebase
pourrait publier votre branche vidée de votre travail.

```
jgit ne fonctionne que sur macOS (système détecté : Linux).
```

Seule l'aide (`jgit --help`) reste accessible. Le détail et l'état d'avancement
sont dans [`docs/05-portabilite.md`](../05-portabilite.md).

---

## Où trouver quoi

| Vous cherchez… | C'est ici |
| --- | --- |
| l'installation, l'alias, les prérequis | [README principal](../../README.md) |
| le vocabulaire et le cycle complet | [01 — Concepts](01-concepts.md) |
| une commande précise | fiches [02](02-feature-et-hotfix.md) à [06](06-utilitaires.md) |
| ce qui est vérifié par les tests | [Parcours couverts](../02-parcours-couverts.md) |
| pourquoi `jgit` ne tourne que sur Mac | [Portabilité](../05-portabilite.md) |
