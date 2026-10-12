# language: fr
Fonctionnalité: Les conflits d'une démo, mis en pause, résolus et réutilisés
  Une démo assemble des tickets qui n'ont pas été écrits ensemble : ils
  peuvent se marcher dessus. La fabrication passe par le même moteur que le
  rebase d'une feature : --on-conflict pause s'arrête sur le conflit, « demo
  continue » reprend, « demo abort » annule. La résolution est un commit de la
  démo : les reconstructions suivantes la rejouent sans la redemander.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature 1" avec le message "Modifie app.txt pour la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature 2" avec le message "Modifie app.txt pour la feature 2"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-3 --from feature/TEST-1 --no-interaction"
    Et je note l'état de la branche distante "demo/sprint12"

  Scénario: Le conflit est mis en pause et décrit
    Quand je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "schema" égal à "jgit.conflict/1"
    Et le JSON a "paused" vrai
    Et le JSON a "operation" égal à "demo_add"
    Et le JSON a "target" égal à "demo/sprint12"
    Et le JSON a "branch" égal à "jgit_demo_sprint12"
    Et le JSON a "context.demo" égal à "sprint12"
    Et le JSON a "context.ticket" égal à "feature/TEST-2"
    Et le JSON a "commit.subject" égal à "Modifie app.txt pour la feature 2"
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et le JSON a "commands.continue" égal à "jgit demo continue sprint12"
    Et le JSON a "commands.abort" égal à "jgit demo abort sprint12"
    Et une opération jgit est en pause
    Et je suis sur la branche "jgit_demo_sprint12"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Une fois résolu, continue termine et publie la démo
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et je résous le conflit du fichier "src/app.txt" avec "versions 1 et 2 réunies"
    Quand je lance "jgit demo continue sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.result/1"
    Et le JSON a "added[0]" égal à "feature/TEST-2"
    Et aucune opération jgit n'est en pause
    Et je suis sur la branche "develop"
    Et la branche locale "jgit_demo_sprint12" n'existe pas
    Et le fichier "src/app.txt" de la branche distante "demo/sprint12" contient "versions 1 et 2 réunies"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-3 |
      | feature/TEST-1 |
      | feature/TEST-2 |
    # La résolution garde l'empreinte du commit : le ticket est reconnu à jour.
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "tickets[ticket=feature/TEST-2].status" égal à "up_to_date"

  # Le gain du modèle : la résolution est dans la démo. Retirer un ticket placé
  # avant, ou rebaser sur une base qui a avancé, la rejoue sans conflit.
  Scénario: Une résolution déjà faite est rejouée par les reconstructions suivantes
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et je résous le conflit du fichier "src/app.txt" avec "versions 1 et 2 réunies"
    Et je lance "jgit demo continue sprint12"
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-3 --on-conflict pause --no-interaction"
    Alors jgit se termine sans erreur
    Et aucune opération jgit n'est en pause
    Et le fichier "src/app.txt" de la branche distante "demo/sprint12" contient "versions 1 et 2 réunies"
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo rebase sprint12 --on-conflict pause --no-interaction"
    Alors jgit se termine sans erreur
    Et aucune opération jgit n'est en pause
    Et le fichier "src/app.txt" de la branche distante "demo/sprint12" contient "versions 1 et 2 réunies"
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo/sprint12"

  Scénario: abort annule tout, sans rien avoir publié
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Quand je lance "jgit demo abort sprint12"
    Alors jgit se termine sans erreur
    Et la sortie contient "L'opération sur la démo demo/sprint12 a été annulée : rien n'a été poussé."
    Et aucune opération jgit n'est en pause
    Et je suis sur la branche "develop"
    Et la branche locale "jgit_demo_sprint12" n'existe pas
    Et la branche distante "demo/sprint12" est inchangée
    Et l'espace de travail est propre

  Scénario: Reprendre sans avoir résolu laisse la démo en pause
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Quand je lance "jgit demo continue sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "error.code" égal à "unresolved_files"
    Et le JSON a "context.ticket" égal à "feature/TEST-2"
    Et une opération jgit est en pause

  # C'est la conduite de Jenkins : sans interaction, un conflit annule tout et
  # le document décrit le conflit pour la notification.
  Scénario: Sans interaction, le conflit est abandonné et décrit
    Quand je lance "jgit demo add sprint12 --from feature/TEST-2 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "schema" égal à "jgit.conflict/1"
    Et le JSON a "paused" faux
    Et le JSON a "context.ticket" égal à "feature/TEST-2"
    Et le JSON a "conflicted_files[0].path" égal à "src/app.txt"
    Et aucune opération jgit n'est en pause
    Et je suis sur la branche "develop"
    Et la branche locale "jgit_demo_sprint12" n'existe pas
    Et la branche distante "demo/sprint12" est inchangée

  # Lire ne touche pas à l'espace de travail : on peut regarder les démos
  # pendant qu'un conflit attend. Tout le reste attend la fin de l'opération.
  Scénario: Pendant la pause, on peut lire mais pas modifier
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Quand je lance "jgit demo list --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demos[name=sprint12].operation_in_progress" vrai
    Quand je lance "jgit demo show sprint12"
    Alors jgit se termine sans erreur
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 5
    Et le JSON a "error.code" égal à "operation_in_progress"
    Et le JSON a "error.hint" qui contient "jgit demo continue sprint12"

  Scénario: Un collègue a modifié la démo pendant la pause : rien n'est écrasé
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Et je note l'état de la branche distante "demo/sprint12"
    Et je résous le conflit du fichier "src/app.txt" avec "versions 1 et 2 réunies"
    Quand je lance "jgit demo continue sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 4
    Et le JSON a "error.code" égal à "lease_rejected"
    Et la branche distante "demo/sprint12" est inchangée
    Et le fichier "src/rustine.txt" existe sur la branche distante "demo/sprint12"
    Et aucune opération jgit n'est en pause
    Et je suis sur la branche "develop"

  Scénario: Reprendre une autre démo que celle en pause est refusé
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Quand je lance "jgit demo continue autre --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "operation_mismatch"
    Et une opération jgit est en pause

  # Quelqu'un — un collègue, une IA, l'interface — qui arrive au milieu doit
  # pouvoir savoir ce qui attend, sans rien toucher.
  Scénario: util status décrit l'opération en pause
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Quand je lance "jgit util status --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.status/1"
    Et le JSON a "current_branch" égal à "jgit_demo_sprint12"
    Et le JSON a "operation_in_progress.operation" égal à "demo_add"
    Et le JSON a "operation_in_progress.target" égal à "demo/sprint12"
    Et le JSON a "operation_in_progress.context.ticket" égal à "feature/TEST-2"
    Et le JSON a "operation_in_progress.commit.subject" égal à "Modifie app.txt pour la feature 2"
    Et le JSON a "operation_in_progress.conflicted_files[0].path" égal à "src/app.txt"
    Et le JSON a "operation_in_progress.commands.continue" égal à "jgit demo continue sprint12"
    Et la sortie contient "Une opération attend la résolution d'un conflit"
    Et une opération jgit est en pause

  Scénario: util status sans rien en pause
    Quand je lance "jgit util status --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation_in_progress" nul
    Et le JSON a "current_branch" égal à "develop"
    Et la sortie contient "Aucune opération jgit en pause."
