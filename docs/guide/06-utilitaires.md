# 06 — Utilitaires

> `jgit util clean` · `jgit util check_rebase` · `jgit util verify_rebase`

Trois commandes d'appoint, sans effet sur le serveur.

---

## `jgit util clean` — faire le ménage

### À quoi ça sert

Supprimer de votre machine les branches que `jgit` a créées pour son propre usage
et qui ne vous servent à rien.

```bash
jgit util clean
```

### Ce qui est supprimé

| Préfixe | Ce que c'est |
| --- | --- |
| `__PR__…` | des branches de PR récupérées du serveur — elles n'ont pas à vivre chez vous |
| `jgit_rebase_…` | des branches de travail d'un rebase, normalement effacées à la fin |
| `jgit_verify_rebase_…` | des copies temporaires d'une vérification de rebase |

**Vos branches ne sont jamais touchées** : `feature/…`, `hotfix/…`, `release/…`,
`demo_…`, la préprod et la production restent en place.

La commande n'agit **que sur votre machine** : rien n'est supprimé sur le serveur.

### Quand l'utiliser

Quand votre liste de branches locales est encombrée, ou après un rebase
interrompu — qui peut laisser des branches `jgit_rebase_*` derrière lui, lesquelles
gênent le rebase suivant.

```
Suppression des branches locales suivantes :
  __PR__feature/MONPROJET-412
  jgit_rebase_feature/MONPROJET-88
Suppression terminée.
```

S'il n'y a rien à nettoyer, elle vous le dit et s'arrête.

> L'ancienne forme `jgit clean` fonctionne encore, avec un avertissement. Elle sera
> retirée : prenez l'habitude de `jgit util clean`.

---

## `jgit util check_rebase` — où j'en suis par rapport à ma base

### À quoi ça sert

Répondre, sans rien taper d'autre, à la question qu'on se pose tous les matins :
**« ma branche est-elle encore à jour, et si je rebase, est-ce que ça passe ? »**

```bash
jgit util check_rebase
```

```
Branche   : feature/MONPROJET-412
Basée sur : develop (origin/develop)
Avance    : 7 commit(s) absents de develop
État      : en retard de 12 commit(s) sur develop.
Rebase    : passerait sans conflit.
  jgit feature rebase MONPROJET-412
```

Vous n'avez pas à nommer la base : `jgit` l'a notée au moment où il a créé la
branche — c'est la [branche d'origine](01-concepts.md#6-la-branche-dorigine).
C'est toute la différence avec `verify_rebase`, à qui il faut donner les deux
branches.

Pour interroger une autre branche que celle sur laquelle vous êtes :

```bash
jgit util check_rebase --from feature/MONPROJET-88
```

### Ce qu'elle ne modifie pas

Rien. Elle rejoue un rebase sur une copie jetable, en efface toute trace, et vous
laisse sur la branche où vous étiez. Ni votre travail, ni le serveur ne bougent.

### La réponse, pour un script

Le texte est pour vous, le **code de sortie** est pour vos outils :

| Code | Réponse |
| --- | --- |
| `0` | à jour sur sa branche d'origine, rien à faire |
| `1` | impossible de répondre (voir « Ce qui bloque » ci-dessous) |
| `2` | en retard, le rebase passerait sans conflit |
| `3` | en retard, des conflits sont à prévoir |

```bash
jgit util check_rebase --from feature/MONPROJET-412 >/dev/null
case $? in
  0) echo "à jour" ;;
  2) echo "à rebaser, ça passe" ;;
  3) echo "à rebaser, prévoir du temps" ;;
  *) echo "on ne sait pas" ;;
esac
```

### Quand l'utiliser

- Le matin, avant d'attaquer : savoir si la préprod vous a doublé pendant la nuit.
- Avant d'annoncer une date : un `3` veut dire qu'il faut prévoir du temps.
- Dans un tableau de bord d'équipe : une ligne par branche en cours.

---

## `jgit util verify_rebase` — essayer un rebase à blanc

### À quoi ça sert

Répondre à une seule question : **« si je rebase cette branche sur celle-là, est-ce
que ça passe ? »** — sans rien modifier.

```bash
jgit util verify_rebase --from feature/MONPROJET-412 --into develop
```

La réponse est `true` ou `false`, et rien d'autre ne change : ni votre branche, ni
votre espace de travail, ni le serveur.

| Réponse | Signification |
| --- | --- |
| `true` | le rebase passerait sans conflit |
| `false` | il y aurait au moins un conflit à résoudre — ou la demande est invalide |

Le code de sortie suit la réponse : c'est ce qui rend la commande utilisable dans
un script ou un tableau de bord.

### Quand l'utiliser

- Avant de lancer un vrai `jgit feature rebase`, pour savoir à quoi s'attendre.
- Pour vérifier d'un coup l'état de plusieurs branches en cours, sans les toucher.
- Dans un outil interne qui affiche « cette branche se rebase proprement ».

### Ce qu'elle ne fait pas

Elle ne **répare** rien et ne prépare rien : c'est une question, pas une action.
Un `true` ne dispense pas de lancer le vrai rebase.

---

## Scénarios

### Scénario 1 — Faire le ménage après un rebase interrompu

> Le rebase d'Alex s'est mal passé, il a fermé son terminal. Sa liste de branches
> est polluée.

```bash
jgit util clean
```

Les branches techniques disparaissent, son ticket et ses branches de projet
restent. Il peut relancer son rebase.

### Scénario 2 — Savoir avant de se lancer

> Camille hésite : sa branche traîne depuis trois semaines.

```bash
jgit util verify_rebase --from feature/MONPROJET-412 --into develop
```

```
false
```

Elle sait qu'il y aura des conflits. Elle prévoit le temps nécessaire, ou choisit
de passer par `--squash` pour n'en avoir qu'un seul à traiter.

### Scénario 3 — Reprendre une branche laissée de côté

> Sam revient de deux semaines de congés et ne se rappelle plus d'où partait sa
> branche.

```bash
jgit util check_rebase
```

```
Branche   : feature/MONPROJET-500
Basée sur : demo_sprint12 (origin/demo_sprint12)
Avance    : 3 commit(s) absents de demo_sprint12
État      : à jour sur demo_sprint12, il n'y a rien à rebaser.
```

Il avait oublié qu'il était parti d'une démo. Un `jgit feature rebase` classique
l'aurait envoyé sur `develop` sans qu'il s'en rende compte — c'est justement ce
que `jgit` lui proposera d'éviter.

### Scénario 4 — Vérifier plusieurs branches d'affilée

```bash
jgit util verify_rebase --from feature/A --into develop
jgit util verify_rebase --from feature/B --into develop
jgit util verify_rebase --from feature/C --into develop
```

Trois réponses, aucune modification nulle part. Léa sait dans quel ordre attaquer
sa journée.

---

## Ce qui bloque

### `util clean`

| Situation | Ce que fait `jgit` |
| --- | --- |
| Aucune branche technique | affiche *« Aucune branche locale à nettoyer »* et s'arrête |

Cette commande ne déclenche ni proposition de mise de côté, ni refus : elle ne
touche pas à votre espace de travail.

### `util check_rebase`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Branche créée avant ce mécanisme, ou à la main | répond *« Désolé : jgit ne sait pas répondre pour les anciennes branches. »* et sort en `1` | la branche d'origine n'est pas devinable : mieux vaut ne pas répondre qu'induire en erreur. Un `feature rebase` lui donnera sa trace |
| Branche d'origine supprimée depuis (une release livrée, une démo effacée) | refuse en la nommant, et sort en `1` | il n'y a plus rien sur quoi se comparer ; rebasez sur une branche vivante |
| Branche inconnue | refuse en la nommant, et sort en `1` | |
| `--from` fourni deux fois | refuse, et sort en `1` | la commande regarde une branche à la fois |
| Une branche en argument, sans `--from` | refuse et rappelle la bonne forme | un argument ignoré en silence est un piège |
| Espace de travail modifié | refuse, et sort en `1` | le rebase à blanc a besoin d'un dépôt propre ; **vos modifications sont intactes** |

### `util verify_rebase`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| `--into` absent | refuse, et répond `false` | il faut une cible |
| `--from` absent, ou fourni deux fois | refuse, et répond `false` | exactement une source est attendue |
| Branche source ou cible inconnue | refuse en la nommant, et répond `false` | |
| Espace de travail modifié | refuse, et répond `false` | la vérification a besoin d'un dépôt propre pour travailler ; **vos modifications sont intactes** |
| Source et cible identiques | répond `true` | il n'y a rien à rejouer |

---

## Limites connues

- **`check_rebase` simule un rebase Git ordinaire**, comme `verify_rebase` : la
  réponse est un bon indicateur, pas une garantie stricte du rebase que `jgit`
  fera réellement, lequel rejoue les commits un par un sur deux branches.
- **`check_rebase` ne répond pas pour les anciennes branches.** C'est volontaire :
  voir le tableau ci-dessus.
- **`util clean` ne touche pas au serveur.** Les branches de PR et les branches de
  ticket livrées restent sur GitHub : leur nettoyage se fait là-bas.
- **`verify_rebase` ne simule pas le rebase de `jgit`**, qui rejoue les commits un
  par un sur deux branches. Elle simule un rebase Git ordinaire : la réponse est un
  bon indicateur, pas une garantie stricte.
- **Elle exige un espace de travail propre**, y compris pour une simple question.

---

**Suite :** [07 — Règles communes](07-regles-communes.md)
