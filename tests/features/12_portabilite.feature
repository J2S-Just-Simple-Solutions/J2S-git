# language: fr
Fonctionnalité: jgit ne tourne que sur macOS
  Plusieurs commandes s'appuient sur des outils BSD dont l'équivalent GNU se
  comporte différemment. Le cas le plus grave : « feature rebase » utilise
  « tail -r », absent de GNU coreutils — la liste des commits à rejouer ressort
  vide et la branche de travail est force-pushée vidée de tout le travail, en
  annonçant « Rebase terminé avec succès ».

  Tant que ces dépendances ne sont pas levées (docs/05-portabilite.md), jgit
  refuse de démarrer ailleurs que sur macOS plutôt que de détruire du travail.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Une commande est refusée sur un système non supporté
    Étant donné le système est "Linux" et non macOS
    Quand je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "jgit ne fonctionne que sur macOS (système détecté : Linux)."
    Et la sortie contient "docs/05-portabilite.md"
    Et la branche distante "feature/TEST-1" n'existe pas
    Et la branche locale "feature/TEST-1" n'existe pas

  # C'est la commande la plus dangereuse : sans le garde-fou, elle se termine en
  # succès après avoir écrasé la branche de travail sur le serveur.
  Scénario: Le rebase est refusé avant toute réécriture d'historique
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "mon travail" avec le message "Mon travail"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-2"
    Et le système est "Linux" et non macOS
    Quand je lance "jgit feature rebase TEST-2 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "jgit ne fonctionne que sur macOS"
    Et la sortie ne contient pas "Rebase terminé avec succès"
    Et la branche distante "feature/TEST-2" est inchangée
    Et le fichier "src/travail.txt" existe sur la branche distante "feature/TEST-2"

  Scénario: Les commandes de release sont refusées elles aussi
    Étant donné le système est "Linux" et non macOS
    Quand je lance "jgit release start"
    Alors jgit se termine en erreur
    Et la sortie contient "jgit ne fonctionne que sur macOS"
    Et la branche distante "release/1.1.0" n'existe pas

  # Le diagnostic doit rester lisible : on doit pouvoir demander l'aide depuis
  # n'importe quel système pour comprendre ce que jgit attend.
  Scénario: L'aide reste accessible sur un système non supporté
    Étant donné le système est "Linux" et non macOS
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    Et la sortie contient "Usage:"

  Scénario: Le système détecté est nommé dans le message
    Étant donné le système est "FreeBSD" et non macOS
    Quand je lance "jgit util clean"
    Alors jgit se termine en erreur
    Et la sortie contient "système détecté : FreeBSD"
