# 06 — Utilitaires

> `jgit util clean` · `jgit util verify_rebase`

Deux commandes d'appoint, sans effet sur le serveur.

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

### Scénario 3 — Vérifier plusieurs branches d'affilée

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

- **`util clean` ne touche pas au serveur.** Les branches de PR et les branches de
  ticket livrées restent sur GitHub : leur nettoyage se fait là-bas.
- **`verify_rebase` ne simule pas le rebase de `jgit`**, qui rejoue les commits un
  par un sur deux branches. Elle simule un rebase Git ordinaire : la réponse est un
  bon indicateur, pas une garantie stricte.
- **Elle exige un espace de travail propre**, y compris pour une simple question.

---

**Suite :** [07 — Règles communes](07-regles-communes.md)
