# language: fr
Fonctionnalité: Vérifier que les mises à jour des démos sont faisables
  « jgit demo check » simule, pour chaque démo, tout ce qui la remettrait à jour
  — rebase sur la base actuelle, retrait des tickets livrés ou disparus, reprise
  des tickets réécrits, ajout des nouveaux commits — et rend un rapport : ce
  qu'il faut lancer, et pour chaque conflit le ticket, le commit et son auteur,
  les fichiers, et en face le commit qui les a touchés et d'où il vient.

  La simulation se fait dans une copie de travail temporaire : rien n'est
  modifié, ni chez soi, ni sur le serveur.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature 1" avec le message "Modifie app.txt pour la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-1 --from feature/TEST-2 --no-interaction"
    Et je note l'état de la branche distante "demo/sprint12"

  Scénario: Une démo à jour n'a rien à faire
    Quand je lance "jgit demo check --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.check/1"
    Et le JSON a "demos[0].name" égal à "sprint12"
    Et le JSON a "demos[0].status" égal à "up_to_date"
    Et la liste JSON "demos[0].actions" contient 0 éléments
    Et le JSON a "summary.up_to_date" égal au nombre 1
    Et la sortie contient "À jour, rien à faire."
    Et aucune copie de travail temporaire ne reste

  Scénario: Une base qui a avancé sans conflit : faisable, avec la commande
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo check sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demos[0].status" égal à "feasible"
    Et le JSON a "demos[0].behind_base" égal au nombre 1
    Et le JSON a "demos[0].actions[0].command" égal à "jgit demo rebase sprint12"
    Et le JSON a "demos[0].actions[0].reason" égal à "base develop en retard de 1 commit(s)"
    Et la liste JSON "demos[0].conflicts" contient 0 éléments
    Et la sortie contient "Mise à jour faisable sans conflit"
    Et la branche distante "demo/sprint12" est inchangée

  # Le cœur de la demande : qui est concerné. En face du commit qui ne passe
  # plus, le dernier commit qui a touché le fichier, son auteur, sa provenance.
  Scénario: Un conflit avec la base est décrit : ticket, commit, auteurs, commandes
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Quand je lance "jgit demo check sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "demos[0].status" égal à "conflicts"
    Et la liste JSON "demos[0].conflicts" contient 1 éléments
    Et le JSON a "demos[0].conflicts[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "demos[0].conflicts[0].step" égal à "rebase"
    Et le JSON a "demos[0].conflicts[0].commit.subject" égal à "Modifie app.txt pour la feature 1"
    Et le JSON a "demos[0].conflicts[0].commit.author" égal à "jgit tests"
    Et le JSON a "demos[0].conflicts[0].files[0].path" égal à "src/app.txt"
    Et le JSON a "demos[0].conflicts[0].files[0].kind" égal à "both_modified"
    Et le JSON a "demos[0].conflicts[0].files[0].other.author" égal à "Camille"
    Et le JSON a "demos[0].conflicts[0].files[0].other.email" égal à "camille@example.invalid"
    Et le JSON a "demos[0].conflicts[0].files[0].other.subject" égal à "Modifie app.txt dans develop"
    Et le JSON a "demos[0].conflicts[0].files[0].other.origin" égal à "develop"
    Et le JSON a "demos[0].conflicts[0].commands.resolve" égal à "jgit demo rebase sprint12 --on-conflict pause"
    Et le JSON a "demos[0].conflicts[0].commands.drop" égal à "jgit demo drop sprint12 --from feature/TEST-1"
    Et le JSON a "demos[0].actions[0].command" égal à "jgit demo rebase sprint12 --on-conflict pause"
    Et le JSON a "summary.conflicts" égal au nombre 1
    Et la sortie contient "en face : "
    Et la sortie contient "par Camille <camille@example.invalid> (develop)"
    Et la branche distante "demo/sprint12" est inchangée
    Et aucune copie de travail temporaire ne reste

  Scénario: Un conflit entre deux tickets désigne l'autre ticket et son auteur
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de la feature 2" sur la branche "feature/TEST-2" avec le message "Modifie app.txt pour la feature 2"
    Quand je lance "jgit demo check sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "demos[0].conflicts[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].conflicts[0].step" égal à "add"
    Et le JSON a "demos[0].conflicts[0].commit.author" égal à "Camille"
    Et le JSON a "demos[0].conflicts[0].files[0].other.origin" égal à "feature/TEST-1"
    Et le JSON a "demos[0].conflicts[0].files[0].other.author" égal à "jgit tests"
    Et le JSON a "demos[0].conflicts[0].commands.resolve" égal à "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et le JSON a "demos[0].actions[0].command" égal à "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"

  # Un ticket en conflit est écarté et la simulation reprend : tous les tickets
  # fautifs sont signalés, pas seulement le premier.
  Scénario: Tous les conflits sont signalés, pas seulement le premier
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 3 réécrit la 2" avec le message "Touche feature2.txt pour la feature 3"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo add sprint12 --from feature/TEST-3 --on-conflict abort"
    Et "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Et "Dominique" pousse le fichier "src/feature2.txt" contenant "autre version" sur la branche "develop" avec le message "Modifie feature2.txt dans develop"
    Quand je lance "jgit demo check sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et la liste JSON "demos[0].conflicts" contient 2 éléments
    Et le JSON a "demos[0].conflicts[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "demos[0].conflicts[0].files[0].other.author" égal à "Camille"
    Et le JSON a "demos[0].conflicts[1].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].conflicts[1].files[0].other.author" égal à "Dominique"

  Scénario: Un ticket livré sera retiré, et le rapport le dit
    Étant donné la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 (#2)"
    Et la PR de "feature/TEST-2" est livrée dans "develop"
    Quand je lance "jgit demo check sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demos[0].status" égal à "feasible"
    Et le JSON a "demos[0].dropped[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].dropped[0].reason" égal à "delivered"
    Et le JSON a "demos[0].actions[0].reason" qui contient "retire feature/TEST-2 (livré)"

  # La vérification peut tourner n'importe quand : espace de travail modifié,
  # autre branche, pour une IA ou un job planifié.
  Scénario: La vérification ne touche à rien
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Et je modifie le fichier "src/brouillon.txt" avec "en cours"
    Quand je lance "jgit demo check"
    Alors jgit se termine avec le code 3
    Et je suis sur la branche "develop"
    Et le fichier de travail "src/brouillon.txt" contient "en cours"
    Et la branche distante "demo/sprint12" est inchangée
    Et aucune opération jgit n'est en pause
    Et aucune copie de travail temporaire ne reste

  Scénario: Une démo archivée ou à l'ancien format ne se vérifie pas
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo check demo-archive/AUJOURDHUI_sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "read_only"
    Étant donné une démo à l'ancien format "vitrine" basée sur "develop" contient les tickets "feature/TEST-1"
    Quand je lance "jgit demo check --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "demos" contient 0 éléments
    Et le JSON a "summary.skipped_legacy" égal au nombre 1
