# language: fr
Fonctionnalité: Le contrat de sortie --json
  jgit est piloté par des humains, mais aussi par une IA, par l'interface en
  terminal et, à terme, par Jenkins. Avec --json, la sortie standard porte un
  seul document JSON et rien d'autre ; les messages destinés aux humains
  partent sur la sortie d'erreur. Le détail est dans docs/06-contrat-cli.md.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Une commande réussie produit un unique document de résultat
    Quand je lance "jgit feature start TEST-1 --no-open --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "schema" égal à "jgit.result/1"
    Et le JSON a "ok" vrai
    Et le JSON a "command" égal à "feature start"
    Et la branche distante "feature/TEST-1" existe

  # --json est fait pour être lu par un programme : personne n'est là pour
  # répondre. Les questions prennent leur réponse par défaut, et le disent sur
  # la sortie d'erreur.
  Scénario: --json implique --no-interaction
    Quand je lance "jgit feature start TEST-2 --no-open --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie contient "[no-interaction] Souhaitez-vous continuer ? -> y"
    Et la sortie standard est un unique document JSON

  Scénario: Une erreur d'usage produit un document d'erreur
    Quand je lance "jgit feature start --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et la sortie standard est un unique document JSON
    Et le JSON a "schema" égal à "jgit.error/1"
    Et le JSON a "ok" faux
    Et le JSON a "error.code" égal à "usage"
    Et le JSON a "error.exit_code" égal au nombre 1
    Et le JSON a "error.message" égal à "Please set a feature identifier."
    Et le JSON a "error.hint" nul

  # L'option --json est repérée avant toute autre : une erreur de syntaxe placée
  # avant elle sur la ligne produit tout de même un document.
  Scénario: Une option inconnue placée avant --json produit un document d'erreur
    Quand je lance "jgit feature start TEST-3 --inconnue --json" en lisant le JSON
    Alors jgit se termine en erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "error.code" égal à "usage"
    Et le JSON a "error.message" égal à "Option inconnue : --inconnue"

  Scénario: Un refus porte son code précis et le remède
    Étant donné je modifie le fichier "src/brouillon.txt" avec "en cours"
    Quand je lance "jgit release start --json" en lisant le JSON
    Alors jgit se termine en erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "error.code" égal à "worktree_dirty"
    Et le JSON a "error.message" égal à "Votre espace de travail contient des modifications non commitées."
    Et le JSON a "error.hint" qui contient "git stash push -u -m"
    Et la sortie contient "Mettez-les de côté puis relancez"

  # Guillemets (le remède du scénario précédent), antislash et accents ne
  # doivent jamais casser le document.
  Scénario: Les caractères spéciaux sont échappés
    Quand je lance "jgit scopé\inconnu --json" en lisant le JSON
    Alors jgit se termine en erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "error.message" égal à "Scope 'scopé\inconnu' non supporté."

  Scénario: L'aide demandée avec --json laisse un document de résultat
    Quand je lance "jgit --help --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie contient "Usage:"
    Et la sortie standard est un unique document JSON
    Et le JSON a "ok" vrai

  Scénario: En mode --json, la sortie ne contient aucune séquence de couleur
    Quand je lance "jgit feature start TEST-4 --no-open --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie ne contient aucune séquence de couleur

  # --no-fetch sert à un affichage répété (interface, tableau de bord) qui n'a
  # pas besoin d'interroger le serveur : les références déjà rapatriées font foi.
  Scénario: --no-fetch travaille sur les références déjà rapatriées
    Étant donné un autre développeur pousse le fichier "src/recent.txt" contenant "récent" sur la branche "develop" avec le message "Livraison récente"
    Quand je lance "jgit feature start TEST-5 --no-open --no-interaction --no-fetch"
    Alors jgit se termine sans erreur
    Et le fichier "src/recent.txt" n'existe pas sur la branche distante "feature/TEST-5"
    Quand je lance "jgit feature start TEST-6 --no-open --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/recent.txt" existe sur la branche distante "feature/TEST-6"
