# language: fr
Fonctionnalité: Branches de démonstration
  Une branche demo_* agrège, par rebase, les features que l'on souhaite montrer
  avant de les livrer. Chaque intégration laisse un commit marqueur qui permet
  de lister ensuite le contenu de la démo.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- demo start -----------------------------------------------------------

  Scénario: Sans nom, la démo porte celui de la branche de référence
    Quand je lance "jgit demo start --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "JGit va créer la branche de démo demo_develop qui se basera sur la branche develop"
    Et la sortie contient "Branche demo_develop créée depuis develop et publiée avec succès."
    Et je suis sur la branche "demo_develop"
    Et la branche distante "demo_develop" existe
    Et le dernier commit de "demo_develop" contient "[jgit] INIT demo demo_develop [empty_commit]"

  Scénario: Une démo peut être nommée
    Quand je lance "jgit demo start sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "demo_sprint12"
    Et la branche distante "demo_sprint12" existe

  Scénario: --based-on choisit la branche de départ de la démo
    Étant donné je me place sur la branche "develop"
    Et je commite le fichier "src/preprod.txt" contenant "en préprod" avec le message "Travail en préprod"
    Et je pousse la branche courante
    Quand je lance "jgit demo start sprint13 --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo_sprint13" existe
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "demo_sprint13"

  Scénario: Relancer start sur une démo publiée la remet simplement à jour
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Quand je lance "jgit demo start sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "Branche demo_sprint12 prête pour la démo."
    Et je suis sur la branche "demo_sprint12"

  # Une démo est toujours créée et poussée par jgit : l'état « en local mais
  # pas sur le serveur » vient d'une suppression côté GitHub, pas d'une branche
  # fabriquée à la main.
  Scénario: Une démo absente du serveur doit être traitée à la main
    Étant donné je lance "jgit demo start orpheline --no-interaction"
    Et la branche "demo_orpheline" est supprimée sur GitHub
    Quand je lance "jgit demo start orpheline --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche demo_orpheline existe en local mais pas sur origin."
    Et la sortie contient "Veuillez la publier manuellement ou la supprimer avant de relancer la commande."
    Et la branche distante "demo_orpheline" n'existe pas

  Scénario: Refuser la confirmation ne crée aucune démo
    Quand je lance "jgit demo start sprint14" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche locale "demo_sprint14" n'existe pas
    Et la branche distante "demo_sprint14" n'existe pas

  # --- demo merge -----------------------------------------------------------

  Scénario: Une feature est intégrée à la démo
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint12"
    Quand je lance "jgit demo merge --from feature/TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "Branche feature/TEST-1 rebasée avec succès dans demo_sprint12."
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo_sprint12"
    Et l'historique de "demo_sprint12" contient "[jgit] DEMO merge feature feature/TEST-1 [empty_commit]"

  Scénario: Plusieurs sources sont intégrées en une commande
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et je lance "jgit hotfix start URGENT-2 --no-interaction --no-open"
    Et je commite le fichier "src/correctif2.txt" contenant "correctif 2" avec le message "Ajoute le correctif 2"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint12"
    Quand je lance "jgit demo merge --from feature/TEST-2 --from hotfix/URGENT-2 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature2.txt" existe sur la branche distante "demo_sprint12"
    Et le fichier "src/correctif2.txt" existe sur la branche distante "demo_sprint12"
    Et l'historique de "demo_sprint12" contient "[jgit] DEMO merge feature feature/TEST-2"
    Et l'historique de "demo_sprint12" contient "[jgit] DEMO merge hotfix hotfix/URGENT-2"

  Scénario: --into désigne la démo à alimenter
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Quand je lance "jgit demo merge --from feature/TEST-3 --into sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "demo_sprint12"
    Et le fichier "src/feature3.txt" existe sur la branche distante "demo_sprint12"

  Scénario: Intégrer deux fois la même feature ne change rien
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/feature4.txt" contenant "feature 4" avec le message "Ajoute la feature 4"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint12"
    Et je lance "jgit demo merge --from feature/TEST-4 --no-interaction"
    Et je note l'état de la branche distante "demo_sprint12"
    Quand je lance "jgit demo merge --from feature/TEST-4 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "La branche feature/TEST-4 est déjà présente dans demo_sprint12."
    Et la branche distante "demo_sprint12" est inchangée

  Scénario: Une source au mauvais format est refusée
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je note l'état de la branche distante "demo_sprint12"
    Quand je lance "jgit demo merge --from TEST-5 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Le format attendu est feature/<ticket> ou hotfix/<ticket>."
    Et la branche distante "demo_sprint12" est inchangée

  Scénario: Une source absente du remote est refusée
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je note l'état de la branche distante "demo_sprint12"
    Quand je lance "jgit demo merge --from feature/INCONNUE --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche feature/INCONNUE n'existe pas sur origin."
    Et la branche distante "demo_sprint12" est inchangée

  Scénario: Le merge de démo n'est possible que depuis une branche demo_*
    Étant donné je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Et je commite le fichier "src/feature6.txt" contenant "feature 6" avec le message "Ajoute la feature 6"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Quand je lance "jgit demo merge --from feature/TEST-6 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Cette commande doit être exécutée sur une branche demo_* (branche actuelle : develop)."

  # --- demo list ------------------------------------------------------------

  Scénario: Une démo vide se signale comme telle
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Quand je lance "jgit demo list"
    Alors jgit se termine sans erreur
    Et la sortie contient "Aucune branche mergée détectée pour demo_sprint12."

  Scénario: demo list ne fonctionne que depuis une branche demo_*
    Étant donné je me place sur la branche "develop"
    Quand je lance "jgit demo list"
    Alors jgit se termine en erreur
    Et la sortie contient "Cette commande doit être exécutée depuis une branche demo_*."

  # Le marqueur de démo compte six mots :
  #   [jgit] DEMO merge <type> <type>/<ticket> [empty_commit]
  # Un séparateur fantaisiste ou un mot de décalage dans le découpage suffit à
  # tronquer « feature/TEST-7 » en « feature », ce qui rend la commande release
  # suggérée inutilisable telle quelle.
  Scénario: demo list affiche le nom complet des branches intégrées
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Et je commite le fichier "src/feature7.txt" contenant "feature 7" avec le message "Ajoute la feature 7"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint12"
    Et je lance "jgit demo merge --from feature/TEST-7 --no-interaction"
    Quand je lance "jgit demo list"
    Alors jgit se termine sans erreur
    Et la sortie contient "Branches mergées dans demo_sprint12 :"
    Et la sortie contient "feature/TEST-7"
    Et la sortie contient "Commandes release suggérées :"
    Et la sortie contient "jgit release merge --from feature/TEST-7"

  # --- demo remove ----------------------------------------------------------

  Scénario: Une démo terminée est supprimée partout
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Quand je lance "jgit demo remove --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "Branche de démo supprimée avec succès."
    Et la branche distante "demo_sprint12" n'existe pas
    Et la branche locale "demo_sprint12" n'existe pas
    Et je suis sur la branche "develop"

  Scénario: Refuser la suppression conserve la démo
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Quand je lance "jgit demo remove" et que je réponds aux questions :
      | Confirmez-vous la suppression | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche distante "demo_sprint12" existe
    Et la branche locale "demo_sprint12" existe

  Scénario: Une démo déjà supprimée sur GitHub est nettoyée en local
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et la branche "demo_sprint12" est supprimée sur GitHub
    Quand je lance "jgit demo remove --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "Aucune branche distante demo_sprint12 trouvée."
    Et la branche locale "demo_sprint12" n'existe pas
    Et je suis sur la branche "develop"

  Scénario: demo remove ne fonctionne que depuis une branche demo_*
    Étant donné je me place sur la branche "develop"
    Quand je lance "jgit demo remove --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Cette commande doit être exécutée depuis une branche demo_*."
