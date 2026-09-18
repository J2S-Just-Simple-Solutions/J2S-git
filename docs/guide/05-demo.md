# 05 — Démo

> `jgit demo start` · `jgit demo merge` · `jgit demo list` · `jgit demo remove`

---

## À quoi ça sert

Assembler plusieurs tickets sur une branche temporaire pour les **montrer
ensemble** — à un client, en démonstration de fin de sprint, sur un environnement
de test — avant de décider ce qui part réellement en version.

---

## Le principe

Une branche de démo s'appelle `demo_<nom>`. On y ajoute les tickets un par un,
elle se déploie sur un environnement de démonstration, on montre, puis on la
supprime.

**Une branche de démo est jetable.** Elle ne sert jamais de base à autre chose, et
on ne livre jamais depuis une démo : quand la démo est validée, on repasse par
`jgit release merge` avec les mêmes tickets.

```
  develop ───┬──────────────────────────────
             │
             └── demo_sprint12 ──①──②──③     ← on montre ça
                                              ← puis on jette

                 ① MONPROJET-412   ② MONPROJET-88   ③ MONPROJET-500
```

### Une différence importante avec la release

`jgit demo merge` **ne fusionne pas** : il rejoue la démo par-dessus le ticket,
puis republie la branche en écrasant celle du serveur. C'est ce qui garde
l'historique lisible et linéaire, mais cela signifie que **la branche de démo est
réécrite à chaque ajout**.

Conséquence pratique : ne travaillez jamais sur une branche de démo, et ne
demandez à personne de s'en servir comme point de départ.

### Autre différence : le ticket n'a pas besoin d'être validé

Contrairement à la release, qui n'intègre que du code relu, une démo prend la
**branche de travail** telle qu'elle est sur le serveur. C'est le but : on montre
ce qui est en cours, avant validation.

---

## `demo start` — créer la démo

```bash
jgit demo start sprint12          # → demo_sprint12
jgit demo start                   # → demo_develop (nom de la branche de référence)
jgit demo start recette --based-on main
```

`jgit` annonce ce qu'il va créer, demande confirmation, crée la branche à partir
de la **version serveur** de sa base, y pose un commit repère, et la pousse.

Si la démo existe déjà sur le serveur, il vous place simplement dessus et la met à
jour.

---

## `demo merge` — ajouter un ticket

```bash
jgit demo merge --from feature/MONPROJET-412
```

Plusieurs d'un coup :

```bash
jgit demo merge --from feature/MONPROJET-412 --from hotfix/MONPROJET-500
```

Depuis une autre branche, en désignant la démo :

```bash
jgit demo merge --from feature/MONPROJET-88 --into sprint12
```

Pour chaque ticket, `jgit` pose un commit repère
`[jgit] DEMO merge feature feature/MONPROJET-412`, rejoue la démo par-dessus le
ticket, et republie.

Un ticket déjà présent est détecté : rien ne bouge.

> La source doit être une **branche de travail** : `feature/<ticket>` ou
> `hotfix/<ticket>`. Pas de branche de PR, pas de nom libre.

---

## `demo list` — savoir ce qu'il y a dedans

```bash
jgit demo list
```

Lancée **depuis la branche de démo**, elle lit les commits repères et affiche :

```
Branches mergées dans demo_sprint12 :
  - MONPROJET-412 (feature/MONPROJET-412)
  - MONPROJET-500 (hotfix/MONPROJET-500)

Commandes release suggérées :
jgit release merge --from feature/MONPROJET-412
jgit release merge --from hotfix/MONPROJET-500
```

Les commandes du bas sont **copiables telles quelles** : c'est le pont entre la
démo et la livraison réelle.

---

## `demo remove` — démonter la démo

```bash
jgit demo remove
```

Lancée depuis la branche de démo, elle demande confirmation, supprime la branche
sur le serveur puis chez vous, et vous replace sur la branche de référence.

---

## Scénarios

### Scénario 1 — La démo de fin de sprint

> **Yann** prépare la démonstration du vendredi avec trois tickets en cours.

```bash
jgit demo start sprint12
jgit demo merge --from feature/MONPROJET-412 \
                --from feature/MONPROJET-88 \
                --from hotfix/MONPROJET-500
```

La branche `demo_sprint12` est déployée sur l'environnement de démonstration. Il
montre les trois sujets ensemble.

### Scénario 2 — Un ticket a avancé depuis

> Mercredi, Camille pousse deux commits de plus sur `MONPROJET-412`.

```bash
jgit demo merge --from feature/MONPROJET-412
```

La démo est rejouée par-dessus la version à jour du ticket. L'environnement de
démonstration se met à jour au prochain déploiement.

### Scénario 3 — De la démo à la livraison

> La démo est validée, tout part en version.

```bash
jgit demo list
```

Yann copie les commandes suggérées… mais ne les lance pas encore : les PR doivent
d'abord être validées. Une fois fait :

```bash
jgit release merge --from feature/MONPROJET-412 \
                   --from feature/MONPROJET-88 \
                   --from hotfix/MONPROJET-500
jgit release finish
```

**Ce qui part en version n'est pas ce qui était dans la démo**, mais le code relu
et validé des mêmes tickets. La démo ne sert qu'à décider.

### Scénario 4 — Nettoyer après la démo

```bash
jgit demo remove
```

```
Suppression de la branche de démo demo_sprint12
Elle sera retirée du remote origin et supprimée en local.
Confirmez-vous la suppression ? (Y/n)
```

Yann confirme, se retrouve sur `develop`, et la branche a disparu partout.

### Scénario 5 — Deux tickets qui se marchent dessus

```bash
jgit demo merge --from feature/MONPROJET-412
```

```
Rebase interrompu pour feature/MONPROJET-412. Résolvez les conflits puis terminez
le rebase manuellement.
Utilisez 'git rebase --continue' après résolution ou 'git rebase --abort' pour annuler.
```

Contrairement à une release, `jgit` **vous laisse la main** ici : une démo est
jetable, c'est à vous de trancher. Réglez le conflit et continuez, ou annulez et
laissez ce ticket hors de la démo.

---

## Ce qui bloque

| Situation | Ce que fait `jgit` | Pourquoi |
| --- | --- | --- |
| Espace de travail modifié | refuse, et donne la commande pour le mettre de côté | une démo se fabrique, elle ne se travaille pas |
| Commits non poussés sur la branche de base | refuse **avant** de demander confirmation | une démo part de la version du serveur |
| La démo existe chez vous mais plus sur le serveur | refuse : *« Veuillez la publier manuellement ou la supprimer »* | quelqu'un l'a supprimée sur GitHub ; `jgit` ne devine pas laquelle des deux fait foi |
| Vous refusez la confirmation de création | s'arrête : aucune branche créée | |
| Source au mauvais format | refuse : *« Le format attendu est feature/\<ticket\> ou hotfix/\<ticket\> »* | |
| Source absente du serveur | refuse en la nommant | |
| `merge`, `list` ou `remove` lancée hors d'une branche `demo_*` | refuse en nommant la branche courante | ces commandes agissent sur la démo courante |
| **Conflit pendant un ajout** | s'arrête et vous laisse la main | voir scénario 5 |
| Vous refusez la suppression | la démo est conservée, chez vous et sur le serveur | |

---

## Limites connues

- **La démo est réécrite à chaque ajout**, et republiée en écrasant la version du
  serveur. Si un collègue avait récupéré la branche, sa copie ne correspondra plus.
- **`demo list` ne fonctionne que depuis la branche de démo**, et s'appuie sur les
  commits repères : si quelqu'un les supprime en nettoyant l'historique, la liste
  devient incomplète.
- **Aucun lien automatique entre démo et release.** `demo list` vous *suggère* les
  commandes, mais rien ne vérifie que ce qui a été démontré est bien ce qui a été
  livré.
- **Une démo n'a pas de durée de vie.** Rien ne supprime les branches `demo_*`
  oubliées : pensez à `jgit demo remove` quand la démo est passée.

---

**Suite :** [06 — Utilitaires](06-utilitaires.md)
