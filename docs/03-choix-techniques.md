# Choix techniques de la suite de tests

Chaque décision est présentée avec son contexte, ses conséquences et ce qui a été
écarté. L'objectif est qu'une reprise du sujet dans six mois n'ait pas à
re-débattre les mêmes points.

---

## 1. Tester `jgit` par l'extérieur, jamais fonction par fonction

**Contexte.** `jgit` est un ensemble de fonctions bash sourcées entre elles. Il
serait possible de les appeler une par une depuis un test.

**Décision.** Les tests n'appellent que la ligne de commande : `jgit feature
start TEST-123`. Aucune fonction interne n'est appelée directement.

**Conséquences.** L'intérieur peut être réorganisé sans toucher un seul scénario.
En contrepartie, un échec désigne une commande et non une ligne : le journal
complet de la commande est donc affiché à chaque échec.

**Écarté.** Tester `functions.sh` unitairement : un `checkout_or_create_branch`
correct ne dit rien sur le fait qu'une release finisse taguée au bon endroit,
c'est-à-dire sur la seule chose qui compte pour l'utilisateur.

---

## 2. Un vrai dépôt git, avec un remote local

**Contexte.** `jgit` enchaîne des opérations git réelles dont les effets se
constatent sur le graphe des commits : merge `--no-ff`, cherry-pick, force-push,
tags, suppressions de branches distantes.

**Décision.** Chaque scénario travaille sur un dépôt jetable créé à la volée, dont
le remote `origin` est un dépôt **bare local**. Les `push`, `fetch`, `merge`,
`rebase` sont réellement exécutés.

**Conséquences.** On teste git tel qu'il se comporte vraiment, y compris ses
subtilités (fast-forward, ancêtres communs, conflits) — ce qu'aucune simulation ne
reproduirait fidèlement. Coût : quelques secondes par scénario.

**Écarté.** Simuler git par des stubs : on aurait testé notre idée de git, pas git.

---

## 3. Le client `gh` est remplacé par un mock qui journalise

**Contexte.** `jgit` appelle `gh` pour créer les PR et les releases. Impossible de
laisser des tests créer de vraies PR sur les dépôts J2S.

**Décision.** Un faux `gh` est placé en tête de `PATH`. Il n'exécute rien : il
écrit la ligne de commande reçue dans un journal, et répond comme le vrai
(une URL). Les scénarios vérifient ce journal.

**Conséquences.** On vérifie **l'intention** de `jgit` (« une PR a été demandée de
cette branche vers cette base ») et le **nombre exact** d'appels, ce qui attrape
aussi les appels en trop. Aucun réseau, aucun jeton d'authentification, tests
jouables hors ligne.

**Limite assumée.** Le contrat avec le vrai `gh` n'est pas vérifié : si GitHub
renommait une option, les tests resteraient verts. Ce risque relève d'un essai
manuel occasionnel, pas de cette suite.

---

## 4. Les actions humaines sur GitHub sont rejouées explicitement

**Contexte.** Le parcours J2S comporte une étape qui n'est pas le fait de `jgit` :
un humain valide la PR sur GitHub, ce qui écrase le travail sur la branche `__PR__`
en un commit unique (« Squash and merge »).

**Décision.** Cette action est une étape à part entière du scénario :
`Quand la PR de "…" est squash-mergée sur GitHub avec le message "…"`. Elle est
réalisée par de vraies commandes git dans un clone technique, en dehors du dépôt
de travail — comme le ferait GitHub.

**Conséquences.** Le scénario raconte le parcours complet, y compris ce qui se
passe entre deux commandes `jgit`. On peut aussi tester ce qui arrive quand cette
étape **n'a pas** eu lieu (une release qui intégrerait une PR non validée).

**Limite assumée.** La simulation suppose le mode « Squash and merge », qui est la
convention J2S.

---

## 5. L'interactif est piloté dans un pseudo-terminal

**Contexte.** `jgit` pose des questions avec `read -p`. Or bash n'affiche l'invite
de `read -p` **que si l'entrée est un terminal**. Un test qui enverrait les
réponses par un tube ne verrait jamais les questions : il pourrait valider un
`jgit` qui a cessé de demander confirmation avant une action destructrice.

**Décision.** Les commandes interactives sont lancées dans un pseudo-terminal
(`tests/lib/expect.py`, basé sur le module `pty` de Python). Le scénario déclare
les questions attendues et les réponses à taper.

**Conséquences.** Trois régressions distinctes sont attrapées : une question qui
disparaît (le test échoue), une question inattendue qui apparaît (échec sur
timeout au lieu d'un blocage), et une réponse mal interprétée. C'est ce qui rend
testable la règle « un conflit de rebase n'est jamais validé automatiquement ».

**Écarté.** `expect(1)` : absent par défaut sur macOS. Envoyer les réponses via un
tube : ne montre pas les invites, donc ne prouve rien.

---

## 6. Les scénarios sont écrits en Gherkin, en français

**Contexte.** Un scénario écrit en bash mélange l'intention (« la branche de PR ne
doit pas rester en local ») et la mécanique (`git show-ref --verify --quiet …`).
Il devient illisible pour qui veut simplement savoir ce qui est garanti.

**Décision.** Les scénarios sont des fichiers `.feature` en Gherkin français ; le
bash est confiné dans les définitions d'étapes (`tests/steps/*.steps.sh`).

**Conséquences.** Un scénario se relit comme une spécification et sert de
documentation exécutable. Écrire un nouveau scénario ne demande souvent aucun
bash : les phrases existantes se recombinent. Coût : une indirection de plus entre
la phrase et le code.

---

## 7. Un moteur Gherkin maison, en bash

**Contexte.** Écrire du Gherkin suppose habituellement Cucumber (Ruby), Behave
(Python) ou cucumber-js (Node) — et des définitions d'étapes dans ce langage-là.
Or ce qu'on doit piloter est du bash, et le dépôt n'a aujourd'hui aucune
dépendance.

**Décision.** Un moteur minimal (`tests/lib/gherkin.sh`, ~250 lignes) analyse les
`.feature` et exécute les phrases contre des fonctions bash déclarées par
`step_def`.

**Conséquences.** `git clone` puis `./tests/run.sh` : rien à installer. Les
définitions d'étapes sont dans le même langage que l'outil testé. En contrepartie,
le moteur ne couvre qu'un sous-ensemble de Gherkin : `Fonctionnalité`, `Contexte`,
`Scénario`, les mots-clés d'étapes, les tableaux et les commentaires — pas les
`Plan du scénario` ni les docstrings, qui seront ajoutés le jour où un scénario en
aura besoin.

**Écarté.** cucumber-js : imposerait Node et npm à tout le monde, et surtout des
step definitions en JavaScript qui ne feraient qu'appeler du bash — une couche
d'indirection pour rien.

---

## 8. Aucune dépendance au-delà de ce qu'un Mac J2S a déjà

**Contexte.** L'outil vise des développeurs sur macOS, avec le bash 3.2 livré par
Apple.

**Décision.** Les tests n'utilisent que `bash` (compatible 3.2), `git` et
`python3` (livré avec macOS). Le lanceur exécute d'ailleurs les scénarios avec le
même interpréteur que lui-même, et `jgit.sh` via son shebang, exactement comme
l'alias `jgit` du poste de travail.

**Conséquences.** On teste dans les conditions réelles d'exécution, y compris les
limites de bash 3.2 (pas de tableaux associatifs). Le code des tests s'interdit
donc les facilités de bash 4+.

---

## 9. Un bac à sable neuf et totalement isolé par scénario

**Contexte.** Des tests qui se partagent un dépôt finissent par dépendre de leur
ordre d'exécution. Et un dépôt de test qui lirait la configuration git du poste
se comporterait différemment d'une machine à l'autre.

**Décision.** Chaque scénario obtient un répertoire temporaire neuf (dépôt de
travail, remote, clone technique « GitHub », mock `gh`) avec un `HOME` dédié et la
configuration système git neutralisée. Il est détruit à la fin, sauf avec
l'option `-k` qui le conserve pour inspection.

**Conséquences.** Les scénarios sont rejouables indéfiniment, dans n'importe quel
ordre, et un scénario en échec n'entraîne pas les suivants — chacun tourne dans
son propre sous-shell.

---

## 10. Échec immédiat, avec le contexte sous les yeux

**Décision.** Une assertion en échec interrompt le scénario et affiche son
contexte utile : les branches réellement présentes, la sortie complète de la
commande, le journal des appels à GitHub.

**Conséquences.** Pas de cascade d'échecs dérivés à démêler. En fonctionnement
nominal le lanceur reste silencieux : il n'affiche le détail que pour les
scénarios en échec, et retourne un code de sortie non nul — directement
utilisable en CI ou dans un hook.

---

## 11. L'extension Cucumber de VS Code est recommandée au niveau du dépôt

**Contexte.** VS Code n'a pas de coloration Gherkin native : sans extension, les
`.feature` s'affichent en texte brut, ce qui décourage d'écrire des scénarios.

**Décision.** Le dépôt recommande **`CucumberOpen.cucumber-official`** via
`.vscode/extensions.json` : VS Code propose son installation à l'ouverture du
projet. On peut aussi l'installer à la main :

```bash
code --install-extension CucumberOpen.cucumber-official
```

Deux détails rendent l'extension réellement confortable, et sont déjà réglés dans
`.vscode/settings.json` :

- chaque `.feature` commence par `# language: fr`, sans quoi l'extension applique
  le dialecte anglais et ne colore plus les mots-clés français ;
- l'extension souligne toute étape dont elle ne trouve pas la définition, et elle
  ne sait lire que des step definitions en JS/TS/Java/Python/Ruby… pas en bash.
  Le fichier `tests/steps/vscode_glue.py`, **généré** par
  `tests/steps/generate_vscode_glue.sh`, lui redéclare les mêmes phrases dans un
  format qu'elle comprend. Il n'est jamais exécuté par les tests.

**Conséquences.** Coloration, autocomplétion des étapes existantes et détection
des fautes de frappe dans les phrases. En contrepartie, le fichier généré doit
être régénéré après l'ajout d'une phrase — sinon la nouvelle étape est soulignée
dans l'éditeur (les tests, eux, continuent de fonctionner) :

```bash
./tests/steps/generate_vscode_glue.sh          # régénère
./tests/steps/generate_vscode_glue.sh --check  # vérifie qu'il est à jour
```

**Écarté.** Se passer d'extension (illisible), ou désactiver les avertissements :
l'extension n'offre aucun réglage pour cela.

---

## 12. La branche d'origine vit dans un trailer du commit d'init

> Décision sur l'outil, et non sur la suite de tests, consignée ici parce que
> c'est l'endroit où le projet garde ses décisions structurantes
> ([règle de codage n°1](04-regles-de-codage.md)).

**Contexte.** Plusieurs commandes ont besoin de savoir de quelle branche une
autre est partie : `util check_rebase` pour dire si l'on est à jour,
`feature rebase` pour ne pas renvoyer sur `develop` une branche partie d'ailleurs.
Or Git ne le sait pas : `git merge-base` donne le point de séparation de deux
branches, jamais laquelle a servi de point de départ. L'information n'existe
qu'au moment de la création, et se perd aussitôt.

**Décision.** L'inscrire dans le **corps du commit d'initialisation**, sous forme
de deux trailers :

```
[jgit] INIT feature/TEST-1 [empty_commit]

jgit-branch: feature/TEST-1
jgit-based-on: develop
```

Le corps du message est le seul support qui voyage avec la branche sans
configuration : il suit le clone et le `fetch`, est rejoué tel quel par les
cherry-picks du rebase, reste invisible en `--oneline` comme dans la liste des
commits de GitHub, et disparaît avec le commit d'init au squash-and-merge.

**Pourquoi deux trailers.** `jgit-branch` n'est pas un doublon du sujet : c'est
lui qui rend la lecture sûre. Les commits d'init **remontent dans les branches
livrées** — une release intègre l'historique des branches `__PR__`, puis `main`
celui de la release — si bien qu'une branche quelconque compte, dans ses
ancêtres, quantité de commits porteurs d'une origine qui n'est pas la sienne. Une
lecture qui chercherait seulement `jgit-based-on` attribuerait à une vieille
branche la trace du voisin, au lieu de la reconnaître comme ancienne. La lecture
est donc ancrée sur le nom de la branche décrite.

**Conséquence à ne pas perdre de vue.** Le message complet (`%B`) d'un commit
d'init ne vaut plus son sujet. Toute comparaison porte sur `%s` — le cas vécu
pendant l'implémentation : `release finish` comparait le `%B` du dernier commit
pour détecter une release vide, et aurait livré une release vide comme si elle
contenait quelque chose.

**Écarté.**

| Piste | Pourquoi non |
| --- | --- |
| `git notes` | ni poussées ni récupérées par défaut : l'information n'aurait existé que sur la machine qui l'a écrite |
| Un fichier dans le dépôt | pollue le projet de l'utilisateur, et entre en conflit à chaque merge |
| Une référence dédiée (`refs/jgit/…`) | pousse et récupère à la main : un clone frais ne l'aurait pas |
| Le nom de la branche | illisible, et impossible à mettre à jour après un rebase |

**Migration.** Aucune. Les branches créées avant ce mécanisme n'ont pas la trace,
et on ne la leur invente pas : `util check_rebase` refuse de répondre pour
elles, et `feature rebase` la leur donne au passage.
