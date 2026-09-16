# language: fr
Fonctionnalité: Parcours complets de bout en bout
  Ces scénarios enchaînent les commandes telles qu'un développeur les utilise
  réellement sur une journée de travail, pour vérifier que les commandes tiennent
  ensemble et pas seulement isolément.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Un hotfix part de la production et y revient
    # --- Le correctif est développé ---------------------------------------
    Étant donné je me place sur la branche "develop"
    Et je commite le fichier "src/preprod.txt" contenant "en cours de préprod" avec le message "Travail de préprod en cours"
    Et je pousse la branche courante
    Quand je lance "jgit hotfix start URGENT-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "hotfix/URGENT-1"
    Et GitHub a reçu "--base=__PR__hotfix/URGENT-1"

    Quand je commite le fichier "src/correctif.txt" contenant "correctif de production" avec le message "Corrige le bug de production"
    Et je pousse la branche courante
    Et la PR de "hotfix/URGENT-1" est squash-mergée sur GitHub avec le message "URGENT-1 : corrige le bug (#12)"

    # --- Le correctif part en release -------------------------------------
    Quand je lance "jgit release merge --from hotfix/URGENT-1"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/1.1.0"
    Et le fichier "src/correctif.txt" existe sur la branche distante "release/1.1.0"
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "release/1.1.0"

    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "main"
    Et le fichier "src/correctif.txt" existe sur la branche distante "main"
    Et le fichier "src/correctif.txt" existe dans le tag "1.1.0"
    Et le tag "1.1.0" existe sur le remote
    Et la branche distante "release/1.1.0" n'existe pas
    Et GitHub a reçu "release create 1.1.0 --generate-notes"

  Scénario: Une feature est rebasée, redémarrée puis livrée
    # --- Premier lot de travail -------------------------------------------
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/lot1.txt" contenant "lot 1" avec le message "Premier lot"
    Et je pousse la branche courante

    # --- Un collègue livre en préprod : il faut se rebaser ----------------
    Étant donné un autre développeur pousse le fichier "src/collegue.txt" contenant "travail du collègue" sur la branche "develop" avec le message "Livraison du collègue"
    Quand je lance "jgit feature rebase TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/collegue.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/lot1.txt" existe sur la branche distante "feature/TEST-1"

    # --- La PR est mergée, le travail reprend -----------------------------
    Quand la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 : premier lot (#20)"
    Et je lance "jgit feature restart TEST-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Quand je commite le fichier "src/lot2.txt" contenant "lot 2" avec le message "Second lot"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 : second lot (#21)"

    # --- Livraison ---------------------------------------------------------
    Quand je lance "jgit release merge --from feature/TEST-1"
    Alors jgit se termine sans erreur
    Et le fichier "src/lot1.txt" existe sur la branche distante "release/1.1.0"
    Et le fichier "src/lot2.txt" existe sur la branche distante "release/1.1.0"
    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et le fichier "src/lot1.txt" existe dans le tag "1.1.0"
    Et le fichier "src/lot2.txt" existe dans le tag "1.1.0"
    Et le fichier "src/collegue.txt" existe sur la branche distante "main"

  Scénario: Une démo sert de répétition avant la release
    # --- Deux features prêtes ---------------------------------------------
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante

    # --- On les montre sur une branche de démo ----------------------------
    Quand je lance "jgit demo start sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Quand je lance "jgit demo merge --from feature/TEST-2 --from feature/TEST-3 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature2.txt" existe sur la branche distante "demo_sprint12"
    Et le fichier "src/feature3.txt" existe sur la branche distante "demo_sprint12"
    Quand je lance "jgit demo list"
    Alors jgit se termine sans erreur
    Et la sortie contient "Branches mergées dans demo_sprint12 :"

    # --- La démo validée, on livre pour de vrai ---------------------------
    Quand la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 (#22)"
    Et la PR de "feature/TEST-3" est squash-mergée sur GitHub avec le message "TEST-3 (#23)"
    Et je lance "jgit release merge --from feature/TEST-2 --from feature/TEST-3"
    Alors jgit se termine sans erreur
    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature2.txt" existe dans le tag "1.1.0"
    Et le fichier "src/feature3.txt" existe dans le tag "1.1.0"

    # --- La démo est démontée ---------------------------------------------
    Quand je me place sur la branche "demo_sprint12"
    Et je lance "jgit demo remove --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo_sprint12" n'existe pas
    Et la branche locale "demo_sprint12" n'existe pas

  Scénario: Deux releases successives s'enchaînent
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/feature4.txt" contenant "feature 4" avec le message "Ajoute la feature 4"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 (#24)"
    Et je lance "jgit release merge --from feature/TEST-4"
    Et je lance "jgit release finish"

    Quand je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Quand je commite le fichier "src/feature5.txt" contenant "feature 5" avec le message "Ajoute la feature 5"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-5" est squash-mergée sur GitHub avec le message "TEST-5 (#25)"
    Et je lance "jgit release merge --from feature/TEST-5"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/1.2.0"
    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et le tag "1.1.0" existe sur le remote
    Et le tag "1.2.0" existe sur le remote
    Et le fichier "src/feature4.txt" existe dans le tag "1.2.0"
    Et le fichier "src/feature5.txt" existe dans le tag "1.2.0"
    Et le fichier "src/feature5.txt" n'existe pas sur la branche distante "develop"
    Et GitHub a reçu "release create 1.1.0 --generate-notes"
    Et GitHub a reçu "release create 1.2.0 --generate-notes"
