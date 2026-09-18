# Documentation `jgit`

La documentation se lit à deux niveaux, selon que vous **utilisez** `jgit` ou que
vous **travaillez dessus**.

## Vous utilisez `jgit`

➜ **[Guide d'utilisation](guide/README.md)** — une fiche par commande : à quoi ça
sert, comment ça marche, des scénarios concrets, la liste complète des refus et
les limites connues. Lisible sans être expert Git.

| Fiche | Contenu |
| --- | --- |
| [01 — Concepts](guide/01-concepts.md) | Le vocabulaire, la paire de branches, le cycle d'un ticket |
| [02 — Feature et hotfix](guide/02-feature-et-hotfix.md) | Démarrer et relancer un ticket |
| [03 — Rebase](guide/03-rebase.md) | Rattraper la préprod sans casser sa PR, le squash |
| [04 — Release](guide/04-release.md) | Préparer, alimenter et livrer une version |
| [05 — Démo](guide/05-demo.md) | Assembler des tickets pour les montrer |
| [06 — Utilitaires](guide/06-utilitaires.md) | Nettoyage, vérification de rebase à blanc |
| [07 — Règles communes](guide/07-regles-communes.md) | Options, questions, refus, configuration |

## Vous travaillez sur `jgit`

| Document | Contenu |
| --- | --- |
| [01 — Stratégie de test](01-strategie-de-test.md) | Ce qu'on cherche à garantir, comment, et ce qui n'est volontairement pas couvert |
| [02 — Parcours couverts](02-parcours-couverts.md) | Description fonctionnelle des parcours validés par les tests, et garanties associées |
| [03 — Choix techniques](03-choix-techniques.md) | Les décisions prises pour la suite de tests, leurs raisons et leurs conséquences |
| [04 — Règles de codage](04-regles-de-codage.md) | Les règles à respecter en modifiant `jgit`, à commencer par l'alignement code / aide / doc |
| [05 — Portabilité](05-portabilite.md) | Pourquoi `jgit` refuse de tourner ailleurs que sur macOS, et ce qu'il reste à lever |

Le mode d'emploi opérationnel (lancer les tests, écrire un scénario, catalogue
des étapes) est dans [`tests/README.md`](../tests/README.md).
L'installation et la configuration sont dans le [README principal](../README.md).

## En une page

`jgit` automatise des manipulations git irréversibles sur des dépôts partagés :
création de branches, force-push après rebase, merge sur la production, tags,
suppression de branches distantes. Une régression ne se voit pas à la lecture du
code, elle se voit sur un dépôt abîmé.

La suite de tests répond à ça en jouant les commandes **pour de vrai** :

```
  scénario Gherkin                 dépôt jetable                  vérifications
  (tests/features/*.feature)   →   vrais commits, vraies      →   branches, tags,
                                   branches, vrais tags            contenu des fichiers,
                                   remote git local                appels à GitHub
```

Trois principes structurent l'ensemble :

1. **git est réel, GitHub est simulé.** Toutes les opérations git s'exécutent
   contre un remote local ; seul le client `gh` est remplacé par un mock qui
   journalise ce qu'on lui demande. Aucun test ne touche les dépôts J2S.
2. **L'interactif est testé en tant que tel.** `jgit` est piloté dans un
   pseudo-terminal : le test vérifie que chaque question est posée avant d'y
   répondre.
3. **Les scénarios se lisent sans savoir coder.** Ils sont écrits en Gherkin, en
   français ; le bash est confiné dans les définitions d'étapes.
