# 04 — Release

> `jgit release start` · `jgit release merge` · `jgit release finish`

---

## À quoi ça sert

Assembler les tickets validés dans une version, puis la livrer en production :
fusion, numéro de version, tag, publication GitHub.

---

## Le principe

Une version se construit sur une **branche dédiée**, `release/1.4.0`, créée à
partir de la production. On y intègre les tickets un par un, on vérifie, puis on
bascule le tout en production d'un seul geste.

```
  main ──────────────────────────────┬──────────────── tag 1.4.0
          │                           │
          └── release/1.4.0 ──①──②──③─┘

              ① MONPROJET-412   ② MONPROJET-500   ③ MONPROJET-88
```

**Ce qui est intégré, c'est la branche de PR** — donc le code relu et validé,
jamais votre branche de travail. C'est la garantie centrale : on ne livre que ce
qui est passé par une relecture.

Et c'est toujours la **version du serveur** de cette branche de PR qui est prise,
jamais une copie locale qui pourrait dater d'avant la validation.

---

## `release start` — ouvrir une version

```bash
jgit release start            # numéro calculé automatiquement
jgit release start 2.0.0      # numéro imposé
```

Sans argument, `jgit` lit le dernier tag du dépôt et incrémente le chiffre du
milieu : `1.3.0` → `release/1.4.0`.

Il crée la branche à partir de la **production telle qu'elle est sur le serveur**,
y pose un commit repère, et la pousse.

Si la branche de version existe déjà sur le serveur, il la reprend simplement.

> Vous n'aurez souvent pas besoin de cette commande : `release merge` ouvre la
> version toute seule si elle n'existe pas encore.

---

## `release merge` — intégrer un ticket

```bash
jgit release merge --from feature/MONPROJET-412
```

Plusieurs tickets d'un coup :

```bash
jgit release merge --from feature/MONPROJET-412 --from hotfix/MONPROJET-500
```

Dans une version précise, déjà ouverte :

```bash
jgit release merge --from feature/MONPROJET-88 --into 1.4.0
```

Ou en imposant le numéro de la version à créer :

```bash
jgit release merge 2.0.0 --from feature/MONPROJET-88
```

Pour chaque ticket, `jgit` vérifie que sa PR a bien été validée, puis fusionne la
branche de PR dans la version, avec un commit de traçabilité
`[jgit] Release merge feature branch : …`. La version est poussée à la fin.

> Vous pouvez écrire `--from feature/MONPROJET-412` ou
> `--from __PR__feature/MONPROJET-412` : les deux formes sont acceptées et
> désignent la même chose.

---

## `release finish` — livrer

```bash
jgit release finish                # termine la version courante
jgit release finish --into 1.4.0   # termine une version précise
```

`jgit` :

1. vérifie que la version n'est pas vide et que son numéro est cohérent ;
2. fusionne la branche de version dans la production ;
3. pose le tag (`1.4.0`) ;
4. pousse la production et le tag ;
5. supprime la branche de version, chez vous **et sur le serveur** ;
6. crée la **release GitHub** avec ses notes générées automatiquement.

À la fin, vous êtes sur la branche de production.

> Ces effets sont **irréversibles**. C'est la commande à lancer en sachant ce
> qu'on fait.

---

## Scénarios

### Scénario 1 — La livraison de la semaine

> **Léa** livre trois tickets validés. Le dernier tag est `1.3.0`.

```bash
jgit release merge --from feature/MONPROJET-412 \
                   --from feature/MONPROJET-88 \
                   --from hotfix/MONPROJET-500
```

`jgit` crée `release/1.4.0` à partir de la production, y intègre les trois
branches de PR, et pousse. Léa vérifie le résultat sur GitHub — la préprod, elle,
n'a pas bougé.

```bash
jgit release finish
```

```
Future tag: 1.4.0
Merging release release/1.4.0 in main branch...
Create new tag 1.4.0
```

La production contient les trois tickets, le tag est posé, la release GitHub est
publiée, la branche de version a disparu.

### Scénario 2 — Livrer en deux temps

> Léa ouvre la version lundi, mais deux tickets ne seront validés que jeudi.

```bash
# Lundi
jgit release merge --from feature/MONPROJET-412

# Jeudi, dans la même version
jgit release merge --from feature/MONPROJET-88 --into 1.4.0
jgit release finish --into 1.4.0
```

`--into` désigne explicitement la version à alimenter ou à terminer, depuis
n'importe quelle branche.

### Scénario 3 — Un ticket n'était pas validé

```bash
jgit release merge --from feature/MONPROJET-777
```

```
/!\ La branche '__PR__feature/MONPROJET-777' ne contient que le commit
d'initialisation. Merci de valider et merger la PR avant d'intégrer dans la release.
```

Le garde-fou le plus utile de `jgit` : la branche de PR est vide de code métier,
donc la PR n'a jamais été validée. Livrer maintenant aurait mis en production du
code que personne n'a relu — ou pire, rien du tout.

### Scénario 4 — Deux tickets qui se marchent dessus

```bash
jgit release merge --from feature/MONPROJET-412 --from feature/MONPROJET-500
```

```
Conflit lors de l'intégration de __PR__feature/MONPROJET-500 dans release/1.4.0.
Le merge a été annulé : la release n'a pas été poussée et rien n'est perdu.
Résolvez le conflit à la main, puis relancez jgit pour les sources restantes.
```

**Rien n'a été publié.** Léa résout le conflit à la main entre les deux tickets,
puis reprend l'intégration des suivants. Une version ne part jamais à moitié.

### Scénario 5 — Un correctif est parti directement en production

> Pendant que la version se préparait, un correctif a été poussé en production.
> La fusion conflicte.

```bash
jgit release finish
```

```
Conflit lors de la fusion de release/1.4.0 dans main.
Aucun tag n'a été posé, rien n'a été poussé et la branche de release est intacte.
```

Aucun tag, aucune release GitHub, rien en production. La branche de version est
toujours là : Léa règle le conflit puis relance.

### Scénario 6 — Léa a un commit non poussé sur la production

```bash
jgit release start
```

```
La branche main porte 1 commit(s) qui ne sont pas sur origin/main.
Une release doit partir de la version du serveur, et jgit ne décide pas à votre
place du sort de commits que vous n'avez pas publiés.

Publiez-les :
  git push origin main

…ou mettez-les de côté puis relancez :
  git switch main
  git branch sauvegarde-main
  git reset --hard origin/main
```

`jgit` ne supprime pas ce commit et ne le publie pas non plus : il s'arrête et
laisse Léa décider. Les commandes à lancer sont dans le message.

### Scénario 7 — Enchaîner deux versions

```bash
jgit release merge --from feature/A
jgit release finish          # → tag 1.4.0

jgit release merge --from feature/B
jgit release finish          # → tag 1.5.0
```

Le numéro repart automatiquement du nouveau tag.

---

## Ce qui bloque

### `release start`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Espace de travail modifié | refuse, et donne la commande pour le mettre de côté | une version se fabrique à partir d'un état connu, pas d'un dépôt en cours de modification |
| Commits non poussés sur la production | refuse, et donne les deux issues possibles | ni les écraser, ni les publier sans votre accord |
| Aucun tag dans le dépôt | refuse : *« A tag must already exists (x.x.x format) »* | il n'y a pas de numéro précédent d'où partir |
| La branche de version a divergé du serveur | s'arrête sans rien modifier | |

### `release merge`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Aucune source (`--from` absent) | refuse | |
| Branche source inconnue sur le serveur | refuse en la nommant | |
| La PR n'a pas été validée | refuse : *« ne contient que le commit d'initialisation »* | on ne livre que du code relu |
| `--into` sur une version qui n'existe pas | refuse en la nommant | |
| **Conflit pendant une fusion** | annule la fusion, **ne pousse rien**, n'essaie pas les sources suivantes | une version ne part jamais amputée |
| Espace de travail modifié | refuse | |

### `release finish`

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| La version ne contient aucun ticket | refuse : *« It seems that the release is empty… »* | |
| Commits non poussés sur la production | refuse | sans ça, la fusion les publierait en production sans votre accord |
| **Conflit à la fusion en production** | annule : **aucun tag, aucune publication**, la branche de version reste disponible | |
| Le numéro de version est plus ancien que le dernier tag | bascule sur une version recalculée | |
| GitHub refuse de créer la release | sort en erreur | **la fusion et le tag sont déjà poussés** : il ne reste que la publication GitHub, le message le dit |

---

## Limites connues

Deux défauts de numérotation sont identifiés et suivis dans
l'[issue #40](https://github.com/J2S-Just-Simple-Solutions/J2S-git/issues/40) :

- **Les versions majeures ne fonctionnent pas.** `jgit release finish` sur une
  `release/2.0.0` l'abandonne, crée une version vide à la place et s'arrête en
  erreur. En attendant le correctif, une montée en version majeure doit se faire à
  la main.
- **Le numéro de correctif n'est pas remis à zéro.** Si le dernier tag est
  `1.2.3`, la version suivante proposée est `1.3.3` au lieu de `1.3.0`. Sans effet
  tant que tous les tags se terminent par `.0`, ce qui est le cas aujourd'hui ;
  indiquez le numéro explicitement en cas de doute.

Par ailleurs :

- **`release finish` ne met pas la préprod à jour.** Après une livraison, c'est à
  vous de reporter la production dans la préprod si votre projet le demande.
- **Le calcul automatique de version ne gère que l'incrément mineur.** Pour toute
  autre montée, donnez le numéro : `jgit release start 1.4.2`.

---

**Suite :** [05 — Démo](05-demo.md)
