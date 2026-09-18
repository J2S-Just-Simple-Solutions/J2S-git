# Stratégie de test

## Pourquoi tester `jgit`

`jgit` n'est pas une bibliothèque : c'est un outil qui exécute, sur les dépôts de
l'équipe, des opérations qu'on ne rattrape pas facilement.

- `feature start` crée deux branches et pousse sur le remote ;
- `feature rebase` réécrit l'historique puis **force-push** ;
- `release finish` merge sur la branche de production, tague, **supprime** la
  branche de release en local et sur le remote, et publie une release GitHub.

Une régression ne se manifeste pas par un message d'erreur en console : elle se
manifeste par une branche perdue, un tag posé sur le mauvais commit ou une PR
ouverte vers la mauvaise base. C'est donc le **résultat sur le dépôt** qu'il faut
vérifier, pas le détail des fonctions bash.

## Ce qu'on cherche à garantir

| Garantie | Comment elle est vérifiée |
| --- | --- |
| Les bonnes branches existent, aux bons endroits (local / remote) | inspection du dépôt et du remote après chaque commande |
| Le code arrive là où il doit arriver, et **nulle part ailleurs** | contenu des fichiers branche par branche, y compris les branches qui ne doivent pas bouger |
| Les tags pointent sur le bon commit | lecture du contenu du commit tagué |
| `jgit` demande à GitHub exactement ce qu'il faut | journal des appels au client `gh`, y compris leur nombre |
| Les questions posées à l'utilisateur sont bien posées | pilotage dans un pseudo-terminal |
| Le développeur est laissé sur une branche cohérente | vérification de la branche courante en fin de commande |

## Le niveau de test retenu : bout en bout

Un seul niveau de test est utilisé : **l'exécution réelle de la commande**, vue de
l'extérieur. Pas de test unitaire des fonctions de `functions.sh`.

Raison : la valeur de `jgit` n'est pas dans ses fonctions prises isolément mais
dans l'enchaînement qu'elles produisent. Un `checkout_or_create_branch` testé
isolément ne dit rien sur le fait qu'une release finisse taguée au bon endroit.
Tester par l'extérieur permet aussi de refactoriser librement l'intérieur : les
scénarios ne connaissent que la ligne de commande, jamais les fonctions.

Conséquence assumée : les tests sont plus lents (quelques secondes par scénario)
et un échec désigne une commande, pas une ligne. Le journal d'exécution complet
est affiché en cas d'échec pour compenser.

## Le périmètre : git est réel, GitHub est simulé

```
      ce que le test exécute vraiment          ce qui est simulé
  ┌─────────────────────────────────┐   ┌──────────────────────────────┐
  │  git commit / push / merge      │   │  gh pr create                │
  │  git rebase / cherry-pick / tag │   │  gh release create           │
  │  toute la logique de jgit       │   │  la validation d'une PR       │
  └─────────────────────────────────┘   └──────────────────────────────┘
```

La frontière est nette : **tout ce qui est git s'exécute réellement**, contre un
remote local ; **tout ce qui est GitHub est simulé**, pour ne jamais polluer les
dépôts de l'organisation ni dépendre du réseau.

Deux choses distinctes sont simulées côté GitHub :

1. **Le client `gh`**, remplacé par un mock qui journalise les appels. On vérifie
   ainsi *l'intention* de `jgit` (« il a bien demandé une PR de la branche de
   travail vers la branche de PR ») sans exécuter la commande.
2. **Les actions humaines sur GitHub** — valider et merger une PR, supprimer une
   branche — rejouées explicitement par des étapes du scénario, puisqu'elles font
   partie du parcours mais ne sont pas le fait de `jgit`.

## Ce qui n'est volontairement pas couvert

- **Le contrat avec le vrai `gh`.** Si GitHub renomme une option, les tests
  passeront toujours. C'est le prix de l'absence de réseau ; ce risque se couvre
  par une exécution manuelle de temps en temps, pas par cette suite.
- **Le comportement réseau** (remote injoignable, authentification expirée).
- **Les réglages GitHub du dépôt** : la simulation suppose le mode « Squash and
  merge », qui est la convention J2S.
- **Le rendu visuel** (couleurs, mise en forme des historiques).

## État de la couverture

| Commande | Couverte |
| --- | --- |
| Analyse de la ligne de commande, aide, refus | oui — [parcours 02](02-parcours-couverts.md) |
| `feature start` / `hotfix start` (options, cas limites) | oui — [parcours 01](02-parcours-couverts.md) et [03](02-parcours-couverts.md) |
| `release start` (implicite via `release merge`) | oui |
| `release merge` | oui |
| `release finish` | oui |
| `feature restart` | oui — [parcours 04](02-parcours-couverts.md) |
| `feature rebase` (avec et sans `--squash`, avec conflit) | oui |
| `hotfix restart` / `hotfix rebase` | oui |
| `demo start / merge / list / remove` | oui |
| `util clean`, `util verify_rebase` | oui |
| Syntaxes dépréciées | oui — [parcours 10](02-parcours-couverts.md) |
| Fraîcheur des branches (retard, avance, divergence) | oui — [parcours 11](02-parcours-couverts.md) |
| Conflits (`release merge`, `release finish`, `demo merge`, rebase) | oui — parcours [05](02-parcours-couverts.md), [06](02-parcours-couverts.md) et [07](02-parcours-couverts.md) |
| Refus d'un espace de travail sale ou d'une branche non publiée (release, demo) | oui — parcours [06](02-parcours-couverts.md), [07](02-parcours-couverts.md) et [08](02-parcours-couverts.md) |
| Refus de démarrer hors macOS | oui — [parcours 12](02-parcours-couverts.md) |

## Figer un comportement discutable plutôt que l'ignorer

Certains scénarios décrivent ce que `jgit` fait aujourd'hui, en signalant que ce
n'est pas ce qu'il devrait faire — par exemple un `feature restart` sur une
feature inexistante, qui créait une branche au lieu de refuser. Ces scénarios
portent un commentaire `# ANOMALIE CONNUE` qui l'annonce.

Leur rôle n'est pas de valider le comportement mais de le rendre visible : le jour
où la commande est corrigée, le scénario échoue et rappelle qu'il faut le
réécrire. Un défaut connu et documenté vaut mieux qu'un angle mort.

La méthode a été éprouvée : les cinq anomalies figées par la première version de
la suite ont été ouvertes en issues (#34 à #38), corrigées, et leurs scénarios
inversés pour décrire le comportement attendu. Ils servent désormais de tests de
non-régression.

## Ce qui reste à couvrir

Les quatre chantiers listés ici dans les versions précédentes — `feature rebase`,
les refus, `demo`, `hotfix` — sont aujourd'hui couverts (parcours 05, 07, 09 et
les scénarios `hotfix` répartis dans 03, 04 et 05).

Restent trois angles morts identifiés, par ordre d'intérêt :

1. **La résolution interactive d'un conflit de rebase.** L'arrêt propre en
   `--no-interaction` est couvert, ainsi que la restauration après squash. Le
   chemin « le développeur résout le conflit dans un autre terminal puis répond
   oui » ne l'est pas : il suppose de commiter depuis le scénario pendant que
   `jgit` attend dans son pseudo-terminal.
2. **Le nettoyage des branches temporaires de `util verify_rebase`.** Leur nom
   contient le PID (`jgit_verify_rebase_<src>_onto_<cible>_$$`), donc un scénario
   ne peut pas le prédire. Il manque une étape du type
   `aucune branche locale ne commence par "…"` — le scénario existant porte ce
   titre mais ne vérifie aujourd'hui que ce qui l'entoure.
3. **Un conflit sur la reprise des commits de la branche `__PR__`.** Les conflits
   sont couverts sur la branche de travail, pas sur la première boucle de
   cherry-pick.

Chacun s'écrit dans un fichier `tests/features/*.feature` ; le mode d'emploi est
dans [`tests/README.md`](../tests/README.md).
