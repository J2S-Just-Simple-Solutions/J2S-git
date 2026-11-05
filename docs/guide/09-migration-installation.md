# Mettre à jour l'installation de jgit

`Mettre-a-jour-jgit.sh` est un script autonome destiné à macOS et à Bash 3.2.
Il peut être envoyé seul aux personnes qui avaient installé jgit depuis un ZIP.
Il ne dépend pas des modules de jgit. La commande `jgit auto-update` réutilise
ce même programme en lui indiquant l’installation appelée.
Tout le programme est embarqué dans ce fichier ; aucun ZIP à décompresser.

## Comment ça marche

Enregistrez le fichier dans **Téléchargements**, ouvrez Terminal dans ce
dossier, puis exécutez ces deux lignes :

```bash
chmod +x Mettre-a-jour-jgit.sh
./Mettre-a-jour-jgit.sh
```

Vous pouvez aussi lancer `bash Mettre-a-jour-jgit.sh` sans changer les droits.
Le script se place dans votre dossier personnel, affiche
les vérifications puis demande confirmation. Le résultat reste affiché dans
le terminal après la fin du programme, sans saisie supplémentaire.

Pour les mises à jour suivantes, lancez simplement `jgit auto-update`.
La commande fonctionne hors d'un projet Git et choisit l'installation
réellement appelée, y compris via un lien symbolique. Elle ne charge pas la
configuration `.jgit/conf_local.sh` du projet courant et ne recherche pas
l'alias. Le script de mise à jour est chargé en mémoire avant l'opération,
pour pouvoir remplacer son propre fichier en cours d'exécution.

`jgit auto-update --help` décrit ses options. `--no-interaction` applique la
réponse par défaut **non** et annule donc une mise à jour nécessaire ;
`--json` implique ce mode et émet un document unique sur la sortie standard.
Le détail reste sur la sortie d'erreur. `--no-fetch` et les options des
commandes métier sont refusés. Cette commande conserve les mêmes prérequis
macOS, droits et accès au dépôt que le script autonome.

Lorsqu’il est lancé directement, le script recherche un alias `jgit` dans `.zprofile`, `.zshrc`, `.zshenv`,
`.zlogin`, `.bash_profile`, `.bashrc` et `.profile` du dossier personnel. Il
accepte un chemin absolu, `~/`, `$HOME/` ou `${HOME}/`, éventuellement précédé
de `bash` ou `sh` à l'intérieur des guillemets de l'alias. Les expressions
complexes et les chemins contenant des espaces sont refusés sans les exécuter.

Pour un ZIP, il télécharge le dépôt officiel par SSH, puis compare les contenus
à l'historique de `main`. Les règles `.gitignore` de l'installation ne peuvent
pas masquer de différences. Les droits d'exécution ne sont pas comparés.
Les éléments suivants sont exclus : `.DS_Store`, `._*`, `.AppleDouble`,
`.jgit/`, `node_modules/`, `ui/dist/`, `__pycache__/`, `*.py[cod]`,
`tests/**/tmp/`, `.idea/`, `*.swp` et `*~`. Ils restent dans la sauvegarde et
ne sont pas recopiés dans le nouveau clone ; une configuration locale utile
doit donc être reprise manuellement depuis cette sauvegarde.

Une seule confirmation présente les versions et les chemins. Entrée ou une
réponse autre que `o` ou `oui` annule. Le dossier actuel devient
`<dossier>.zip-sauvegarde-<date>` et le clone prend sa place. L'alias reste
identique. La sauvegarde complète reste disponible jusqu'à sa suppression
manuelle.

Pour un clone existant, le script exige `main`, aucun fichier suivi modifié et
une avance rapide possible. Les fichiers non suivis (`.DS_Store` du Finder,
notes personnelles…) sont laissés tels quels ; si la mise à jour devait en
écraser un, elle échoue et le clone reste sur sa version. Il récupère les nouveautés puis applique exactement le commit
présenté lors de la confirmation, sans second téléchargement. Un clone déjà
à jour n'a pas besoin de confirmation.

Après installation, `jgit help` doit répondre et le clone doit être propre.
Un échec ou un signal d'interruption déclenche une tentative de restauration.
Le script contrôle son résultat ; si elle échoue, il affiche la sauvegarde
ou le commit précédent à restaurer et conserve les fichiers temporaires utiles.

## Ce qui bloque

- Système autre que macOS, lancement avec `sudo`, Git absent ou inutilisable.
- Alias absent, ambigu, complexe, cible manquante ou installations multiples.
- Dossier système, droits insuffisants ou processus utilisant l'installation.
- Accès au dépôt impossible, ZIP modifié ou version absente de `main`.
- Clone d'un autre dépôt, branche différente de `main`, HEAD détachée,
  fichiers suivis modifiés, opération Git en cours ou commits locaux.

Si SSH échoue, le script fournit un texte d'assistance à transmettre à une IA,
et tente de le copier dans le presse-papiers. Il n'accepte aucune nouvelle clé
d'hôte et ne modifie pas la configuration SSH.

## Limites connues

Pour le script lancé directement, un lien dans le `PATH` sans alias, un
`ZDOTDIR` personnalisé et les alias définis dans d'autres fichiers ne sont
pas détectés. `jgit auto-update` n'a pas cette limite puisqu'il connaît déjà
son installation. Les liens
symboliques internes et les noms de fichiers cités par Git sont refusés lors
de la comparaison du ZIP. Le contrôle `jgit help` vérifie le démarrage ; les
dépendances optionnelles de l'interface et les commandes métier restent à
vérifier dans un projet. Une coupure de courant ou un arrêt forcé (`SIGKILL`)
ne permet pas l'exécution du retour arrière automatique.

Les vérifications peuvent créer puis retirer un clone temporaire ; pour un
clone existant, `git fetch` met à jour les références distantes avant la
confirmation. Le script exige un usage exclusif de l'installation pendant
son exécution.
