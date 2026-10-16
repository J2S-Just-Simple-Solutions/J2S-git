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

**Complément : Linux dans Docker.** Depuis que `jgit` doit tourner dans un
conteneur et sur un agent Jenkins, la même suite est aussi jouée sous Debian
(bash 5.2, outils GNU) par `./tests/run-in-docker.sh`. L'image de test
(`tests/docker/Dockerfile`) n'ajoute que `git` et `python3` : la règle « aucune
dépendance supplémentaire » vaut pour les deux plateformes.

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

---

## 13. Une sortie JSON en bash pur, sur un descripteur à part

**Contexte.** `jgit` doit être pilotable par une IA, par une interface en
terminal et par Jenkins. Ces programmes ont besoin d'un résultat structuré, pas
de phrases colorées. Mais le code existant écrit ses messages sur la sortie
standard, partout.

**Décision.** Avec `--json`, `jgit.sh` duplique la sortie standard sur le
descripteur 3 puis redirige la sortie standard vers la sortie d'erreur. Le code
existant n'est pas touché : ses messages partent désormais sur la sortie
d'erreur. Seul `json_emit` écrit sur le descripteur 3, une seule fois. Un
`trap EXIT` garantit qu'il y a toujours un document, même sur un `exit` imprévu.
Le JSON est fabriqué en bash pur (`json.sh`).

**Conséquences.** Une commande existante devient pilotable sans réécriture : elle
produit au minimum `jgit.result/1` ou `jgit.error/1`. Les commandes nouvelles
(démos) produisent des documents riches. En contrepartie, les erreurs doivent être
identifiées (`jgit_fail`) pour être utiles à un programme.

**Écarté.** `jq` : absent des postes, et la règle n°8 interdit toute dépendance
supplémentaire. Un mode « JSON » qui remplacerait chaque `echo` : des centaines de
lignes à toucher, pour un résultat identique.

**Piège connu.** bash 5.2 donne un sens spécial à `&` dans le remplacement de
`${s//motif/remplacement}` s'il n'est pas entre guillemets. Toutes les
substitutions de `json_str` sont protégées.

---

## 14. Un conflit peut se mettre en pause, et la publication ne force rien

**Contexte.** Le rebase gérait un conflit de deux façons : attendre que le
développeur ait résolu et commité dans un autre terminal, ou tout annuler sans
interaction. Une IA ne sait pas répondre à une question posée par un processus
qui tourne : il lui faut une commande qui s'arrête, puis une commande qui
reprend. Et la publication faisait deux `push --force` successifs.

**Décision.** Un seul moteur de rejeu (`replay.sh`), commun au rebase et aux
démos, avec trois conduites choisies par `--on-conflict` : `ask`, `abort`,
`pause`. En pause, tout ce qu'il faut pour terminer est enregistré dans
`.git/jgit/operation.state` (variables `OP_*`), le cherry-pick reste en cours,
et `continue` / `abort` repartent de cet état. La publication est un seul
`git push --atomic` avec `--force-with-lease=<ref>:<sha lu au départ>` pour
chaque branche.

**Conséquences.**
- Une seule opération en pause par dépôt ; toute autre commande refuse (code 5).
- La reprise garde la conduite choisie au départ : un rebase lancé en pause se
  remet en pause au conflit suivant.
- Un collègue qui pousse pendant un rebase n'est jamais écrasé : le push est
  refusé, les branches locales reviennent à leur état d'avant (code 4).
- `git rerere` est activé pendant le rejeu : une résolution déjà faite sur le
  poste est réappliquée dans les fichiers. Rien n'en dépend.
- Un commit qui devient vide au rejeu est conservé vide
  (`--keep-redundant-commits`) au lieu d'interrompre le rebase.

**Écarté.**
- Un verrou : `jgit` tourne sur chaque poste, un verrou local ne protège de
  personne. La seule protection partagée est celle du serveur, le lease.
- `--force-with-lease` sans valeur : il compare à la référence de suivi locale,
  qu'un `git fetch` d'arrière-plan (un IDE) met à jour en silence — la protection
  disparaît sans que personne le sache.
- `--json` impliquant `pause` : Jenkins utilise `--json` et ne doit jamais
  laisser un dépôt au milieu d'une opération.

---

## 15. Une démo est une recette écrite dans sa propre branche

**Contexte.** La première version des démos rejouait la démo par-dessus chaque
ticket ajouté (`git rebase origin/feature/X`). La base dérivait vers celle du
dernier ticket, les SHA changeaient à chaque ajout, et la détection « déjà
présent » reposait sur des SHA que `jgit feature rebase` recalcule de toute
façon. Il n'y avait pas de vue d'ensemble, pas de retrait possible.

**Décision.**
- Une démo est une base et une liste ordonnée de tickets, **écrite dans la
  branche** `demo/<nom>` : commit d'init (trailers `jgit-branch`,
  `jgit-based-on`, `jgit-demo-format: 2`), puis, pour chaque ticket, ses commits
  cherry-pickés tels quels et un **repère qui clôt le segment**
  (`[jgit] DEMO ticket <T> [empty_commit]`). Le repère ferme le segment plutôt
  que de l'ouvrir : ce qui suit le dernier repère est, sans ambiguïté, un commit
  poussé à la main.
- Un ticket est identifié par ses repères ; un commit, par son **empreinte**
  (adresse de l'auteur, date d'auteur, sujet), que le cherry-pick conserve — et
  donc aussi le rebase de `jgit`. Jamais par un SHA.
- « Livré » se lit dans les traces jgit que la release fait remonter dans la
  base : le commit d'init de la branche de PR, le merge de release.
- Toute modification passe par un plan (`init`, `pick`, `marker`) déroulé sur une
  branche temporaire par le moteur de rejeu commun (choix n°14), puis un seul
  `push --force-with-lease=<ref>:<sha lu>`. Ajouter est une avance rapide ;
  retirer, reprendre et rebaser reconstruisent **à partir de la démo
  elle-même**, ce qui rejoue les résolutions de conflit déjà faites.
- Une démo inchangée n'est jamais republiée.
- Archiver renomme la branche `demo-archive/<AAAA-MM-JJ>_<nom>` (`<AAAA-MM-JJ>.<n>_<nom>`
  pour la n-ième du jour) : le suffixe porte sur la date, jamais sur le nom, pour
  qu'un nom qui finit par `-2` reste lisible. Chaque renommage est un seul push
  `--atomic`, protégé par lease des deux côtés.
- Les démos `demo_<nom>` de la première version sont lues (marqueurs
  `[jgit] DEMO merge …`) mais ne se modifient plus : `migrate` les recrée.

**Conséquences.** La démo se lit sans autre source ; `show` sait dire, ticket par
ticket, ce qui est à jour, ce qui a avancé, ce qui a été réécrit ou livré. Une IA
ou Jenkins pilote le tout par `--json`. En contrepartie, un ticket squashé ou
réécrit à la main n'est plus reconnu commit par commit : il passe en
« réécrit », et `refresh` le reprend.

**Écarté.**
- Des commits de fusion (`merge --no-ff` de chaque ticket) : un ticket rebasé par
  `jgit` n'est plus un ancêtre de sa version précédente, et le rebase de feature
  existant procède par cherry-pick — deux mécaniques pour un même métier.
- Un fichier de recette à part (branche de métadonnées) : une seconde source de
  vérité, susceptible de diverger de la branche réelle.
- `git rerere` comme mémoire des résolutions : son cache est local au poste ;
  Jenkins et les collègues ne l'auraient pas. La résolution vit dans la démo.
- Une copie de travail séparée (`git worktree`) : la règle n°3 (un seul point de
  bascule de branche) et le rebase existant travaillent dans l'espace de travail ;
  une seule façon de faire.

---

## 16. Une interface en TypeScript et Ink, livrée dans Docker

**Contexte.** Les démos doivent être pilotables par quelqu'un qui ne retient pas
les commandes. L'équipe maîtrise TypeScript ; le bash, lui, ne sait pas faire
d'interface au clavier digne de ce nom.

**Décision.**
- Une interface en terminal en TypeScript avec Ink (React pour le terminal),
  dans `ui/`. Elle **n'a aucune logique git** : elle appelle `jgit … --json` et
  lit les documents du contrat (choix n°13). Le bash reste le moteur, et la seule
  source de vérité.
- Les réécritures passent par `--dry-run` : le plan est montré avant d'être
  appliqué. Toute modification est lancée avec `--on-conflict pause` : un
  conflit ouvre un écran dédié plutôt qu'un échec.
- Un projet a souvent des centaines de branches de tickets : on les cherche à
  la frappe plutôt qu'on ne les parcourt, et toute liste n'affiche qu'une
  fenêtre qui tient dans le terminal — un écran plus haut que le terminal, Ink
  le réimprime à chaque touche et le terminal défile au lieu de la sélection.
  Un ticket seul à correspondre est coché d'office mais ne s'ajoute qu'avec ⏎ :
  en tapant « 1234 », « 123 » peut déjà être unique.
- Ouvrir un éditeur ou Claude Code demande le terminal : l'interface se démonte,
  le lanceur (`cli.tsx`) exécute la commande, puis relance l'interface, qui
  relit `jgit util status`.
- Livraison dans Docker : image `j2s/jgit:local` (Debian, Node 22, git,
  openssh, nano, tzdata), construite par `docker-compose.yml`, lancée par
  `jgit ui` avec `docker run`. Le dépôt est monté au même chemin, le conteneur
  tourne sous l'identité de l'hôte (un point d'entrée la déclare dans
  `/etc/passwd`, sans quoi ssh refuse de démarrer), `safe.directory` est fixé par
  variables d'environnement (`GIT_CONFIG_COUNT`), le fuseau horaire du poste est
  transmis.
- Sur Mac, l'agent SSH de Docker Desktop est un socket `root:root` en
  `rw-rw----` : le conteneur reçoit le groupe root (`--group-add 0`) pour s'en
  servir sans changer d'identité. `docker compose run` ne sait pas ajouter un
  groupe : compose construit, `docker run` lance.

**Conséquences.** Rien à installer sur un poste que Docker ; la même image sert
la ligne de commande à un agent de CI. Les remotes doivent être en SSH (le
trousseau macOS n'est pas visible du conteneur). `JGIT_UI=native` lance
l'interface avec le Node du poste, sans Docker.

**Écarté.**
- Go et Bubble Tea : un binaire autonome, mais une technologie que l'équipe ne
  pratique pas.
- Une application web : un second produit à héberger et maintenir, sans gain
  pour le premier usage.
- Réécrire la logique des démos en TypeScript : deux moteurs à garder d'accord,
  et la suite Gherkin à dupliquer.

---

## 17. La vérification des mises à jour simule dans une copie de travail à part

**Contexte.** Avant de lancer les mises à jour d'une démo — ou de laisser un job
planifié le faire —, on veut savoir si elles passeront, et sinon qui est
concerné. La seule façon fiable de le savoir est de rejouer les commits.

**Décision.** `jgit demo check` rejoue, pour chaque démo, ce que feraient
`rebase`, `refresh` et `add`, dans une **copie de travail temporaire**
(`git worktree add --detach`, sous `.git/jgit/check/`), avec la même mécanique de
cherry-pick que la vraie fabrication. Un ticket qui conflicte est écarté et la
simulation reprend sans lui. Pour chaque fichier en conflit, le dernier commit
qui l'a touché du côté de la démo donne « en face » : auteur et provenance.
La copie est supprimée en sortant, quelle que soit la sortie (`jgit_on_exit`).

**Conséquences.** La vérification ne touche ni à l'espace de travail de
l'utilisateur (même modifié), ni à sa branche courante, ni au serveur ; elle
peut tourner pendant qu'une opération est en pause, pour une IA ou un job
planifié. Elle n'a pas besoin de l'identité git du poste. Les commits de
simulation n'ont de branche nulle part : git les oublie. C'est une **exception
assumée** à la règle n°3 (un seul `git checkout`) : la copie de simulation n'est
pas l'espace de travail de l'utilisateur.

**Écarté.**
- Simuler dans l'espace de travail, comme `util verify_rebase` : il faudrait un
  dépôt propre et des bascules de branche, pour une question qui ne modifie rien.
- `git merge-tree --merge-base` : sans copie de travail, mais exige git 2.40,
  absent de Debian bookworm (image Docker, agents Jenkins).
- S'arrêter au premier conflit : le rapport ne dirait pas qui d'autre est
  concerné.

