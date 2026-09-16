# language: fr
Fonctionnalité: Livraison d'une feature, de sa création à la release
  Le scénario déroule de vraies commandes git dans un dépôt jetable :
  vrais commits, vraies branches, vrai tag. Seul GitHub est simulé, le remote
  est local et le client gh est mocké.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Une feature est développée puis livrée dans une release

    # --- Création de la feature -------------------------------------------
    Quand je lance "jgit feature start TEST-123" et que je réponds aux questions :
      | Souhaitez-vous continuer | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "JGit va créer la branche feature/TEST-123"
    Et la branche locale "feature/TEST-123" existe
    Et la branche distante "feature/TEST-123" existe
    Et je suis sur la branche "feature/TEST-123"
    Et la branche distante "__PR__feature/TEST-123" existe
    Et la branche locale "__PR__feature/TEST-123" n'existe pas
    Et le dernier commit de "__PR__feature/TEST-123" contient "[jgit] INIT feature/TEST-123"
    Et le dernier commit de "feature/TEST-123" contient "START feature/TEST-123"
    Et GitHub a reçu "pr create"
    Et GitHub a reçu "--base=__PR__feature/TEST-123"
    Et GitHub a reçu "--head=feature/TEST-123"
    Et GitHub a reçu "--title TEST-123"

    # --- Le développeur travaille -----------------------------------------
    Quand je commite le fichier "src/feature.txt" contenant "fonctionnalité TEST-123" avec le message "Ajoute la fonctionnalité"
    Et je commite le fichier "src/app.txt" contenant "version 1.1.0" avec le message "Met à jour la version applicative"
    Et je pousse la branche courante
    Alors le fichier "src/feature.txt" existe sur la branche distante "feature/TEST-123"
    Et le fichier "src/feature.txt" n'existe pas sur la branche distante "__PR__feature/TEST-123"

    # --- La PR est validée et mergée sur GitHub ---------------------------
    Quand la PR de "feature/TEST-123" est squash-mergée sur GitHub avec le message "TEST-123 : ajoute la fonctionnalité (#42)"
    Alors le fichier "src/feature.txt" existe sur la branche distante "__PR__feature/TEST-123"
    Et le dernier commit de "__PR__feature/TEST-123" contient "TEST-123 : ajoute la fonctionnalité"

    # --- Intégration dans la release --------------------------------------
    Quand je lance "jgit release merge --from feature/TEST-123"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "release/1.1.0"
    Et la branche distante "release/1.1.0" existe
    Et le fichier "src/feature.txt" existe sur la branche distante "release/1.1.0"
    Et le fichier "src/app.txt" de la branche distante "release/1.1.0" contient "version 1.1.0"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-123"
    Et l'historique de "release/1.1.0" contient "[jgit] INIT release release/1.1.0"
    Et le fichier "src/feature.txt" n'existe pas sur la branche distante "main"

    # --- Finalisation de la release ---------------------------------------
    Quand je lance "jgit release finish"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "main"
    Et le fichier "src/feature.txt" existe sur la branche distante "main"
    Et le fichier "src/app.txt" de la branche distante "main" contient "version 1.1.0"
    Et l'historique de "main" contient "Merge release branch : release/1.1.0"
    Et le tag "1.1.0" existe sur le remote
    Et le fichier "src/feature.txt" existe dans le tag "1.1.0"
    Et la branche distante "release/1.1.0" n'existe pas
    Et la branche locale "release/1.1.0" n'existe pas
    Et le fichier "src/feature.txt" n'existe pas sur la branche distante "develop"
    Et GitHub a reçu "release create 1.1.0 --generate-notes"
    Et GitHub a reçu exactement 2 appels
