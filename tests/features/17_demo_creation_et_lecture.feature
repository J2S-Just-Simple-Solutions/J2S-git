# language: fr
Fonctionnalité: Créer une démo, puis la lire
  Une démo est une recette : une base et une liste ordonnée de tickets, écrite
  dans la branche demo/<nom> elle-même. Les commits de chaque ticket y sont
  cherry-pickés tels quels, puis un repère clôt le segment du ticket.

  « demo list » montre toutes les démos et leur état, « demo show » le détail
  d'une démo ticket par ticket, « demo candidates » les tickets que l'on peut
  y ajouter. Ces trois commandes ne font que lire.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je commite le fichier "src/feature1-bis.txt" contenant "feature 1 bis" avec le message "Complète la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"

  # --- demo create -----------------------------------------------------------

  Scénario: Une démo vide est créée sur la version serveur de develop
    Quand je lance "jgit demo create sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "schema" égal à "jgit.demo.result/1"
    Et le JSON a "operation" égal à "create"
    Et le JSON a "demo" égal à "sprint12"
    Et le JSON a "branch" égal à "demo/sprint12"
    Et le JSON a "changed" vrai
    Et le JSON a "pushed" vrai
    Et le JSON a "base" égal à "develop"
    Et le JSON a "old_sha" nul
    Et la branche distante "demo/sprint12" existe
    Et la branche distante "demo/sprint12" est partie de "develop"
    Et le dernier commit de "demo/sprint12" contient "[jgit] INIT demo demo/sprint12 [empty_commit]"
    Et la démo distante "demo/sprint12" ne contient aucun ticket
    # Une démo se fabrique : on reste là où l'on était.
    Et je suis sur la branche "develop"
    Et la branche locale "demo/sprint12" n'existe pas
    Et la branche locale "jgit_demo_sprint12" n'existe pas

  Scénario: Une démo est créée avec ses tickets, dans l'ordre demandé
    Quand je lance "jgit demo create sprint12 --from feature/TEST-1 --from hotfix/URGENT-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "added" contient 2 éléments
    Et le JSON a "added[0]" égal à "feature/TEST-1"
    Et le JSON a "added[1]" égal à "hotfix/URGENT-1"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1  |
      | hotfix/URGENT-1 |
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/feature1-bis.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/correctif.txt" existe sur la branche distante "demo/sprint12"
    Et l'historique de "demo/sprint12" contient "[jgit] DEMO ticket feature/TEST-1 [empty_commit]"
    Et l'historique de "demo/sprint12" contient "[jgit] DEMO ticket hotfix/URGENT-1 [empty_commit]"
    # Les commits de travail sont repris, pas les commits d'init des tickets.
    Et l'historique de "demo/sprint12" ne contient pas "START feature/TEST-1"

  Scénario: --based-on choisit la base de la démo
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo create recette --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo/recette" est partie de "main"
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "demo/recette"

  Scénario: La création demande confirmation, et un refus ne crée rien
    Quand je lance "jgit demo create sprint12 --from feature/TEST-1" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "JGit va créer la démo demo/sprint12 basée sur develop"
    Et la sortie contient "+ feature/TEST-1"
    Et la sortie contient "Opération annulée."
    Et la branche distante "demo/sprint12" n'existe pas
    Et je suis sur la branche "develop"

  Scénario: --dry-run montre ce qui serait fait sans rien créer
    Quand je lance "jgit demo create sprint12 --from feature/TEST-1 --dry-run --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dry_run" vrai
    Et le JSON a "pushed" faux
    Et le JSON a "added[0]" égal à "feature/TEST-1"
    Et la sortie contient "--dry-run : rien n'a été modifié."
    Et la branche distante "demo/sprint12" n'existe pas

  Scénario: Une démo qui existe déjà n'est pas recréée
    Étant donné je lance "jgit demo create sprint12 --no-interaction"
    Et je note l'état de la branche distante "demo/sprint12"
    Quand je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "already_exists"
    Et le JSON a "error.hint" qui contient "jgit demo add sprint12 --from <ticket>"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Un nom de démo invalide est refusé
    Quand je lance "jgit demo create sprint..12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "invalid_name"
    Et la branche distante "demo/sprint..12" n'existe pas

  Scénario: Une démo sans nom est refusée
    Quand je lance "jgit demo create --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"

  Scénario: Une base inexistante est refusée comme pour une feature
    Quand je lance "jgit demo create vitrine --based-on inexistante --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "base_not_found"
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "jgit demo create vitrine --based-on <branche>"
    Et la branche distante "demo/vitrine" n'existe pas

  Scénario: Un ticket au mauvais format ou absent du serveur est refusé
    Quand je lance "jgit demo create sprint12 --from TEST-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "bad_ticket_format"
    Quand je lance "jgit demo create sprint12 --from feature/INCONNU --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "ticket_not_found"
    Et la branche distante "demo/sprint12" n'existe pas

  # Une démo se fabrique à partir du serveur, sur une branche temporaire : un
  # espace de travail en cours de modification n'y a pas sa place.
  Scénario: Un espace de travail sale empêche de fabriquer une démo
    Étant donné je modifie le fichier "src/brouillon.txt" avec "en cours"
    Quand je lance "jgit demo create sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine en erreur
    Et le JSON a "error.code" égal à "worktree_dirty"
    Et la branche distante "demo/sprint12" n'existe pas
    Et le fichier de travail "src/brouillon.txt" contient "en cours"

  # --- demo list -------------------------------------------------------------

  Scénario: Sans démo, la liste le dit
    Quand je lance "jgit demo list --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.list/1"
    Et la liste JSON "demos" contient 0 éléments
    Et la sortie contient "Aucune démo."

  Scénario: La liste montre chaque démo, sa base et son état
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --from hotfix/URGENT-1 --no-interaction"
    Et je lance "jgit demo create recette --based-on main --no-interaction"
    Quand je lance "jgit demo list --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "demos" contient 2 éléments
    Et le JSON a "demos[name=sprint12].branch" égal à "demo/sprint12"
    Et le JSON a "demos[name=sprint12].base" égal à "develop"
    Et le JSON a "demos[name=sprint12].ticket_count" égal au nombre 2
    Et le JSON a "demos[name=sprint12].behind_base" égal au nombre 0
    Et le JSON a "demos[name=sprint12].needs_rebase" faux
    Et le JSON a "demos[name=sprint12].archived" faux
    Et le JSON a "demos[name=sprint12].format" égal à "v2"
    Et le JSON a "demos[name=recette].base" égal à "main"
    Et la sortie contient "sprint12"
    Et la sortie contient "2 tickets"
    Et la sortie contient "✔ à jour"

  Scénario: Les commandes de lecture n'ont pas besoin d'identité git
    Étant donné je lance "jgit demo create sprint12 --no-interaction"
    Et aucune identité git n'est configurée
    Quand je lance "jgit demo list"
    Alors jgit se termine sans erreur
    Et la sortie contient "sprint12"

  # --- demo show -------------------------------------------------------------

  Scénario: Le détail d'une démo à jour
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --from hotfix/URGENT-1 --no-interaction"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.show/1"
    Et le JSON a "demo.name" égal à "sprint12"
    Et le JSON a "demo.base" égal à "develop"
    Et le JSON a "demo.behind_base" égal au nombre 0
    Et la liste JSON "tickets" contient 2 éléments
    Et le JSON a "tickets[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "tickets[0].type" égal à "feature"
    Et le JSON a "tickets[0].id" égal à "TEST-1"
    Et le JSON a "tickets[0].position" égal au nombre 1
    Et le JSON a "tickets[0].status" égal à "up_to_date"
    Et le JSON a "tickets[0].delivered" faux
    Et le JSON a "tickets[0].commits_in_demo" égal au nombre 2
    Et le JSON a "tickets[0].commits_not_in_demo" égal au nombre 0
    Et le JSON a "tickets[0].suggested_action" égal à "none"
    Et le JSON a "tickets[1].ticket" égal à "hotfix/URGENT-1"
    Et la liste JSON "foreign_commits" contient 0 éléments
    Et le JSON a "release_command" égal à "jgit release merge --from feature/TEST-1 --from hotfix/URGENT-1"
    Et la sortie contient "Démo sprint12 (demo/sprint12)"
    Et la sortie contient "Base         develop — à jour"

  Scénario: Un ticket qui a avancé depuis son ajout est signalé
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et je me place sur la branche "feature/TEST-1"
    Et je commite le fichier "src/feature1-ter.txt" contenant "suite" avec le message "Poursuit la feature 1"
    Et je pousse la branche courante
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[0].status" égal à "ahead"
    Et le JSON a "tickets[0].commits_not_in_demo" égal au nombre 1
    Et le JSON a "tickets[0].suggested_action" égal à "add"
    Et le JSON a "demo.tickets_needing_attention" égal au nombre 1
    Et la sortie contient "1 commit pas encore dans la démo"
    Et la sortie contient "jgit demo add sprint12 --from feature/TEST-1"

  # Le cœur du modèle : « jgit feature rebase » recalcule tous les SHA du
  # ticket, mais ses commits gardent leur empreinte (auteur, date, sujet).
  Scénario: Un ticket rebasé par jgit reste reconnu à jour
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je lance "jgit feature rebase TEST-1 --no-interaction"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[0].status" égal à "up_to_date"
    Et le JSON a "tickets[0].commits_in_demo" égal au nombre 2

  Scénario: Un ticket réécrit (squash) est signalé comme à reprendre
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je lance "jgit feature rebase TEST-1 --squash --no-interaction"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[0].status" égal à "diverged"
    Et le JSON a "tickets[0].suggested_action" égal à "refresh"
    Et la sortie contient "jgit demo refresh sprint12 --from feature/TEST-1"

  Scénario: Un ticket dont la branche a disparu est signalé
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et la branche "feature/TEST-1" est supprimée sur GitHub
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[0].status" égal à "missing"
    Et le JSON a "tickets[0].remote_exists" faux
    Et le JSON a "tickets[0].suggested_action" égal à "drop"
    Et la sortie contient "branche supprimée du serveur"
    Et le JSON a "release_command" nul

  Scénario: Un ticket livré dans la base est signalé
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --from hotfix/URGENT-1 --no-interaction"
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 (#1)"
    Et la PR de "feature/TEST-1" est livrée dans "develop"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[ticket=feature/TEST-1].delivered" vrai
    Et le JSON a "tickets[ticket=feature/TEST-1].suggested_action" égal à "drop"
    Et le JSON a "tickets[ticket=hotfix/URGENT-1].delivered" faux
    Et le JSON a "release_command" égal à "jgit release merge --from hotfix/URGENT-1"
    Et la sortie contient "✔ livré dans develop"

  Scénario: Une démo en retard sur sa base le dit
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demo.behind_base" égal au nombre 1
    Et le JSON a "demo.needs_rebase" vrai
    Et la sortie contient "en retard de 1 commit(s)"
    Et la sortie contient "jgit demo rebase sprint12"

  Scénario: Un commit poussé à la main sur la démo est repéré
    Étant donné je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "foreign_commits" contient 1 éléments
    Et le JSON a "foreign_commits[0].subject" égal à "Rustine pour la démo"
    Et le JSON a "demo.foreign_commit_count" égal au nombre 1
    Et le JSON a "tickets[0].status" égal à "up_to_date"
    Et la sortie contient "Commits ajoutés à la main sur la démo"

  Scénario: Sans nom, show lit la démo de la branche courante
    Étant donné je lance "jgit demo create sprint12 --no-interaction"
    Et je récupère la branche distante "demo/sprint12" en local
    Et je me place sur la branche "demo/sprint12"
    Quand je lance "jgit demo show --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demo.name" égal à "sprint12"

  Scénario: Sans nom ni démo courante, show demande laquelle
    Quand je lance "jgit demo show --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Et le JSON a "error.hint" égal à "Les démos du projet : jgit demo list"

  Scénario: Une démo inconnue est refusée
    Quand je lance "jgit demo show inconnue --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "demo_not_found"

  # --- demo candidates -------------------------------------------------------

  Scénario: Les candidats d'une démo excluent ses tickets et signalent les livrés
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et la PR de "hotfix/URGENT-1" est squash-mergée sur GitHub avec le message "URGENT-1 (#2)"
    Et la PR de "hotfix/URGENT-1" est livrée dans "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Quand je lance "jgit demo candidates sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.candidates/1"
    Et le JSON a "demo" égal à "sprint12"
    Et le JSON a "base" égal à "develop"
    Et la liste JSON "candidates" contient 2 éléments
    Et le JSON a "candidates[ticket=feature/TEST-2].delivered" faux
    Et le JSON a "candidates[ticket=feature/TEST-2].last_subject" égal à "Ajoute la feature 2"
    Et le JSON a "candidates[ticket=hotfix/URGENT-1].delivered" vrai
    Et la sortie contient "Ajouter : jgit demo add sprint12 --from <ticket>"
    Et la sortie contient "Déjà livrés dans develop"

  Scénario: Sans démo, les candidats sont tous les tickets du serveur
    Quand je lance "jgit demo candidates --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demo" nul
    Et la liste JSON "candidates" contient 2 éléments
