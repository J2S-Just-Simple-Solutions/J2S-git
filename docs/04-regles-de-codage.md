# Règles de codage

Ce document rassemble les règles qui ne se devinent pas à la lecture du code et
dont le non-respect est passé inaperçu au moins une fois.

---

## 1. Toute modification de code réaligne la documentation dans la même passe

**La règle.** Une modification du comportement de `jgit` n'est terminée que
lorsque les trois supports disent la même chose :

1. le **code** ;
2. l'**aide en ligne** (`jgit --help`, fonction `help()` dans `jgit.sh`) ;
3. la **documentation Markdown** (`README.md` et `docs/`).

Aucun des trois n'est optionnel, et aucun ne se rattrape « plus tard ».

**Pourquoi.** La doc de `jgit` n'est pas un commentaire : c'est le contrat sur
lequel le développeur s'appuie pour décider s'il peut lancer une commande
destructrice. Une doc périmée est pire qu'une absence de doc, parce qu'on lui
fait confiance. Le cas vécu : le README promettait *« en avance (commits non
poussés) → ne touche à rien »* alors que `release start` faisait un
`git reset --hard` — la promesse elle-même invitait à perdre du travail.

**La check-list à dérouler avant d'ouvrir la PR.**

| Question | Où regarder |
| --- | --- |
| Une commande ou une option a changé ? | `help()` dans `jgit.sh` **et** la section correspondante du `README.md` |
| Un message affiché à l'utilisateur a changé ? | les scénarios qui le vérifient au mot près |
| Un comportement a changé ? | `docs/02-parcours-couverts.md`, section du parcours concerné |
| Un scénario a été ajouté ou supprimé ? | le compte et le tableau de `tests/README.md` |
| Une nouvelle étape Gherkin ? | catalogue de `tests/README.md` **et** `./tests/steps/generate_vscode_glue.sh` |
| Une décision structurante a été prise ? | `docs/03-choix-techniques.md` |

**Le garde-fou automatique.** Le scénario *« L'aide décrit exactement les
commandes et options acceptées »* (`02_ligne_de_commande.feature`) liste chaque
commande et chaque option réellement acceptée : ajouter une option sans la
documenter dans `help()` fait échouer les tests. Étendez-le à chaque nouvelle
option — c'est le seul endroit où l'oubli se voit tout seul.

---

## 2. La réponse par défaut d'une question porte toujours la majuscule

**La règle.** Toute question posée par `confirm_action` affiche son suffixe avec
la réponse par défaut **en majuscule**, quelle qu'elle soit :

```
Souhaitez-vous continuer ? (Y/n)                        ← Entrée = oui
Souhaitez-vous squasher ces commits avant le rebase ? (y/N)   ← Entrée = non
```

Il n'existe **aucune** question affichée `(y/n)`.

**Pourquoi.** L'utilisateur valide souvent sans lire. La majuscule est la seule
information qui lui dit ce que fait la touche Entrée — et donc ce que
`--no-interaction` appliquera de son côté, puisque les deux suivent la même
valeur par défaut. Une question en minuscules laisse croire qu'il n'y a pas de
défaut, alors qu'il y en a toujours un.

**En pratique.** Ne composez jamais le suffixe à la main : passez la valeur par
défaut en second argument de `confirm_action`, qui s'occupe de l'affichage.

```bash
confirm_action "Souhaitez-vous continuer ?" "y"    # → (Y/n)
confirm_action "Supprimer la branche ?"     "n"    # → (y/N)
```

Deux scénarios de `02_ligne_de_commande.feature` vérifient les deux formes.

---

## 3. Un seul point d'entrée pour changer de branche

Aucun `git checkout` ne doit exister ailleurs que dans `switch_branch`
(`functions.sh`). C'est ce qui garantit qu'on travaille toujours sur la version
du serveur — la règle transverse décrite dans le
[parcours 11](02-parcours-couverts.md#parcours-11--la-fraîcheur-des-branches).

Pour vérifier :

```bash
grep -rn "git checkout" *.sh
```

Les seules occurrences légitimes sont celles de `switch_branch` elle-même.

---

## 4. Le code de retour d'une commande git destructrice est toujours contrôlé

`merge`, `rebase`, `cherry-pick`, `push` : leur échec doit interrompre la
commande, remettre le dépôt en état (`--abort`) et le dire. Ne **jamais** laisser
une boucle continuer sur un dépôt en conflit, et ne jamais pousser après un échec.

Le cas vécu : `release merge --from A --from B` ignorait l'échec du merge de `B`,
poussait la release **amputée de B** et se terminait en succès.

---

## 5. Une fonction appelée en substitution de commande écrit ses erreurs sur stderr

```bash
reference_branch=$(get_reference_branch "$feature_type")
```

Un `echo` d'erreur dans cette fonction est capturé et devient **un nom de
branche**. Les messages partent donc sur `stderr`, et l'échec passe par le code
de retour, que l'appelant contrôle. `exit_safe` n'y sert à rien non plus : il ne
quitterait que le sous-shell.

---

## 6. Compatibilité bash 3.2 et macOS

Le bash livré par Apple est le 3.2 : pas de tableaux associatifs, pas de
`readarray`/`mapfile`, pas de `${var^^}`. Voir le
[choix technique n°8](03-choix-techniques.md).

`jgit` ne tourne par ailleurs que sur macOS, pour des raisons détaillées dans
[`05-portabilite.md`](05-portabilite.md) : avant d'introduire une dépendance à un
outil système, vérifiez qu'elle ne fige pas davantage cette situation.
