# Guide d'utilisation de `jgit`

Ce guide explique **ce que fait `jgit`, quand l'utiliser, et pourquoi il refuse
parfois d'avancer**. Il se lit sans connaître le fonctionnement interne de l'outil
et sans être expert en Git : si vous savez ce qu'est un commit, une branche et une
pull request, vous avez le niveau.

Il sert aussi de **référence** : chaque commande y est décrite avec ses règles
exactes, la liste complète de ses refus, et ses limites connues. Ce qui est écrit
ici est ce que fait l'outil — et ce qui est vérifié par sa suite de tests.

## Par où commencer

| Vous voulez… | Lisez |
| --- | --- |
| comprendre le vocabulaire et le principe général | [01 — Concepts](01-concepts.md) |
| démarrer ou reprendre un ticket | [02 — Feature et hotfix](02-feature-et-hotfix.md) |
| mettre votre branche à jour sans casser votre PR | [03 — Rebase](03-rebase.md) |
| préparer et livrer une version | [04 — Release](04-release.md) |
| montrer plusieurs sujets ensemble avant de livrer | [05 — Démo](05-demo.md) |
| faire le ménage, ou tester un rebase à blanc | [06 — Utilitaires](06-utilitaires.md) |
| comprendre les options, les refus, la configuration | [07 — Règles communes](07-regles-communes.md) |

## En trois phrases

`jgit` applique les conventions Git de J2S à votre place : il crée les branches
au bon endroit, ouvre les pull requests vers la bonne cible, prépare les versions
et pose les tags.

Il travaille **toujours sur la version du serveur** : avant d'agir, il remet à
jour la branche concernée, et il s'arrête s'il ne peut pas le faire proprement.

Il ne pousse jamais rien à votre place et ne décide jamais du sort de votre
travail : quand la situation demande un arbitrage, il **s'arrête et vous explique
quoi faire**.

## Comment lire les fiches

Chaque fiche de commande suit le même plan :

1. **À quoi ça sert** — en une phrase.
2. **Comment ça marche** — le déroulé, sans jargon.
3. **La commande** — la syntaxe et ses options.
4. **Scénarios** — des situations réelles, du début à la fin.
5. **Ce qui bloque** — le tableau complet des refus, et la raison de chacun.
6. **Limites connues** — ce que la commande ne sait pas faire aujourd'hui.

## Prérequis

- **Un Mac.** `jgit` refuse de démarrer ailleurs
  ([pourquoi](../05-portabilite.md)).
- Git, et le client GitHub `gh` installé et connecté.
- Un dépôt dont le serveur (`origin`) est sur le GitHub de J2S.

L'installation et la configuration sont décrites dans le
[README principal](../../README.md).

## Documentation technique

Ce guide s'adresse aux **utilisateurs** de `jgit`. Pour travailler **sur**
`jgit` — stratégie de test, parcours vérifiés, choix techniques, règles de
codage — voyez [`docs/`](../README.md).
