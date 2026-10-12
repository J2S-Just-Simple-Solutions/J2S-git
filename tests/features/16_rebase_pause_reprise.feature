# language: fr
Fonctionnalité: Un conflit de rebase mis en pause, résolu, puis repris
  Face à un conflit, --on-conflict choisit la conduite : ask (défaut en
  interactif) attend que le développeur ait résolu et commité ; abort (défaut
  sans interaction) annule tout ; pause s'arrête en laissant le conflit à
  résoudre, pour qu'un humain ou une IA le règle puis reprenne avec
  « jgit feature continue ». Rien n'est poussé tant que le rebase n'est pas
  terminé, et rien n'écrase un collègue qui aurait poussé entre-temps.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature" avec le message "Modifie app.txt côté feature"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt côté develop"
    Et je note l'état de la branche distante "feature/TEST-1"
    Et je note l'état de la branche distante "__PR__feature/TEST-1"

  Scénario: Le conflit est mis en pause et décrit
    Quand je lance "jgit feature rebase TEST-1 --on-conflict pause --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et la sortie standard est un unique document JSON
    Et le JSON a "schema" égal à "jgit.conflict/1"
    Et le JSON a "ok" faux
    Et le JSON a "paused" vrai
    Et le JSON a "operation" égal à "feature_rebase"
    Et le JSON a "target" égal à "feature/TEST-1"
    Et le JSON a "error.code" égal à "conflict"
    Et le JSON a "error.exit_code" égal au nombre 3
    Et le JSON a "branch" égal à "jgit_rebase_feature/TEST-1"
    Et le JSON a "commit.subject" égal à "Modifie app.txt côté feature"
    Et la liste JSON "conflicted_files" contient 1 éléments
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et le JSON a "conflicted_files[0].kind" égal à "both_modified"
    Et le JSON a "progress.done" égal au nombre 2
    Et le JSON a "progress.total" égal au nombre 3
    Et le JSON a "commands.continue" égal à "jgit feature continue TEST-1"
    Et le JSON a "commands.abort" égal à "jgit feature abort TEST-1"
    Et la sortie contient "L'opération est en pause : rien n'a été poussé."
    Et une opération jgit est en pause
    Et je suis sur la branche "jgit_rebase_feature/TEST-1"
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "__PR__feature/TEST-1" est inchangée

  Scénario: Une fois le conflit résolu, continue termine et publie le rebase
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Et je résous le conflit du fichier "src/app.txt" avec "version résolue"
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la sortie standard est un unique document JSON
    Et le JSON a "ok" vrai
    Et la sortie contient "Rebase terminé avec succès"
    Et aucune opération jgit n'est en pause
    Et je suis sur la branche "feature/TEST-1"
    Et le fichier "src/app.txt" de la branche distante "feature/TEST-1" contient "version résolue"
    Et l'historique de "feature/TEST-1" contient "Modifie app.txt côté develop"
    Et l'historique de "feature/TEST-1" contient "Modifie app.txt côté feature"
    Et l'historique de "__PR__feature/TEST-1" contient "Modifie app.txt côté develop"
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas
    Et la branche locale "jgit_rebase___PR__feature/TEST-1" n'existe pas

  Scénario: Plusieurs conflits successifs se reprennent l'un après l'autre
    Étant donné je me place sur la branche "feature/TEST-1"
    Et je commite le fichier "src/app.txt" contenant "version 2 de la feature" avec le message "Modifie encore app.txt"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-1"
    Et je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Et je résous le conflit du fichier "src/app.txt" avec "première résolution"
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "commit.subject" égal à "Modifie encore app.txt"
    Et le JSON a "progress.done" égal au nombre 3
    Et une opération jgit est en pause
    Et la branche distante "feature/TEST-1" est inchangée
    Quand je résous le conflit du fichier "src/app.txt" avec "seconde résolution"
    Et je lance "jgit feature continue TEST-1"
    Alors jgit se termine sans erreur
    Et aucune opération jgit n'est en pause
    Et le fichier "src/app.txt" de la branche distante "feature/TEST-1" contient "seconde résolution"
    Et l'historique de "feature/TEST-1" contient "Modifie encore app.txt"

  Scénario: Reprendre sans avoir résolu laisse l'opération en pause
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "error.code" égal à "unresolved_files"
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et la sortie contient "Des fichiers sont encore en conflit"
    Et une opération jgit est en pause
    Et la branche distante "feature/TEST-1" est inchangée

  Scénario: Des marqueurs de conflit marqués résolus sont refusés
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Et je marque le fichier "src/app.txt" résolu sans retirer les marqueurs
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "error.code" égal à "conflict_markers_left"
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et le JSON a "conflicted_files[0].kind" égal à "conflict_markers"
    Et une opération jgit est en pause
    Et la branche distante "feature/TEST-1" est inchangée

  Scénario: abort annule tout, sans rien avoir poussé
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Quand je lance "jgit feature abort TEST-1"
    Alors jgit se termine sans erreur
    Et la sortie contient "Le rebase a été annulé, l'état local est restauré et le remote n'a pas été modifié."
    Et aucune opération jgit n'est en pause
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "__PR__feature/TEST-1" est inchangée
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas
    Et la branche locale "jgit_rebase___PR__feature/TEST-1" n'existe pas
    Et l'historique local de "feature/TEST-1" ne contient pas "Modifie app.txt côté develop"
    Et l'espace de travail est propre

  # L'opération en pause occupe l'espace de travail : la moindre bascule de
  # branche la détruirait. Tout le reste est refusé, en rappelant les issues.
  Scénario: Tant qu'une opération est en pause, les autres commandes refusent
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Quand je lance "jgit feature start TEST-2 --no-open --json" en lisant le JSON
    Alors jgit se termine avec le code 5
    Et le JSON a "error.code" égal à "operation_in_progress"
    Et le JSON a "error.hint" qui contient "jgit feature continue TEST-1"
    Et le JSON a "error.hint" qui contient "jgit feature abort TEST-1"
    Et la branche distante "feature/TEST-2" n'existe pas
    Quand je lance "jgit util clean"
    Alors jgit se termine avec le code 5
    Et la branche locale "jgit_rebase_feature/TEST-1" existe
    Et une opération jgit est en pause

  Scénario: Reprendre alors que rien n'est en pause est refusé
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "no_operation_in_progress"

  Scénario: Reprendre un autre ticket que celui en pause est refusé
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Quand je lance "jgit feature continue TEST-9 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "operation_mismatch"
    Et le JSON a "error.hint" qui contient "jgit feature continue TEST-1"
    Et une opération jgit est en pause

  # Le rebase a lu la version serveur au départ. Si un collègue pousse pendant
  # que le conflit se résout, son travail n'est jamais écrasé.
  Scénario: Un collègue a poussé pendant la pause : rien n'est écrasé
    Étant donné je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Et un autre développeur pousse le fichier "src/collegue.txt" contenant "travail du collègue" sur la branche "feature/TEST-1" avec le message "Travail du collègue"
    Et je note l'état de la branche distante "feature/TEST-1"
    Et je résous le conflit du fichier "src/app.txt" avec "version résolue"
    Quand je lance "jgit feature continue TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 4
    Et le JSON a "error.code" égal à "lease_rejected"
    Et le JSON a "error.hint" qui contient "jgit feature rebase TEST-1"
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "__PR__feature/TEST-1" est inchangée
    Et le fichier "src/collegue.txt" existe sur la branche distante "feature/TEST-1"
    Et aucune opération jgit n'est en pause
    Et l'historique local de "feature/TEST-1" ne contient pas "Modifie app.txt côté develop"

  # C'est la conduite de Jenkins : sans interaction, un conflit annule tout, et
  # le document décrit le conflit pour la notification.
  Scénario: Sans interaction, le conflit est abandonné et décrit
    Quand je lance "jgit feature rebase TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "schema" égal à "jgit.conflict/1"
    Et le JSON a "paused" faux
    Et le JSON a "error.code" égal à "conflict"
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et le JSON a "commands" nul
    Et aucune opération jgit n'est en pause
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche locale "jgit_rebase_feature/TEST-1" n'existe pas

  Scénario: Une valeur inconnue pour --on-conflict est refusée
    Quand je lance "jgit feature rebase TEST-1 --on-conflict peut-etre --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Et le JSON a "error.hint" égal à "Valeurs acceptées : ask, abort, pause."
    Et la branche distante "feature/TEST-1" est inchangée
