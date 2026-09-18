# language: fr
Fonctionnalité: Analyse de la ligne de commande
  jgit doit guider l'utilisateur : afficher l'aide quand rien n'est demandé et
  refuser clairement toute commande mal formée, sans jamais toucher au dépôt.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Sans argument, jgit affiche son aide
    Quand je lance "jgit"
    Alors jgit se termine sans erreur
    Et la sortie contient "Usage:"
    Et la sortie contient "Scopes:"
    Et GitHub a reçu exactement 0 appels

  Scénario: L'aide est accessible par -h, --help et le scope help
    Quand je lance "jgit -h"
    Alors jgit se termine sans erreur
    Et la sortie contient "jgit feature start <ticket>"
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    Et la sortie contient "jgit release start [<x.y.z>]"
    Quand je lance "jgit help"
    Alors jgit se termine sans erreur
    Et la sortie contient "jgit util verify_rebase --from <branche_source> --into <branche_cible>"

  # L'aide se désynchronise du code sans que rien ne le signale. Ce scénario
  # liste chaque commande et chaque option réellement acceptée : ajouter une
  # option sans documenter son usage fait échouer le test.
  Scénario: L'aide décrit exactement les commandes et options acceptées
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    # Options globales
    Et la sortie contient "--based-on <branch>"
    Et la sortie contient "--from <branch>"
    Et la sortie contient "--into <branch>"
    Et la sortie contient "--no-interaction"
    Et la sortie contient "--no-open"
    Et la sortie contient "--squash"
    # Feature & hotfix : chaque action avec les options qu'elle lit vraiment
    Et la sortie contient "jgit feature start <ticket> [--based-on <branch>] [--no-open]"
    Et la sortie contient "jgit feature restart <ticket> [--no-open]"
    Et la sortie contient "jgit feature rebase <ticket> [--based-on <branch>] [--squash]"
    # Release : finish accepte --into, au même titre que merge
    Et la sortie contient "jgit release start [<x.y.z>]"
    Et la sortie contient "jgit release merge [<x.y.z>] --from <branch> [--into <branch>]"
    Et la sortie contient "jgit release finish [--into <x.y.z>]"
    # Demo
    Et la sortie contient "jgit demo start [<demo_name>] [--based-on <branch>]"
    Et la sortie contient "jgit demo merge [--from feature/<ticket>]... [--into <branch>]"
    Et la sortie contient "jgit demo list"
    Et la sortie contient "jgit demo remove [--no-interaction]"
    # Util
    Et la sortie contient "jgit util clean"
    Et la sortie contient "jgit util verify_rebase --from <branche_source> --into <branche_cible>"
    # L'aide doit dire ce que util clean supprime réellement, y compris les
    # branches laissées par util verify_rebase.
    Et la sortie contient "jgit_rebase_*, jgit_verify_rebase_* et __PR__*"

  # RÈGLE : la réponse appliquée quand on valide sans rien saisir est toujours
  # signalée par la majuscule. Une question dont les deux lettres sont en
  # minuscules ne dit pas ce que fait la touche Entrée.
  Scénario: Chaque question signale sa réponse par défaut en majuscule
    Quand je lance "jgit feature start TEST-20" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Souhaitez-vous continuer ? (Y/n)"

  Scénario: Une question dont le défaut est non porte la majuscule sur le non
    Étant donné je lance "jgit feature start TEST-21 --no-interaction --no-open"
    Et je commite le fichier "src/t1.txt" contenant "1" avec le message "Commit numéro 1"
    Et je commite le fichier "src/t2.txt" contenant "2" avec le message "Commit numéro 2"
    Et je commite le fichier "src/t3.txt" contenant "3" avec le message "Commit numéro 3"
    Et je commite le fichier "src/t4.txt" contenant "4" avec le message "Commit numéro 4"
    Et je commite le fichier "src/t5.txt" contenant "5" avec le message "Commit numéro 5"
    Et je commite le fichier "src/t6.txt" contenant "6" avec le message "Commit numéro 6"
    Et je commite le fichier "src/t7.txt" contenant "7" avec le message "Commit numéro 7"
    Et je commite le fichier "src/t8.txt" contenant "8" avec le message "Commit numéro 8"
    Et je commite le fichier "src/t9.txt" contenant "9" avec le message "Commit numéro 9"
    Et je pousse la branche courante
    Quand je lance "jgit feature rebase TEST-21" et que je réponds aux questions :
      | Souhaitez-vous squasher ces commits | n |
      | Souhaitez-vous continuer            | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Souhaitez-vous squasher ces commits avant le rebase ? (y/N)"
    Et la sortie contient "Souhaitez-vous continuer ? (Y/n)"

  Scénario: Un scope inconnu est refusé
    Quand je lance "jgit bidule"
    Alors jgit se termine en erreur
    Et la sortie contient "Scope 'bidule' non supporté."

  Scénario: Une action inconnue est refusée pour chaque scope
    Quand je lance "jgit feature bidule TEST-1"
    Alors jgit se termine en erreur
    Et la sortie contient "Action 'bidule' non supportée pour feature."
    Quand je lance "jgit hotfix bidule TEST-1"
    Alors jgit se termine en erreur
    Et la sortie contient "Action 'bidule' non supportée pour hotfix."
    Quand je lance "jgit release bidule"
    Alors jgit se termine en erreur
    Et la sortie contient "Action 'bidule' non supportée pour release."
    Quand je lance "jgit demo bidule"
    Alors jgit se termine en erreur
    Et la sortie contient "Action 'bidule' non supportée pour demo."
    Quand je lance "jgit util bidule"
    Alors jgit se termine en erreur
    Et la sortie contient "Action 'bidule' non supportée pour util."

  Scénario: Un scope sans action affiche l'aide et sort en erreur
    Quand je lance "jgit feature"
    Alors jgit se termine en erreur
    Et la sortie contient "Usage:"
    Quand je lance "jgit release"
    Alors jgit se termine en erreur
    Et la sortie contient "Usage:"
    Quand je lance "jgit demo"
    Alors jgit se termine en erreur
    Et la sortie contient "Usage:"
    Quand je lance "jgit hotfix"
    Alors jgit se termine en erreur
    Et la sortie contient "Usage:"
    Quand je lance "jgit util"
    Alors jgit se termine en erreur
    Et la sortie contient "Usage:"
    Et la sortie ne contient pas "Action '' non supportée"

  Scénario: Une feature ou un hotfix sans identifiant est refusé
    Quand je lance "jgit feature start"
    Alors jgit se termine en erreur
    Et la sortie contient "Please set a feature identifier."
    Quand je lance "jgit feature restart"
    Alors jgit se termine en erreur
    Et la sortie contient "Please set a feature identifier."
    Quand je lance "jgit feature rebase"
    Alors jgit se termine en erreur
    Et la sortie contient "Please set a feature identifier."
    Quand je lance "jgit hotfix start"
    Alors jgit se termine en erreur
    Et la sortie contient "Please set a hotfix identifier."
    Et la branche distante "feature/" n'existe pas

  Scénario: Une option attendant une valeur la réclame
    Quand je lance "jgit feature start TEST-1 --based-on"
    Alors jgit se termine en erreur
    Et la sortie contient "l'option --based-on requiert une valeur."
    Quand je lance "jgit release merge --from"
    Alors jgit se termine en erreur
    Et la sortie contient "l'option --from requiert une valeur."
    Quand je lance "jgit release merge --from feature/X --into"
    Alors jgit se termine en erreur
    Et la sortie contient "l'option --into requiert une valeur."

  Scénario: Une option suivie d'une autre option est refusée
    Quand je lance "jgit feature start TEST-1 --based-on --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "l'option --based-on requiert une valeur."
    Et la branche distante "feature/TEST-1" n'existe pas

  Scénario: Une option inconnue est refusée
    Quand je lance "jgit feature start TEST-1 --bidule"
    Alors jgit se termine en erreur
    Et la sortie contient "Option inconnue : --bidule"
    Et la branche distante "feature/TEST-1" n'existe pas

  Scénario: Les arguments positionnels superflus sont refusés
    Quand je lance "jgit feature start TEST-1 en-trop"
    Alors jgit se termine en erreur
    Et la sortie contient "Arguments supplémentaires non reconnus : en-trop"
    Et la branche distante "feature/TEST-1" n'existe pas

  Scénario: Un merge sans source est refusé
    Quand je lance "jgit release merge"
    Alors jgit se termine en erreur
    Et la sortie contient "Veuillez spécifier au moins une source avec --from."
    Quand je lance "jgit demo merge"
    Alors jgit se termine en erreur
    Et la sortie contient "Veuillez préciser au moins une source avec --from."

  Scénario: jgit refuse de travailler sans le remote J2S
    Étant donné le dépôt n'a plus de remote
    Quand je lance "jgit util clean"
    Alors jgit se termine en erreur
    Et la sortie contient "Please configure J2S remote as origin"

  Scénario: L'aide reste accessible même sans remote configuré
    Étant donné le dépôt n'a plus de remote
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    Et la sortie contient "Usage:"

  Scénario: Après --, tout est traité comme un argument positionnel
    Quand je lance "jgit -- feature start TEST-1 --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "Arguments supplémentaires non reconnus : --no-open"
    Et la branche distante "feature/TEST-1" n'existe pas
