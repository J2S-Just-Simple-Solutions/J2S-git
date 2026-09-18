# language: fr
Fonctionnalité: Utilitaires et garde-fous transverses
  « util clean » efface les branches techniques laissées par jgit,
  « util verify_rebase » répond true/false à la question « ce rebase
  passera-t-il ? » sans rien modifier, et le stash automatique protège le
  travail non commité avant toute manipulation de branches.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- util clean -----------------------------------------------------------

  Scénario: Sans branche technique, le nettoyage ne fait rien
    Quand je lance "jgit util clean"
    Alors jgit se termine sans erreur
    Et la sortie contient "Aucune branche locale à nettoyer"

  # feature/TEST-1 et __PR__feature/TEST-1 sont de vraies branches jgit. Les
  # deux autres sont des branches temporaires, qu'un rebase interrompu laisse
  # derrière lui : seul leur nom compte pour un nettoyage par motif.
  Scénario: Les branches techniques sont supprimées, les autres conservées
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je récupère la branche distante "__PR__feature/TEST-1" en local
    Et je crée la branche locale "jgit_rebase_feature/TEST-1"
    Et je crée la branche locale "jgit_verify_rebase_a_onto_b"
    Quand je lance "jgit util clean"
    Alors jgit se termine sans erreur
    Et la sortie contient "Suppression des branches locales suivantes :"
    Et la sortie contient "Suppression terminée."
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas
    Et la branche locale "__PR__feature/TEST-1" n'existe pas
    Et la branche locale "jgit_verify_rebase_a_onto_b" n'existe pas
    Et la branche locale "feature/TEST-1" existe
    Et la branche locale "develop" existe
    Et la branche locale "main" existe

  # --- util verify_rebase ---------------------------------------------------

  Scénario: Sans branche cible, la vérification est refusée
    Quand je lance "jgit util verify_rebase --from develop"
    Alors jgit se termine en erreur
    Et la sortie contient "veuillez préciser la branche cible avec --into."
    Et la sortie contient "false"

  Scénario: Sans branche source, la vérification est refusée
    Quand je lance "jgit util verify_rebase --into main"
    Alors jgit se termine en erreur
    Et la sortie contient "veuillez fournir exactement une branche source via --from."
    Et la sortie contient "false"

  Scénario: Deux branches sources sont refusées
    Quand je lance "jgit util verify_rebase --from develop --from main --into main"
    Alors jgit se termine en erreur
    Et la sortie contient "veuillez fournir exactement une branche source via --from."
    Et la sortie contient "false"

  Scénario: Une branche source inconnue est refusée
    Quand je lance "jgit util verify_rebase --from inconnue --into main"
    Alors jgit se termine en erreur
    Et la sortie contient "la branche source 'inconnue' est introuvable."
    Et la sortie contient "false"

  Scénario: Une branche cible inconnue est refusée
    Quand je lance "jgit util verify_rebase --from develop --into inconnue"
    Alors jgit se termine en erreur
    Et la sortie contient "la branche cible 'inconnue' est introuvable."
    Et la sortie contient "false"

  Scénario: Un espace de travail sale interdit la vérification
    Étant donné je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit util verify_rebase --from develop --into main"
    Alors jgit se termine en erreur
    Et la sortie contient "l'espace de travail contient des modifications. Nettoyez-le avant de lancer la vérification."
    Et la sortie contient "false"
    Et le fichier de travail "src/app.txt" contient "travail en cours"

  Scénario: Une branche comparée à elle-même passe toujours
    Quand je lance "jgit util verify_rebase --from develop --into develop"
    Alors jgit se termine sans erreur
    Et la sortie contient "true"

  Scénario: Un rebase possible répond true sans rien modifier
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/nouveau.txt" contenant "sans conflit" avec le message "Ajoute un fichier sans conflit"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/autre.txt" contenant "autre" sur la branche "develop" avec le message "Livraison sans conflit"
    Et je me place sur la branche "develop"
    Et je récupère les nouveautés du remote
    Et je note l'état de la branche distante "feature/TEST-1"
    Quand je lance "jgit util verify_rebase --from feature/TEST-1 --into origin/develop"
    Alors jgit se termine sans erreur
    Et la sortie contient "true"
    Et je suis sur la branche "develop"
    Et la branche distante "feature/TEST-1" est inchangée
    Et l'espace de travail est propre

  Scénario: Un rebase conflictuel répond false et ne laisse aucune trace
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature" avec le message "Modifie app.txt côté feature"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt côté develop"
    Et je me place sur la branche "develop"
    Et je récupère les nouveautés du remote
    Et je note l'état de la branche distante "feature/TEST-2"
    Quand je lance "jgit util verify_rebase --from feature/TEST-2 --into origin/develop"
    Alors jgit se termine en erreur
    Et la sortie contient "false"
    Et je suis sur la branche "develop"
    Et la branche distante "feature/TEST-2" est inchangée
    Et l'espace de travail est propre
    Et l'historique local de "feature/TEST-2" contient "Modifie app.txt côté feature"

  Scénario: La vérification nettoie sa branche temporaire
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/nouveau.txt" contenant "sans conflit" avec le message "Ajoute un fichier sans conflit"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Quand je lance "jgit util verify_rebase --from feature/TEST-3 --into develop"
    Alors jgit se termine sans erreur
    Et la branche locale "feature/TEST-3" existe
    Et la branche locale "develop" existe
    Et je suis sur la branche "develop"

  # --- stash automatique ----------------------------------------------------

  Scénario: Le travail non commité est mis de côté puis restauré
    Étant donné je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "You have uncommited modifications."
    Et la sortie contient "Do you want to stash and unstash changes at the end of process ? -> y"
    Et la branche distante "feature/TEST-4" existe
    Et je suis sur la branche "feature/TEST-4"
    Et le fichier de travail "src/app.txt" contient "travail en cours"
    Et l'espace de travail contient encore mes modifications

  Scénario: Refuser le stash interrompt la commande sans rien toucher
    Étant donné je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit feature start TEST-5" et que je réponds aux questions :
      | Do you want to stash and unstash changes | n |
    Alors jgit se termine en erreur
    Et la branche locale "feature/TEST-5" n'existe pas
    Et la branche distante "feature/TEST-5" n'existe pas
    Et le fichier de travail "src/app.txt" contient "travail en cours"
    Et GitHub a reçu exactement 0 appels

  # Le stash automatique ne couvre que feature et hotfix : on y travaille. Une
  # release ou une démo se fabrique, et jgit refuse de le faire sur un dépôt en
  # cours de modification plutôt que de ranger le travail à votre place.
  Scénario: Les commandes de release refusent un espace de travail sale
    Étant donné je me place sur la branche "develop"
    Et je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit release start --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Votre espace de travail contient des modifications non commitées."
    Et la sortie ne contient pas "You have uncommited modifications."
    Et je suis sur la branche "develop"
    Et le fichier de travail "src/app.txt" contient "travail en cours"
    Et l'espace de travail contient encore mes modifications
    Et la branche distante "release/1.1.0" n'existe pas

  Scénario: Les commandes de démo refusent elles aussi
    Étant donné je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit demo start sprint12 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Une démo ne se fabrique pas sur un dépôt en cours de modification."
    Et le fichier de travail "src/app.txt" contient "travail en cours"
    Et la branche distante "demo_sprint12" n'existe pas

  Scénario: util ne déclenche pas le stash automatique
    Étant donné je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit util clean"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "You have uncommited modifications."
    Et le fichier de travail "src/app.txt" contient "travail en cours"
