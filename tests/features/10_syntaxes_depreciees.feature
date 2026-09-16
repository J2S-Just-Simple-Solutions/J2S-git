# language: fr
Fonctionnalité: Compatibilité avec les anciennes syntaxes
  Deux commandes ont changé de forme. Les anciennes restent acceptées le temps
  que les habitudes et les scripts de chacun rattrapent : elles fonctionnent à
  l'identique et affichent un avertissement de dépréciation.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- jgit release merge <branche> -----------------------------------------

  Scénario: L'ancienne forme positionnelle de release merge fonctionne encore
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 (#1)"
    Quand je lance "jgit release merge feature/TEST-1"
    Alors jgit se termine sans erreur
    Et la sortie contient "[déprécié] « jgit release merge feature/TEST-1 » : utilisez désormais « jgit release merge --from feature/TEST-1 »."
    Et la sortie contient "L'ancienne forme fonctionne encore mais sera retirée dans une prochaine version."
    Et je suis sur la branche "release/1.1.0"
    Et le fichier "src/feature1.txt" existe sur la branche distante "release/1.1.0"
    Et l'historique de "release/1.1.0" contient "[jgit] Release merge feature branch : __PR__feature/TEST-1"

  Scénario: L'ancienne forme accepte aussi un nom de branche déjà préfixé
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 (#2)"
    Quand je lance "jgit release merge __PR__feature/TEST-2"
    Alors jgit se termine sans erreur
    Et la sortie contient "[déprécié]"
    Et le fichier "src/feature2.txt" existe sur la branche distante "release/1.1.0"

  Scénario: L'ancienne forme fonctionne aussi pour un hotfix
    Étant donné je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et la PR de "hotfix/URGENT-1" est squash-mergée sur GitHub avec le message "URGENT-1 (#3)"
    Quand je lance "jgit release merge hotfix/URGENT-1"
    Alors jgit se termine sans erreur
    Et la sortie contient "[déprécié]"
    Et le fichier "src/correctif.txt" existe sur la branche distante "release/1.1.0"

  Scénario: La nouvelle forme n'affiche aucun avertissement
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-3" est squash-mergée sur GitHub avec le message "TEST-3 (#4)"
    Quand je lance "jgit release merge --from feature/TEST-3"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "[déprécié]"
    Et le fichier "src/feature3.txt" existe sur la branche distante "release/1.1.0"

  Scénario: Une version en position de cible reste une version, pas une source
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/feature4.txt" contenant "feature 4" avec le message "Ajoute la feature 4"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 (#5)"
    Quand je lance "jgit release merge 4.2.0 --from feature/TEST-4"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "[déprécié]"
    Et je suis sur la branche "release/4.2.0"
    Et le fichier "src/feature4.txt" existe sur la branche distante "release/4.2.0"

  Scénario: Une version préfixée release/ reste une version
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Et je commite le fichier "src/feature5.txt" contenant "feature 5" avec le message "Ajoute la feature 5"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-5" est squash-mergée sur GitHub avec le message "TEST-5 (#6)"
    Quand je lance "jgit release merge release/5.1.0 --from feature/TEST-5"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "[déprécié]"
    Et je suis sur la branche "release/5.1.0"

  Scénario: Sans source ni version, l'erreur reste celle de la nouvelle syntaxe
    Quand je lance "jgit release merge"
    Alors jgit se termine en erreur
    Et la sortie contient "Veuillez spécifier au moins une source avec --from."
    Et la sortie ne contient pas "[déprécié]"

  Scénario: Une version seule sans --from réclame toujours une source
    Quand je lance "jgit release merge 4.2.0"
    Alors jgit se termine en erreur
    Et la sortie contient "Veuillez spécifier au moins une source avec --from."
    Et la sortie ne contient pas "[déprécié]"
    Et la branche distante "release/4.2.0" n'existe pas

  Scénario: Mélanger les deux syntaxes est refusé explicitement
    Quand je lance "jgit release merge feature/TEST-6 --from feature/TEST-7"
    Alors jgit se termine en erreur
    Et la sortie contient "Version de release attendue au format x.y.z, reçu 'feature/TEST-6'."
    Et la sortie contient "Pour désigner une branche source, utilisez --from feature/TEST-6."
    Et la branche distante "release/1.1.0" n'existe pas

  # --- jgit clean -----------------------------------------------------------

  Scénario: L'ancien jgit clean fonctionne encore
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je récupère la branche distante "__PR__feature/TEST-1" en local
    Et je lance "jgit feature start GARDEE --no-interaction --no-open"
    Et je crée la branche locale "jgit_rebase_feature/TEST-1"
    Quand je lance "jgit clean"
    Alors jgit se termine sans erreur
    Et la sortie contient "[déprécié] « jgit clean » : utilisez désormais « jgit util clean »."
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas
    Et la branche locale "__PR__feature/TEST-1" n'existe pas
    Et la branche locale "feature/GARDEE" existe
    Et la branche locale "feature/TEST-1" existe

  Scénario: jgit util clean n'affiche aucun avertissement
    Étant donné je crée la branche locale "jgit_rebase_feature/TEST-1"
    Quand je lance "jgit util clean"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "[déprécié]"
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas

  # --- Documentation --------------------------------------------------------

  Scénario: L'aide documente les syntaxes dépréciées
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    Et la sortie contient "Syntaxes dépréciées"
    Et la sortie contient "jgit release merge <branche>   → jgit release merge --from <branche>"
    Et la sortie contient "jgit clean                     → jgit util clean"
