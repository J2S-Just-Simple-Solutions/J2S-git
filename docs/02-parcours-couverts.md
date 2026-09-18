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

---

## Parcours 05 — Rebaser une feature sur une référence qui a avancé

Fichier : [`tests/features/05_feature_rebase.feature`](../tests/features/05_feature_rebase.feature)

C'est la commande la plus risquée de `jgit` : elle **réécrit l'historique** de
deux branches puis les **force-push**. Le parcours vérifie autant ce qu'elle fait
que ce qu'elle refuse de faire.

### Le principe rejoué

`jgit` ne rebase pas : il reconstruit. Deux branches temporaires
`jgit_rebase_*` sont créées au-dessus de la référence remise à jour, les commits
y sont rejoués un par un en cherry-pick, et ce n'est qu'une fois l'ensemble
validé par l'utilisateur que les branches historiques sont écrasées et poussées.

```
  develop ──── (le collègue a livré) ────┬───────────────────────
                                          │
                                          ├── jgit_rebase___PR__…  (commits de la PR)
                                          │        │
                                          │        └── jgit_rebase_…  (+ commits de travail)
                                          │                  │
                                    renommage + push --force ┘
```

Conséquence directe : **tant que l'utilisateur n'a pas confirmé, le remote est
intact.** Plusieurs scénarios le vérifient explicitement.

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| Rebase nominal, `develop` a avancé | le travail du collègue arrive sur les deux branches, les commits de travail sont conservés, l'ordre est respecté |
| Après le rebase | les branches temporaires `jgit_rebase_*` et la branche `__PR__` locale ont disparu |
| `hotfix rebase` | se rebase sur `main`, pas sur `develop` |
| `--based-on` | impose la référence ; une branche inconnue est refusée sans rien toucher |
| `--squash` | les commits de travail sont regroupés en un seul, **le code est intégralement conservé** |
| `--squash` sur un seul commit | ne fait rien, et le dit |
| Au-delà de `squash_threshold` | le squash est **proposé**, et la réponse par défaut est **non** |
| En dessous du seuil | rien n'est proposé |
| Le squash proposé est accepté | le message est demandé, l'historique est réécrit, le code reste complet |
| Refus de la première confirmation | aucune des deux branches distantes ne bouge |
| Refus de la confirmation finale | rien n'est poussé, et l'historique local est rendu à son état d'origine |
| Conflit en `--no-interaction` | arrêt explicite, cherry-pick abandonné, branches temporaires supprimées, remote intact |
| Conflit après un squash | l'historique initial de la branche de travail est **restauré** |
| PR déjà mergée (plus un fast-forward) | refus explicite, avec la raison |
| Commit de fusion dans l'historique | refus explicite : un merge ne se rejoue pas en cherry-pick |
| Feature inconnue, ou paire de branches supprimée du serveur | refus, sans rien créer |

### Ce que ce parcours protège

| Régression qui serait attrapée |
| --- |
| Un `push --force` déclenché avant la confirmation de l'utilisateur |
| Un squash qui perdrait du code au lieu de ne réécrire que l'historique |
| Un conflit « validé » tout seul en `--no-interaction` — le seul cas qui exige vraiment un humain |
| Un squash appliqué sans retour en arrière possible quand le rebase échoue ensuite |
| Le squash proposé avec « oui » par défaut : valider sans lire réécrirait l'historique |
| Des branches `jgit_rebase_*` laissées derrière, qui feraient échouer le rebase suivant |

---

## Parcours 06 — Le cycle de vie d'une release

Fichier : [`tests/features/06_release.feature`](../tests/features/06_release.feature)

Trois commandes, du calcul de la version jusqu'à la publication sur GitHub.
C'est le parcours qui touche la production : chaque effet y est irréversible.

### Ce que le parcours vérifie

**`release start`**

| Situation | Comportement attendu |
| --- | --- |
| Sans argument | la version suivante est déduite du dernier tag (`1.0.0` → `release/1.1.0`) |
| La release part de `main` | ce qui n'est qu'en préprod n'y entre pas |
| Version explicite, avec ou sans préfixe `release/` | respectée telle quelle, sans double préfixe |
| Aucun tag dans le dépôt | refus explicite |
| Espace de travail sale | refus explicite, avec la commande `git stash` à lancer |
| Relancer `start` sur une release publiée | elle est reprise et remise au niveau du serveur, **jamais détruite puis recréée** |
| `main` porte des commits non poussés | **refus** : ni écrasés, ni rangés d'office ; le message donne les deux issues (publier, ou mettre de côté) |

**`release merge`**

| Situation | Comportement attendu |
| --- | --- |
| Une feature livrée | c'est la branche `__PR__` **du serveur** qui est intégrée |
| Source donnée sous la forme `__PR__…` | acceptée à l'identique |
| Plusieurs `--from` | intégrées en série, chacune avec son commit de traçabilité |
| Version cible à la volée / `--into` | la release visée est créée ou reprise |
| `--into` sans fetch préalable | les références sont rafraîchies : une PR mergée n'est pas vue comme non mergée |
| `--into` sur une release inexistante | refus explicite |
| PR non mergée (branche réduite à son commit d'init) | refus, quelle que soit la forme de la source |
| Copie locale périmée de la branche `__PR__` | ignorée : c'est le serveur qui fait foi |
| **Conflit pendant un merge** | arrêt net : le merge est annulé, **rien n'est poussé**, les sources restantes ne sont pas tentées |

**`release finish`**

| Situation | Comportement attendu |
| --- | --- |
| Nominal | merge dans `main`, tag posé, branche de release supprimée en local **et** sur le remote, release GitHub demandée |
| Enchaîner une seconde release | la version suivante repart du nouveau tag |
| `--into` | désigne explicitement la release à terminer, depuis n'importe quelle branche |
| Release vide | refus explicite |
| Release plus ancienne que le dernier tag | remplacée par la version calculée |
| `main` porte des commits non poussés | **refus** avant la fusion : sans cela le merge les publierait en production |
| **Conflit à la fusion dans `main`** | arrêt : **aucun tag**, **aucun push**, **aucune release GitHub**, et la branche de release reste disponible |
| Échec de `gh release create` | erreur explicite précisant que seul l'appel GitHub reste à rejouer |

### Ce que ce parcours protège

| Régression qui serait attrapée |
| --- |
| Une release poussée **amputée** d'une de ses sources après un conflit ignoré |
| Un tag posé alors que la fusion dans la production a échoué |
| Des commits non poussés de la production **écrasés** au démarrage d'une release |
| Des commits non poussés de la production **publiés** par le merge de `release finish` |
| Une release construite depuis la branche de travail, ou depuis une copie locale périmée |
| Une PR non validée intégrée à une livraison |
| Une branche de release oubliée sur le remote après `finish` |
| Un échec côté GitHub passé sous silence |

---

## Parcours 07 — Les branches de démonstration

Fichier : [`tests/features/07_demo.feature`](../tests/features/07_demo.feature)

Une branche `demo_*` sert à **montrer** plusieurs features ensemble avant de les
livrer. Elle est jetable : contrairement à une release, son historique est
réécrit à chaque ajout.

> `demo merge` porte le nom de « merge » mais procède par **rebase de la branche
> de démo sur la source**, suivi d'un `push --force-with-lease`. C'est ce qui
> garde l'historique linéaire ; c'est aussi pourquoi une démo ne doit jamais
> servir de base à autre chose qu'une démonstration.

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| Espace de travail sale | refus explicite : une démo se fabrique, elle ne se travaille pas |
| Branche de base porteuse de commits non poussés | refus, **avant** la demande de confirmation |
| `demo start` sans nom | la démo prend le nom de la branche de référence (`demo_develop`) |
| `demo start <nom>` / `--based-on` | nom et base imposés, ce qui n'est pas dans la base n'y entre pas |
| Relancer `start` sur une démo publiée | elle est simplement remise à jour |
| Démo présente en local mais supprimée du serveur | refus, avec la marche à suivre |
| Confirmation refusée | aucune branche, ni locale ni distante |
| `demo merge` | la feature arrive dans la démo, avec son commit marqueur `[jgit] DEMO merge …` |
| Plusieurs `--from`, `feature` et `hotfix` mélangés | intégrées en série |
| `--into` | désigne la démo à alimenter depuis n'importe quelle branche |
| Intégrer deux fois la même feature | détecté, la branche distante ne bouge pas |
| Source au mauvais format, ou absente du serveur | refus, la démo ne bouge pas |
| `merge`, `list`, `remove` hors d'une branche `demo_*` | refus explicite |
| **Conflit pendant l'intégration** | la main est rendue au développeur : le rebase reste en cours, rien n'est poussé |
| `demo list` | affiche le **nom complet** des branches intégrées et les commandes `release merge` correspondantes |
| Démo vide | signalée comme telle |
| `demo remove` | supprimée du remote puis du local, retour sur la branche de référence |
| Refus de la suppression / démo déjà supprimée sur GitHub | respectivement conservée, et nettoyée en local |

### Ce que ce parcours protège

Le point historiquement fragile est `demo list` : le nom des branches était
tronqué (issue #37), rendant inutilisables les commandes `release merge`
suggérées — c'est-à-dire la seule raison d'être de la commande. Le scénario
vérifie désormais le nom complet.

Le second est le **traitement des conflits** : contrairement aux commandes de
release, `demo merge` laisse délibérément le rebase en cours. Le scénario fige ce
choix pour qu'il reste un choix, et non un oubli.

---

## Parcours 08 — Les utilitaires et le stash automatique

Fichier : [`tests/features/08_util_et_stash.feature`](../tests/features/08_util_et_stash.feature)

Deux sujets sans rapport fonctionnel, mais qui partagent une propriété : ils ne
doivent **rien** laisser derrière eux.

### `util clean`

Supprime les branches locales purement techniques — `jgit_rebase_*`,
`jgit_verify_rebase_*`, `__PR__*` — et **uniquement** celles-là. Le scénario place
côte à côte de vraies branches de travail et des branches techniques, puis vérifie
que `develop`, `main` et `feature/…` survivent.

### `util verify_rebase`

Répond `true` ou `false` à la question « ce rebase passera-t-il ? », **sans rien
modifier**, ni en local ni sur le remote.

| Situation | Comportement attendu |
| --- | --- |
| `--into` ou `--from` manquant, deux `--from` | refus explicite, et `false` |
| Branche source ou cible inconnue | refus explicite, et `false` |
| Espace de travail sale | refus, et les modifications sont intactes |
| Une branche comparée à elle-même | `true` |
| Rebase possible | `true`, la branche distante est inchangée, l'espace de travail est propre |
| Rebase conflictuel | `false`, **et l'historique local de la branche source est intact** |

C'est cette dernière ligne qui compte : la vérification travaille sur une copie
temporaire, jamais sur la branche du développeur.

### Le stash automatique

| Situation | Comportement attendu |
| --- | --- |
| Travail non commité avant une commande `feature` ou `hotfix` | `jgit` propose de le mettre de côté, et le **restaure** à la fin |
| L'utilisateur refuse | la commande s'arrête, rien n'est créé, rien n'est envoyé à GitHub, les modifications sont intactes |
| Commandes `release` et `demo` | **refus** au lieu du stash : elles fabriquent à partir d'un état connu du serveur, ranger le travail à la place du développeur serait une décision qui ne leur revient pas |
| `util clean` | ne déclenche ni stash ni refus : elle ne touche pas à l'arbre de travail |

---

## Parcours 09 — Des journées de travail complètes

Fichier : [`tests/features/09_parcours_complets.feature`](../tests/features/09_parcours_complets.feature)

Les autres parcours testent des commandes ; celui-ci teste leur **enchaînement**.
Quatre journées types, jouées d'un bout à l'autre :

1. **Un hotfix part de la production et y revient.** Démarré depuis `main` alors
   que `develop` a du travail en cours, il ne l'embarque pas — ni dans la branche,
   ni dans la release, ni dans le tag.
2. **Une feature est rebasée, redémarrée puis livrée.** `start` → commits →
   `rebase` sur une préprod qui a bougé → squash-merge de la PR → `restart` →
   second lot → livraison. Les deux lots se retrouvent dans le tag final.
3. **Une démo sert de répétition avant la release.** Deux features montrées sur
   une branche de démo, listées, puis livrées pour de vrai, puis la démo est
   démontée.
4. **Deux releases successives s'enchaînent.** Les deux tags existent, le contenu
   de la première est bien présent dans la seconde, et rien n'a fui vers `develop`.

### Ce que ce parcours protège

Les régressions qui n'apparaissent qu'à la jointure entre deux commandes : un
`restart` qui casserait le `rebase` précédent, une seconde release qui repartirait
du mauvais tag, un hotfix qui remonterait de la préprod en production.

---

## Parcours 10 — Les syntaxes dépréciées

Fichier : [`tests/features/10_syntaxes_depreciees.feature`](../tests/features/10_syntaxes_depreciees.feature)

Deux commandes ont changé de forme. Les anciennes restent acceptées le temps que
les habitudes et les scripts de chacun rattrapent.

| Ancienne forme | Forme actuelle |
| --- | --- |
| `jgit release merge <branche>` | `jgit release merge --from <branche>` |
| `jgit clean` | `jgit util clean` |

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| Ancienne forme | fonctionne **à l'identique**, et affiche l'avertissement de dépréciation |
| Ancienne forme avec un nom déjà préfixé `__PR__`, ou un `hotfix` | fonctionne aussi |
| Nouvelle forme | **aucun** avertissement |
| `release merge 4.2.0` ou `release/5.1.0` | reste une **version cible**, pas une source |
| Sans source ni version | l'erreur est celle de la nouvelle syntaxe, sans avertissement parasite |
| Mélanger les deux formes | refus explicite, qui nomme la bonne option à utiliser |
| L'aide | documente les deux formes dépréciées |

### Ce que ce parcours protège

La distinction repose sur le **format de l'argument** : `1.2.0` est une version,
tout le reste est une branche source. Une régression sur cette règle ferait
silencieusement passer une version pour une branche — ou l'inverse. Le parcours
la vérifie dans les deux sens, et vérifie surtout que l'ancienne forme continue de
produire **exactement** le même résultat que la nouvelle.

---

## Parcours 11 — La fraîcheur des branches

Fichier : [`tests/features/11_synchronisation.feature`](../tests/features/11_synchronisation.feature)

Ce parcours ne valide pas une commande mais une **règle transversale** : toute
bascule de branche, quelle qu'en soit la raison, passe par une fonction unique
qui remet la branche au niveau du serveur en fast-forward strict.

La règle tient en une phrase : *on travaille sur la version du serveur, sauf
quand on a du travail local en cours — et dans ce cas jgit ne pousse rien à
votre place.*

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| Branche en retard | mise à jour silencieuse, le travail du collègue est là |
| Branche **en avance** (commits non poussés) | acceptée telle quelle ; `jgit` le signale, **ne pousse pas**, et la branche distante est inchangée |
| Rebase d'une branche non poussée | fonctionne : l'avance locale est le cas normal, pas une anomalie |
| Branche de travail **divergente** | arrêt ; ni le remote ni l'historique local ne bougent |
| Branche de **release** divergente | arrêt ; la release distante est inchangée |
| `feature start` avec une préprod locale périmée | la feature part de `develop` **du serveur** |
| `hotfix start` avec une prod locale périmée | le hotfix part de `main` **du serveur** |
| `demo start` avec une référence périmée | la démo part de la version du serveur |

### Ce que ce parcours protège

Le cas le plus coûteux est celui des deux derniers scénarios de départ : avant,
`jgit feature start` faisait bien un `git fetch`, mais basculait ensuite sur la
branche de référence **locale**, qui pouvait avoir des semaines de retard. Une
feature démarrait alors sur une base périmée, sans le moindre avertissement — et
pour un `hotfix`, cela voulait dire partir d'une production qui n'était plus la
production.

Le second acquis est la distinction entre **avance** et **divergence**. Il serait
facile de « sécuriser » jgit en refusant toute branche qui n'est pas strictement
identique au serveur : ce serait inutilisable, puisqu'une branche de travail est
en avance la moitié du temps. Trois scénarios vérifient que l'avance passe, et
que rien n'est poussé au passage.

| Régression qui serait attrapée |
| --- |
| Une branche de référence utilisée dans sa version locale périmée |
| Un `git pull` sans `--ff-only` réintroduit : commit de fusion silencieux, ou dépôt laissé en conflit |
| Un code de retour de synchronisation à nouveau ignoré : la commande continue sur des données périmées |
| Un `push` ajouté « pour aligner » la branche : jgit publierait du travail que le développeur n'a pas choisi de publier |
| Une divergence traitée comme un cas normal |

---

## Parcours 12 — Le refus de tourner ailleurs que sur macOS

Fichier : [`tests/features/12_portabilite.feature`](../tests/features/12_portabilite.feature)

`jgit` s'appuie sur des outils BSD dont l'équivalent GNU se comporte
différemment. Le cas le plus grave : `feature rebase` construit sa liste de
commits avec `tail -r`, qui n'existe pas dans GNU coreutils. Ailleurs que sur
macOS, la liste ressort **vide**, le rebase ne rejoue rien, et la branche de
travail est **force-pushée vidée de tout le travail** — en affichant « Rebase
terminé avec succès ».

Plutôt que de risquer cela, `jgit` refuse de démarrer. Le détail et l'inventaire
de ce qu'il reste à lever sont dans [`05-portabilite.md`](05-portabilite.md).

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| N'importe quelle commande sur un système non supporté | refus explicite, nommant le système détecté et renvoyant à la doc |
| `feature rebase` en particulier | refus **avant** toute réécriture : la branche distante est inchangée, le travail est toujours là |
| Les commandes de release | refusées au même titre |
| `jgit --help` | reste accessible : on doit pouvoir comprendre le refus |

### Comment c'est testé sans machine Linux

Le bac à sable place `$SANDBOX/bin` en tête du `PATH`. L'étape
`Étant donné le système est "…" et non macOS` y dépose un faux `uname` : `jgit`
croit tourner ailleurs, sans conteneur ni runner distant.

---

## Parcours 13 — La branche d'origine et la fraîcheur

Fichier : [`tests/features/13_branche_origine.feature`](../tests/features/13_branche_origine.feature)

Une branche ne dit pas d'où elle vient : Git sait retrouver l'endroit où deux
branches se séparent, jamais **laquelle a servi de point de départ**. `jgit`
inscrit donc le point de départ dans le corps du commit d'initialisation, sous
forme de trailers, et s'en sert pour répondre à « suis-je encore à jour, et
puis-je rebaser sans conflit ? ».

### Ce que le parcours vérifie

| Situation | Comportement attendu |
| --- | --- |
| `feature start` / `hotfix start` | la branche de travail **et** sa branche de PR enregistrent la référence utilisée |
| `--based-on` | c'est cette branche-là qui est enregistrée, pas la référence du projet |
| `demo start`, `release start` | enregistrent également leur base |
| `feature restart` | reprend la base portée par la branche de PR, sans la recalculer |
| L'affichage de l'historique | les trailers restent dans le corps du message : aucun sujet de commit ne les montre |

### La fraîcheur, vue par `util check_rebase`

| Situation | Réponse et code de sortie |
| --- | --- |
| Branche fraîchement créée | *à jour*, code `0` |
| Base qui a avancé, rebase propre | *en retard de N commits*, *passerait sans conflit*, code `2`, et la commande à lancer |
| Base qui a avancé, rebase en conflit | *des conflits sont à prévoir*, code `3`, et le rappel de `--squash` |
| Espace de travail sale, branche inconnue, `--from` en double, branche en positionnel | refus expliqué, code `1` |
| Après la vérification | rien n'a bougé : branches distantes inchangées, développeur laissé sur sa branche |

### Les anciennes branches

C'est le cœur du parcours. Une branche créée avant ce mécanisme — ou à la main —
ne porte aucune trace de son point de départ, et `jgit` **refuse de répondre**
plutôt que de supposer la préprod.

Un scénario va plus loin et protège contre l'erreur qui rendrait ce refus
inopérant : les commits d'initialisation **remontent dans les branches livrées**
(une release intègre l'historique des branches `__PR__`, puis `main` celui de la
release). Une vieille branche partant de `main` compte donc, dans ses ancêtres,
quantité de commits porteurs d'une origine qui n'est pas la sienne. Le scénario
joue une livraison complète avant de créer la branche à la main, et vérifie
qu'elle est bien reconnue comme ancienne — c'est ce que garantit le trailer
`jgit-branch`, qui nomme la branche que chaque trace décrit.

### Le rebase et la base enregistrée

| Situation | Comportement attendu |
| --- | --- |
| Base enregistrée différente de la référence du projet | `jgit` le signale et propose la base enregistrée, qui est la réponse par défaut |
| Réponse `n` | le rebase vise la référence du projet, et la trace est mise à jour en conséquence |
| `--no-interaction` | applique la réponse par défaut : la base enregistrée |
| `--based-on` explicite | fait autorité, aucune question n'est posée, la trace est mise à jour |
| Branche sans trace | rebase sur la référence du projet, et **acquiert sa trace** au passage |

### Quand la base n'existe pas, d'où qu'elle vienne

La branche de base vient de l'une de trois sources : la saisie `--based-on`, la
base enregistrée, ou le calcul automatique. Les trois peuvent désigner une
branche disparue, et les trois doivent donner **le même refus**.

| Situation | Comportement attendu |
| --- | --- |
| `--based-on` mal orthographié (`feature start`, `feature rebase`, `demo start`) | refus nommant la branche, la provenance, le remède et la référence du projet |
| Base enregistrée disparue (une démo supprimée après la démo) | **le même refus**, seule la ligne de provenance change |
| Refus pendant un `rebase` | rien n'a bougé : branches distantes inchangées, branche de travail intacte, aucune branche `jgit_rebase_*` laissée |
| Relance avec `--based-on <branche vivante>` | le rebase aboutit et la trace est mise à jour |
| `hotfix` | même refus, en nommant `hotfix` et la production comme référence |

Le scénario le plus important du lot enchaîne les deux provenances sur la même
branche et vérifie que les phrases sont identiques : c'est ce qui empêche
qu'un cas particulier se remette à parler sa propre langue.

| Régression qui serait attrapée |
| --- |
| Une comparaison de message de commit faite sur `%B` plutôt que sur `%s` : le trailer la ferait échouer, et une release vide passerait pour pleine |
| Un rebase qui se rabat en silence sur `develop` quand la base enregistrée a disparu, déplaçant la branche puis la poussant en force |
| Une valeur par défaut utilisée sans le contrôle appliqué à la saisie |
| Un message de refus propre à une commande, là où le problème est le même partout |
| Le trailer remonté dans le sujet du commit, donc visible partout |
| Une ancienne branche à qui l'on attribue la trace d'un ancêtre au lieu de la reconnaître comme ancienne |
| Un rebase qui laisse la trace d'avant : la branche prétendrait partir d'une base qui n'est plus la sienne |
| `feature rebase` qui renvoie silencieusement sur `develop` une branche partie d'ailleurs |
