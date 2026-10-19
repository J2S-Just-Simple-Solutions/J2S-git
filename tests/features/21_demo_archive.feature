# language: fr
Fonctionnalité: Archiver, restaurer et supprimer une démo
  Archiver une démo la renomme demo-archive/<date>_<nom> : son nom est libéré
  pour une nouvelle démo, et l'ancienne reste consultable et restaurable. Rien
  n'est réécrit, et chaque changement de nom est un seul push atomique.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et je note l'état de la branche distante "demo/sprint12"

  Scénario: Une démo archivée change de nom et libère le sien
    Quand je lance "jgit demo archive sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "archive"
    Et le JSON a "branch" égal à "demo-archive/AUJOURDHUI_sprint12"
    Et le JSON a "previous_branch" égal à "demo/sprint12"
    Et la branche distante "demo/sprint12" n'existe pas
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" existe
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo-archive/AUJOURDHUI_sprint12"
    Et la sortie contient "Pour la reprendre : jgit demo unarchive demo-archive/AUJOURDHUI_sprint12"

  Scénario: Les archives sont à part dans la liste, et se consultent
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo list --json" en lisant le JSON
    Alors la liste JSON "demos" contient 0 éléments
    Et le JSON a "archived_count" égal au nombre 1
    Et la sortie contient "1 démo(s) archivée(s) : jgit demo list --archived"
    Quand je lance "jgit demo list --archived --json" en lisant le JSON
    Alors la liste JSON "demos" contient 1 éléments
    Et le JSON a "demos[0].name" égal à "sprint12"
    Et le JSON a "demos[0].archived" vrai
    Et le JSON a "demos[0].archived_on" égal à "AUJOURDHUI"
    Et le JSON a "demos[0].read_only" vrai
    Quand je lance "jgit demo show demo-archive/AUJOURDHUI_sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[0].ticket" égal à "feature/TEST-1"
    Et la sortie contient "archivée le AUJOURDHUI, lecture seule"

  # Le cas d'usage : remplacer une démo sans perdre la précédente.
  Scénario: Une nouvelle démo peut reprendre le nom d'une démo archivée
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo create sprint12 --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo/sprint12" existe
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" existe

  Scénario: Une seconde archive le même jour porte un numéro
    Étant donné je lance "jgit demo archive sprint12"
    Et je lance "jgit demo create sprint12 --no-interaction"
    Quand je lance "jgit demo archive sprint12"
    Alors jgit se termine sans erreur
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" existe
    Et la branche distante "demo-archive/AUJOURDHUI.2_sprint12" existe

  Scénario: Une démo archivée est en lecture seule
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo add demo-archive/AUJOURDHUI_sprint12 --from feature/TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "archived"
    Et le JSON a "error.hint" égal à "Pour la reprendre : jgit demo unarchive demo-archive/AUJOURDHUI_sprint12"

  Scénario: Une démo absente mais archivée est signalée avec ses archives
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "demo_not_found"
    Et le JSON a "error.hint" qui contient "demo-archive/AUJOURDHUI_sprint12"

  Scénario: Une archive se restaure sous son nom
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo unarchive sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "unarchive"
    Et le JSON a "branch" égal à "demo/sprint12"
    Et la branche distante "demo/sprint12" est inchangée
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" n'existe pas

  Scénario: Plusieurs archives du même nom demandent de préciser laquelle
    Étant donné je lance "jgit demo archive sprint12"
    Et je lance "jgit demo create sprint12 --no-interaction"
    Et je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo unarchive sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "ambiguous"
    Et le JSON a "error.hint" qui contient "jgit demo unarchive demo-archive/AUJOURDHUI_sprint12"
    Et le JSON a "error.hint" qui contient "jgit demo unarchive demo-archive/AUJOURDHUI.2_sprint12"
    Quand je lance "jgit demo unarchive AUJOURDHUI_sprint12"
    Alors jgit se termine sans erreur
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Une archive ne prend pas la place d'une démo active
    Étant donné je lance "jgit demo archive sprint12"
    Et je lance "jgit demo create sprint12 --no-interaction"
    Quand je lance "jgit demo unarchive demo-archive/AUJOURDHUI_sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "already_exists"
    Et le JSON a "error.hint" égal à "Archivez d'abord la démo actuelle : jgit demo archive sprint12"
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" existe

  Scénario: --dry-run annonce l'archive sans rien changer
    Quand je lance "jgit demo archive sprint12 --dry-run --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dry_run" vrai
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: La copie locale identique disparaît avec l'archivage
    Étant donné je récupère la branche distante "demo/sprint12" en local
    Quand je lance "jgit demo archive sprint12"
    Alors jgit se termine sans erreur
    Et la branche locale "demo/sprint12" n'existe pas

  Scénario: Une copie locale porteuse de commits non publiés est conservée
    Étant donné je récupère la branche distante "demo/sprint12" en local
    Et je me place sur la branche "demo/sprint12"
    Et je commite le fichier "src/local.txt" contenant "local" avec le message "Travail local sur la démo"
    Et je me place sur la branche "develop"
    Quand je lance "jgit demo archive sprint12"
    Alors jgit se termine sans erreur
    Et la branche locale "demo/sprint12" existe
    Et la sortie contient "porte des commits absents du serveur : elle est conservée."

  # --- demo delete -----------------------------------------------------------

  Scénario: Une démo est supprimée après confirmation
    Quand je lance "jgit demo delete sprint12" et que je réponds aux questions :
      | Confirmez-vous la suppression | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "Pour la garder consultable, archivez-la plutôt : jgit demo archive sprint12"
    Et la branche distante "demo/sprint12" n'existe pas

  Scénario: Refuser la suppression conserve la démo
    Quand je lance "jgit demo delete sprint12" et que je réponds aux questions :
      | Confirmez-vous la suppression | n |
    Alors jgit se termine en erreur
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Une archive se supprime aussi
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit demo delete demo-archive/AUJOURDHUI_sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "delete"
    Et la branche distante "demo-archive/AUJOURDHUI_sprint12" n'existe pas

  Scénario: Supprimer une démo inconnue est refusé
    Quand je lance "jgit demo delete inconnue --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "demo_not_found"
