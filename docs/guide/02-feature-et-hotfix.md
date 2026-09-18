# 02 — Feature et hotfix

> `jgit feature start` · `jgit feature restart`
> (tout fonctionne à l'identique avec `hotfix`)

---

## À quoi ça sert

Ouvrir un ticket proprement : les deux branches au bon endroit, la pull request
vers la bonne cible, sans rien avoir à retenir.

---

## `feature start` — démarrer un ticket

### Comment ça marche

```bash
jgit feature start MONPROJET-123
```

`jgit` vous annonce ce qu'il va faire et attend votre accord :

```
JGit va créer la branche feature/MONPROJET-123 et sa PR associée
qui se basera sur la branche develop
Souhaitez-vous continuer ? (Y/n)
```

Puis, dans l'ordre :

1. il récupère la dernière version de la branche de référence **depuis le
   serveur** — pas votre copie locale, qui peut dater ;
2. il crée la **branche de PR** `__PR__feature/MONPROJET-123`, y pose un commit
   repère, et la pousse ;
3. il crée votre **branche de travail** `feature/MONPROJET-123`, y pose un commit
   repère, et la pousse ;
4. il supprime la branche de PR **de votre machine** (elle reste sur le serveur) ;
5. il ouvre la **pull request** de votre branche de travail vers la branche de PR.

À la fin, vous êtes sur votre branche de travail, prêt à coder.

Les deux commits repères posés en 2 et 3 retiennent au passage **d'où part votre
branche** ([la branche d'origine](01-concepts.md#6-la-branche-dorigine)). Vous ne
le verrez nulle part dans l'historique, mais c'est ce qui permettra plus tard à
`jgit util check_rebase` de vous dire où vous en êtes, et à `jgit feature rebase`
de vous rebaser au bon endroit — y compris si vous avez utilisé `--based-on`.

### La pull request créée

| Champ | Valeur |
| --- | --- |
| Titre | l'identifiant du ticket (`MONPROJET-123`) |
| Description | le lien Jira correspondant |
| Base (cible) | `__PR__feature/MONPROJET-123` |
| Source | `feature/MONPROJET-123` |
| Étiquette | `NFR` |

### Relancer `start` sur un ticket existant

La commande est **sans danger à relancer**. Selon la situation :

| Situation | Ce que fait `jgit` |
| --- | --- |
| Les branches existent chez vous et sur le serveur | il vous place dessus et les met à jour |
| Elles existent sur le serveur mais pas chez vous | il les récupère |
| Elles n'existent que chez vous | il affiche *« Is this feature already merged ? »* et **ne fait rien** |
| Elles n'existent nulle part | il les crée (le cas nominal) |

Le troisième cas est celui d'un ticket déjà livré, dont la branche a été nettoyée
sur le serveur alors que votre copie locale est restée.

### Options

| Option | Effet |
| --- | --- |
| `--based-on <branche>` | partir d'une autre branche que la référence habituelle |
| `--no-open` | créer les branches **sans** ouvrir de pull request |
| `--no-interaction` | ne rien demander, appliquer les réponses par défaut |

---

## `feature restart` — repartir pour un second lot

### Quand l'utiliser

Votre PR vient d'être validée et mergée, mais le ticket n'est pas fini : vous avez
un second lot de travail à faire. Plutôt que d'ouvrir un nouveau ticket,
`restart` remet le compteur à zéro sur le même.

```bash
jgit feature restart MONPROJET-123
```

### Comment ça marche

1. `jgit` vérifie que votre branche de travail et la branche de PR contiennent
   **exactement le même code**. C'est la preuve que la PR a bien été validée : le
   « Squash and merge » a recopié votre travail sur la branche de PR ;
2. il supprime votre branche de travail, chez vous **et sur le serveur** ;
3. il la recrée à partir de la branche de PR, avec un nouveau commit repère ;
4. il la pousse et ouvre une nouvelle pull request, titrée
   `MONPROJET-123 - RESTART`.

Vous repartez d'une base propre — qui contient tout le travail déjà livré — sans
avoir changé de ticket.

### Options

| Option | Effet |
| --- | --- |
| `--no-open` | recréer la branche **sans** ouvrir de pull request |
| `--no-interaction` | ne rien demander |

---

## Scénarios

### Scénario 1 — Une évolution, du début à la validation

> **Camille** doit ajouter un export CSV. Le ticket est `MONPROJET-412`.

```bash
cd ~/projets/mon-projet
jgit feature start MONPROJET-412
```

Elle répond `y`. `jgit` crée les deux branches, les pousse, ouvre la PR et la
laisse sur `feature/MONPROJET-412`.

Elle code, puis travaille normalement :

```bash
git commit -m "Ajoute l'export CSV des commandes"
git push
```

Sa PR se remplit toute seule sur GitHub. Un collègue la relit, la valide, et fait
« Squash and merge ». Le travail de Camille est maintenant sur la branche de PR,
en un commit unique, prêt à partir en version.

### Scénario 2 — Un correctif urgent en production

> **Sam** doit corriger un bug qui bloque la facturation. La préprod contient une
> refonte qui n'est pas prête.

```bash
jgit hotfix start MONPROJET-500
```

`jgit` annonce : *« qui se basera sur la branche main »*. C'est le point clé — la
refonte en préprod ne suivra pas. Sam corrige, pousse, fait valider sa PR, et le
correctif part en version sans rien embarquer d'autre.

### Scénario 3 — Un second lot sur le même ticket

> La PR de Camille est mergée, mais la relecture a demandé un format de date
> différent.

```bash
jgit feature restart MONPROJET-412
```

```
✅ Les deux branches contiennent exactement le même code.
```

`jgit` recrée sa branche de travail depuis la branche de PR — elle contient déjà
le premier lot — et ouvre une PR `MONPROJET-412 - RESTART`. Camille corrige le
format, pousse, et fait revalider.

### Scénario 4 — Reprendre son ticket sur un autre poste

> **Alex** a démarré son ticket au bureau, il reprend depuis son portable.

```bash
jgit feature start MONPROJET-88
```

```
Exists in remote but not in local
Use remote branch
```

`jgit` récupère la branche depuis le serveur et l'y place. Aucune PR en double
n'est créée.

### Scénario 5 — Le collègue a commité pendant votre pause

```bash
jgit feature start MONPROJET-88
```

```
feature/MONPROJET-88 mise à jour depuis origin/feature/MONPROJET-88 (1 commit(s)).
```

Le travail du collègue est là. Si vous aviez **vous aussi** commité de votre côté
sans pousser, `jgit` s'arrêterait au lieu de choisir — voir
[07 — Règles communes](07-regles-communes.md#la-fraicheur-des-branches).

---

## Ce qui bloque

### `feature start`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Aucun identifiant de ticket | refuse : *« Please set a feature identifier »* | il n'y a pas de nom de branche à créer |
| `--based-on` sur une branche inconnue | refuse en la nommant, sans rien créer, et rappelle la référence du projet | mieux vaut refuser que partir d'un point arbitraire — c'est [le refus commun à toutes les commandes qui partent d'une branche](07-regles-communes.md#si-la-branche-de-base-nexiste-pas) |
| Aucune branche de référence trouvée | refuse : *« aucune branche de référence valide trouvée »* | le projet n'a ni `develop`, ni `master`, ni `main` : il faut configurer `jgit` |
| Vous répondez autre chose que `y` | s'arrête : *« Opération annulée »* | **rien** n'est créé, ni chez vous, ni sur le serveur |
| Votre branche a divergé du serveur | s'arrête sans rien modifier | `jgit` ne choisit pas entre deux historiques |
| GitHub refuse la création de la PR | sort en erreur | **les branches sont poussées** : il ne reste que la PR à ouvrir, le message vous le dit |
| Vous avez du travail non commité | propose de le mettre de côté et vous le rend à la fin | c'est le stash automatique ([détails](07-regles-communes.md#lespace-de-travail-doit-etre-au-propre)) |

### `feature restart`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| La branche de PR n'existe pas | refuse en la nommant | il n'y a rien à partir de quoi repartir |
| Les deux branches n'ont **pas** le même code | refuse : *« Le restart ne peut se faire que sur deux branches identiques »* | c'est le signe que la PR n'a pas été validée : repartir maintenant perdrait votre travail en cours |
| GitHub refuse la création de la PR | sort en erreur, en précisant ce qui reste à faire | idem `start` |

> **Le refus le plus fréquent est le second**, et il est protecteur : tant que la
> PR n'est pas mergée, il n'y a rien à redémarrer. Faites valider la PR d'abord.

---

## Limites connues

- **Le lien de la description de PR pointe toujours vers Jira**, construit à partir
  de l'identifiant du ticket. Si votre ticket ne vient pas de Jira, le lien ne mène
  nulle part — sans conséquence, corrigez la description sur GitHub.
- **L'étiquette `NFR` est appliquée systématiquement.** Elle n'est pas
  paramétrable.
- **`start` sur une branche qui n'existe plus que chez vous ne fait rien** et se
  termine en succès. Le message vous demande si le ticket n'a pas déjà été mergé,
  mais aucune action n'est prise.
- **Un `restart` sur une PR déjà fermée et mergée en production** ne se passe pas
  bien ([issue #27](https://github.com/J2S-Just-Simple-Solutions/J2S-git/issues/27)).
- **Un `restart` ne choisit pas de base** : il reprend celle que porte la branche
  de PR. Si celle-ci a été créée avant l'enregistrement de la branche d'origine,
  la branche recréée n'en aura pas davantage.

---

**Suite :** [03 — Rebase](03-rebase.md) ·
**Référence des règles transverses :** [07 — Règles communes](07-regles-communes.md)
