# language: fr
Fonctionnalité: Cycle de vie d'une release
  « release start » calcule la prochaine version à partir du dernier tag,
  « release merge » y intègre les branches __PR__ des features livrées et
  « release finish » fusionne le tout dans main, pose le tag et publie la
  release GitHub.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- release start --------------------------------------------------------

  Scénario: La version suivante est déduite du dernier tag
    Quand je lance "jgit release start"
    Alors jgit se termine sans erreur
    Et la sortie contient "Current tag: 1.0.0"
    Et la sortie contient "Searching a branch naming: release/1.1.0"
    Et la sortie contient "Release does not exists, create it..."
    Et je suis sur la branche "release/1.1.0"
    Et la branche distante "release/1.1.0" existe
    Et le dernier commit de "release/1.1.0" contient "[jgit] INIT release release/1.1.0. [empty_commit]"

  Scénario: La release part de main et non de develop
    Étant donné je me place sur la branche "develop"
    Et je commite le fichier "src/preprod.txt" contenant "en préprod" avec le message "Travail en préprod"
    Et je pousse la branche courante
    Quand je lance "jgit release start"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "release/1.1.0"

  Scénario: Une version explicite est respectée
    Quand je lance "jgit release start 2.5.0"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/2.5.0"
    Et la branche distante "release/2.5.0" existe

  Scénario: Une version déjà préfixée par release/ est acceptée telle quelle
    Quand je lance "jgit release start release/3.0.0"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/3.0.0"
    Et la branche distante "release/3.0.0" existe
    Et la branche distante "release/release/3.0.0" n'existe pas

  Scénario: Sans tag de départ, la release est impossible
    Étant donné le tag "1.0.0" est supprimé partout
    Quand je lance "jgit release start"
    Alors jgit se termine en erreur
    Et la sortie contient "A tag must already exists (x.x.x format)"
    Et la branche distante "release/1.1.0" n'existe pas

  Scénario: Un fichier non suivi empêche de démarrer une release
    Étant donné je modifie le fichier "src/brouillon.txt" avec "travail en cours"
    Quand je lance "jgit release start"
    Alors jgit se termine en erreur
    Et la sortie contient "Local changes, cannot start release"
    Et la branche distante "release/1.1.0" n'existe pas

  Scénario: Relancer start réutilise la release déjà publiée
    Étant donné je lance "jgit release start"
    Quand je lance "jgit release start"
    Alors jgit se termine sans erreur
    Et la sortie contient "Release release/1.1.0 local branch exists, deletion..."
    Et la sortie contient "Remote branch exists, use it..."
    Et je suis sur la branche "release/1.1.0"
    Et la branche distante "release/1.1.0" a 1 commits d'avance sur "main"

  # --- release merge --------------------------------------------------------

  Scénario: Une feature livrée est intégrée à la release
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 : feature 1 (#1)"
    Quand je lance "jgit release merge --from feature/TEST-1"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/1.1.0"
    Et le fichier "src/feature1.txt" existe sur la branche distante "release/1.1.0"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-1"

  Scénario: La source peut être donnée directement sous sa forme __PR__
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 : feature 2 (#2)"
    Quand je lance "jgit release merge --from __PR__feature/TEST-2"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature2.txt" existe sur la branche distante "release/1.1.0"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-2"

  Scénario: Plusieurs features sont intégrées en une seule commande
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-3" est squash-mergée sur GitHub avec le message "TEST-3 : feature 3 (#3)"
    Et je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/feature4.txt" contenant "feature 4" avec le message "Ajoute la feature 4"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 : feature 4 (#4)"
    Quand je lance "jgit release merge --from feature/TEST-3 --from feature/TEST-4"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature3.txt" existe sur la branche distante "release/1.1.0"
    Et le fichier "src/feature4.txt" existe sur la branche distante "release/1.1.0"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-3"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-4"

  Scénario: Une version cible peut être imposée à la volée
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Et je commite le fichier "src/feature5.txt" contenant "feature 5" avec le message "Ajoute la feature 5"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-5" est squash-mergée sur GitHub avec le message "TEST-5 : feature 5 (#5)"
    Quand je lance "jgit release merge 4.2.0 --from feature/TEST-5"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/4.2.0"
    Et le fichier "src/feature5.txt" existe sur la branche distante "release/4.2.0"
    Et la branche distante "release/1.1.0" n'existe pas

  Scénario: --into réutilise une release déjà ouverte
    Étant donné je lance "jgit release start 5.0.0"
    Et je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Et je commite le fichier "src/feature6.txt" contenant "feature 6" avec le message "Ajoute la feature 6"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-6" est squash-mergée sur GitHub avec le message "TEST-6 : feature 6 (#6)"
    Et je récupère les nouveautés du remote
    Quand je lance "jgit release merge --from feature/TEST-6 --into 5.0.0"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/5.0.0"
    Et le fichier "src/feature6.txt" existe sur la branche distante "release/5.0.0"

  # Avec --into, jgit passe par checkout_release_branch, qui ne rafraîchit que
  # la branche de release : sans un fetch complet en tête de release_merge, les
  # références __PR__ restent périmées et la PR mergée est vue comme non mergée.
  Scénario: --into rafraîchit les références sans fetch préalable
    Étant donné je lance "jgit release start 6.0.0"
    Et je lance "jgit feature start TEST-13 --no-interaction --no-open"
    Et je commite le fichier "src/feature13.txt" contenant "feature 13" avec le message "Ajoute la feature 13"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-13" est squash-mergée sur GitHub avec le message "TEST-13 (#13)"
    Quand je lance "jgit release merge --from feature/TEST-13 --into 6.0.0"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/6.0.0"
    Et le fichier "src/feature13.txt" existe sur la branche distante "release/6.0.0"

  Scénario: --into sur une release inexistante est refusé
    Étant donné je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Et je commite le fichier "src/feature7.txt" contenant "feature 7" avec le message "Ajoute la feature 7"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-7" est squash-mergée sur GitHub avec le message "TEST-7 : feature 7 (#7)"
    Quand je lance "jgit release merge --from feature/TEST-7 --into 9.9.9"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche release/9.9.9 n'existe pas (ni en local ni sur origin)."
    Et la branche distante "release/9.9.9" n'existe pas

  Scénario: Une feature dont la PR n'est pas mergée est refusée
    Étant donné je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Et je commite le fichier "src/feature8.txt" contenant "feature 8" avec le message "Ajoute la feature 8"
    Et je pousse la branche courante
    Quand je lance "jgit release merge --from feature/TEST-8"
    Alors jgit se termine en erreur
    Et la sortie contient "ne contient que le commit d'initialisation. Merci de valider et merger la PR avant d'intégrer dans la release."
    Et le fichier "src/feature8.txt" n'existe pas sur la branche distante "release/1.1.0"

  Scénario: Une branche source inconnue est refusée
    Quand je lance "jgit release merge --from feature/INCONNUE"
    Alors jgit se termine en erreur
    Et la sortie contient "Feature branch '__PR__feature/INCONNUE' was not found!"

  # --- release finish -------------------------------------------------------

  Scénario: La release est fusionnée dans main, taguée et publiée
    Étant donné je lance "jgit feature start TEST-9 --no-interaction --no-open"
    Et je commite le fichier "src/feature9.txt" contenant "feature 9" avec le message "Ajoute la feature 9"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-9" est squash-mergée sur GitHub avec le message "TEST-9 : feature 9 (#9)"
    Et je lance "jgit release merge --from feature/TEST-9"
    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et la sortie contient "Future tag: 1.1.0"
    Et je suis sur la branche "main"
    Et le fichier "src/feature9.txt" existe sur la branche distante "main"
    Et l'historique de "main" contient "Merge release branch : release/1.1.0"
    Et le tag "1.1.0" existe sur le remote
    Et la branche distante "release/1.1.0" n'existe pas
    Et la branche locale "release/1.1.0" n'existe pas
    Et GitHub a reçu "release create 1.1.0 --generate-notes"

  Scénario: Une release finie peut être suivie d'une suivante
    Étant donné je lance "jgit feature start TEST-10 --no-interaction --no-open"
    Et je commite le fichier "src/feature10.txt" contenant "feature 10" avec le message "Ajoute la feature 10"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-10" est squash-mergée sur GitHub avec le message "TEST-10 (#10)"
    Et je lance "jgit release merge --from feature/TEST-10"
    Et je lance "jgit release finish"
    Quand je lance "jgit release start"
    Alors jgit se termine sans erreur
    Et la sortie contient "Current tag: 1.1.0"
    Et je suis sur la branche "release/1.2.0"

  Scénario: --into désigne explicitement la release à terminer
    Étant donné je lance "jgit feature start TEST-11 --no-interaction --no-open"
    Et je commite le fichier "src/feature11.txt" contenant "feature 11" avec le message "Ajoute la feature 11"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-11" est squash-mergée sur GitHub avec le message "TEST-11 (#11)"
    Et je lance "jgit release merge --from feature/TEST-11"
    Et je me place sur la branche "develop"
    Quand je lance "jgit release finish --into 1.1.0"
    Alors jgit se termine sans erreur
    Et le tag "1.1.0" existe sur le remote
    Et le fichier "src/feature11.txt" existe sur la branche distante "main"

  Scénario: Une release vide ne peut pas être terminée
    Étant donné je lance "jgit release start"
    Quand je lance "jgit release finish"
    Alors jgit se termine en erreur
    Et la sortie contient "It seems that the release is empty..."
    Et le tag "1.1.0" n'existe pas sur le remote
    Et GitHub n'a pas reçu "release create"

  Scénario: Terminer depuis develop bascule d'abord sur la release
    Étant donné je me place sur la branche "develop"
    Quand je lance "jgit release finish"
    Alors jgit se termine en erreur
    Et la sortie contient "Release: release/1.1.0"
    Et la sortie contient "It seems that the release is empty..."

  Scénario: Une release plus ancienne que le dernier tag est remplacée
    Étant donné je crée la branche locale "release/1.0.0" depuis "main"
    Et je me place sur la branche "release/1.0.0"
    Quand je lance "jgit release finish"
    Alors jgit se termine en erreur
    Et la sortie contient "Local release does not have the right tag, switching to new branch"
    Et la sortie contient "Release: release/1.1.0"

  # Le tag et le merge sur main sont déjà poussés quand gh échoue : jgit doit
  # sortir en erreur, mais en disant précisément ce qu'il reste à rejouer.
  Scénario: Un échec de gh release create est signalé
    Étant donné je lance "jgit feature start TEST-12 --no-interaction --no-open"
    Et je commite le fichier "src/feature12.txt" contenant "feature 12" avec le message "Ajoute la feature 12"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-12" est squash-mergée sur GitHub avec le message "TEST-12 (#12)"
    Et je lance "jgit release merge --from feature/TEST-12"
    Et le client gh échoue pour les commandes "release create"
    Quand je lance "jgit release finish"
    Alors jgit se termine en erreur
    Et la sortie contient "La release GitHub 1.1.0 n'a pas pu être créée."
    Et la sortie contient "il ne reste que la release GitHub."
    Et le tag "1.1.0" existe sur le remote
    Et GitHub a reçu "release create 1.1.0 --generate-notes"
