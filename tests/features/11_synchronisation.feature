# language: fr
Fonctionnalité: Fraîcheur des branches
  jgit travaille toujours sur la version serveur des branches. Toute bascule
  passe par une fonction unique, qui remet la branche au niveau du remote en
  fast-forward strict.

  Trois situations, trois comportements :

  - en retard  : la branche est mise à jour, sans rien demander ;
  - en avance  : c'est le cas normal d'une branche de travail sur laquelle on
                 vient de commiter. jgit l'accepte telle quelle et ne pousse
                 jamais à la place du développeur ;
  - divergence : la commande s'arrête sans rien modifier, ni en local ni sur le
                 serveur. jgit ne choisit pas entre les deux historiques.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- en retard ------------------------------------------------------------

  Scénario: Une branche en retard est remise au niveau du serveur
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et un autre développeur pousse le fichier "src/collegue.txt" contenant "collègue" sur la branche "feature/TEST-1" avec le message "Commit du collègue"
    Quand je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "feature/TEST-1 mise à jour depuis origin/feature/TEST-1 (1 commit(s))."
    Et le fichier de travail "src/collegue.txt" contient "collègue"

  # --- en avance : ne doit jamais bloquer, ni pousser -----------------------

  Scénario: Une branche de travail en avance est acceptée telle quelle
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/wip.txt" contenant "en cours" avec le message "Travail en cours"
    Et je note l'état de la branche distante "feature/TEST-2"
    Quand je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "feature/TEST-2 a 1 commit(s) d'avance sur origin/feature/TEST-2, non poussé(s)."
    Et la branche distante "feature/TEST-2" est inchangée
    Et le dernier commit local de "feature/TEST-2" contient "Travail en cours"

  Scénario: Un rebase accepte une branche de travail non poussée
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Travail en préprod"
    Quand je lance "jgit feature rebase TEST-3 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature3.txt" existe sur la branche distante "feature/TEST-3"
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-3"

  # --- divergence : arrêt propre, aucun effet de bord -----------------------

  Scénario: Une branche de travail divergente arrête la commande
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/local.txt" contenant "local" avec le message "Mon commit"
    Et un autre développeur pousse le fichier "src/distant.txt" contenant "distant" sur la branche "feature/TEST-4" avec le message "Commit du collègue"
    Et je note l'état de la branche distante "feature/TEST-4"
    Quand je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche feature/TEST-4 a divergé de origin/feature/TEST-4."
    Et la sortie contient "jgit ne choisit pas à votre place"
    Et la branche distante "feature/TEST-4" est inchangée
    Et le dernier commit local de "feature/TEST-4" contient "Mon commit"

  Scénario: Une branche de release divergente arrête la commande
    Étant donné je lance "jgit release start"
    Et je commite le fichier "src/local.txt" contenant "local" avec le message "Mon commit sur la release"
    Et un autre développeur pousse le fichier "src/distant.txt" contenant "distant" sur la branche "release/1.1.0" avec le message "Commit du collègue"
    Et je note l'état de la branche distante "release/1.1.0"
    Quand je lance "jgit release start"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche release/1.1.0 a divergé de origin/release/1.1.0."
    Et la branche distante "release/1.1.0" est inchangée

  # --- la branche de référence est concernée au même titre ------------------

  Scénario: Une feature démarre sur la préprod du serveur, pas sur sa copie locale périmée
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "livré en préprod" sur la branche "develop" avec le message "Travail d'un collègue"
    Quand je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-5"

  Scénario: Un hotfix démarre sur la production du serveur
    Étant donné un autre développeur pousse le fichier "src/prod.txt" contenant "correctif livré" sur la branche "main" avec le message "Correctif d'un collègue"
    Quand je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et le fichier "src/prod.txt" existe sur la branche distante "hotfix/URGENT-1"

  Scénario: Une démo démarre sur la branche de référence du serveur
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "livré en préprod" sur la branche "develop" avec le message "Travail d'un collègue"
    Quand je lance "jgit demo start sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo_sprint12"
