# language: fr
Fonctionnalité: L'état des lieux des tickets et des démos
  « jgit audit » fait l'état des lieux de tous les tickets du serveur, puis de
  toutes les démos, et dit ce qu'il faut lancer, dans l'ordre, et qui est
  concerné.

  Pour chaque ticket : est-il à jour sur sa base ? Sinon, son rebase passe-t-il ?
  Comme jgit feature rebase, seuls ses propres commits comptent. Le rapport dit
  qui doit intervenir et quoi lancer ; le détail (commits, fichiers, et en face
  le commit de la base) est dans --json.

  Pour chaque démo : d'abord rebaser ses tickets en retard, chez eux (c'est là
  que leurs conflits avec la base se résolvent, par leur auteur), puis remettre
  la démo à jour, en reprenant depuis leur branche les tickets qui le
  demandent. Les conflits qui restent dans la démo sont ceux entre tickets.

  Tout est simulé : rien n'est modifié, ni chez soi, ni sur le serveur.

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

  Scénario: Tout est à jour : rien à faire
    Quand je lance "jgit audit --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.audit/1"
    Et le JSON a "scope" égal à "all"
    Et la liste JSON "tickets" contient 2 éléments
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "up_to_date"
    Et le JSON a "tickets[ticket=feature/TEST-1].base" égal à "develop"
    Et le JSON a "tickets[ticket=feature/TEST-1].base_source" égal à "recorded"
    Et le JSON a "tickets[ticket=feature/TEST-1].owner.author" égal à "jgit tests"
    Et le JSON a "tickets[ticket=feature/TEST-1].pr_validated" faux
    Et le JSON a "tickets[ticket=feature/TEST-1].pr_title" nul
    Et la liste JSON "tickets[ticket=feature/TEST-1].concerned" contient 0 éléments
    Et le JSON a "tickets[ticket=feature/TEST-1].command" nul
    Et le JSON a "tickets[ticket=feature/TEST-1].demos[0]" égal à "sprint12"
    Et le JSON a "demos[0].name" égal à "sprint12"
    Et le JSON a "demos[0].status" égal à "up_to_date"
    Et la liste JSON "demos[0].actions" contient 0 éléments
    Et le JSON a "summary.tickets.up_to_date" égal au nombre 2
    Et le JSON a "summary.demos.up_to_date" égal au nombre 1
    Et la sortie contient "À jour, rien à faire."
    Et aucune copie de travail temporaire ne reste

  Scénario: La base a avancé sans conflit : les tickets d'abord, chez eux, puis la démo
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit audit demos sprint12 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "scope" égal à "demos"
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "to_rebase"
    Et le JSON a "tickets[ticket=feature/TEST-1].behind_base" égal au nombre 1
    Et le JSON a "tickets[ticket=feature/TEST-1].command" égal à "jgit feature rebase TEST-1"
    Et le JSON a "tickets[ticket=feature/TEST-1].concerned[0].author" égal à "jgit tests"
    Et le JSON a "demos[0].status" égal à "feasible"
    Et le JSON a "demos[0].behind_base" égal au nombre 1
    Et la liste JSON "demos[0].prerequisites" contient 2 éléments
    Et le JSON a "demos[0].actions[0].kind" égal à "ticket"
    Et le JSON a "demos[0].actions[0].command" égal à "jgit feature rebase TEST-1"
    Et le JSON a "demos[0].actions[1].command" égal à "jgit feature rebase TEST-2"
    Et le JSON a "demos[0].actions[2].kind" égal à "demo"
    Et le JSON a "demos[0].actions[2].command" égal à "jgit demo rebase sprint12"
    Et le JSON a "demos[0].actions[2].reason" égal à "base develop en retard de 1 commit(s)"
    Et la liste JSON "demos[0].conflicts" contient 0 éléments
    Et la sortie contient "Mise à jour faisable sans conflit"
    Et la sortie contient "d'abord rebaser le ticket chez lui"
    Et la branche distante "demo/sprint12" est inchangée

  # Le cœur de la demande : qui doit intervenir. Le rapport le dit ; le JSON
  # garde le détail : le commit qui ne passe plus et, en face, le dernier
  # commit de la base qui a touché le fichier, et son auteur.
  Scénario: Le rebase d'un ticket sur sa base coince : qui doit intervenir, et le détail
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Quand je lance "jgit audit --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "conflicts"
    Et le JSON a "tickets[ticket=feature/TEST-1].command" égal à "jgit feature rebase TEST-1 --on-conflict pause"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.commit.subject" égal à "Modifie app.txt pour la feature 1"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.commit.author" égal à "jgit tests"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].path" égal à "src/app.txt"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].kind" égal à "both_modified"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].other.author" égal à "Camille"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].other.email" égal à "camille@example.invalid"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].other.subject" égal à "Modifie app.txt dans develop"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].other.origin" égal à "develop"
    Et le JSON a "tickets[ticket=feature/TEST-1].concerned[0].author" égal à "jgit tests"
    Et le JSON a "tickets[ticket=feature/TEST-2].status" égal à "to_rebase"
    Et le JSON a "summary.tickets.conflicts" égal au nombre 1
    Et le JSON a "demos[0].status" égal à "conflicts"
    Et le JSON a "demos[0].held[0]" égal à "feature/TEST-1"
    Et le JSON a "demos[0].prerequisites[0].command" égal à "jgit feature rebase TEST-1 --on-conflict pause"
    Et le JSON a "demos[0].actions[2].command" égal à "jgit demo rebase sprint12 --from feature/TEST-1"
    Et la liste JSON "demos[0].conflicts" contient 0 éléments
    Et la sortie contient "feature/TEST-1 — en retard de 1 commit(s) sur develop : son rebase coince"
    Et la sortie contient "à faire par : jgit tests"
    Et la sortie contient "→ jgit feature rebase TEST-1 --on-conflict pause   (démos : sprint12)"
    Et la branche distante "demo/sprint12" est inchangée
    Et aucune copie de travail temporaire ne reste

  # Seuls ceux dont les commits touchent les fichiers en conflit sont appelés,
  # pas tous ceux qui ont travaillé sur la branche.
  Scénario: Ne doivent intervenir que les auteurs des commits en conflit
    Étant donné "Dominique" pousse le fichier "src/notes.txt" contenant "notes" sur la branche "feature/TEST-1" avec le message "Ajoute des notes"
    Et "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Quand je lance "jgit audit tickets --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "conflicts"
    Et le JSON a "tickets[ticket=feature/TEST-1].owner.author" égal à "Dominique"
    Et la liste JSON "tickets[ticket=feature/TEST-1].concerned" contient 1 éléments
    Et le JSON a "tickets[ticket=feature/TEST-1].concerned[0].author" égal à "jgit tests"
    Et le JSON a "tickets[ticket=feature/TEST-1].conflict.files[0].path" égal à "src/app.txt"
    # Le rapport dit qui, pas le détail des fichiers et des commits.
    Quand je lance "jgit audit tickets"
    Alors jgit se termine avec le code 3
    Et la sortie contient "à faire par : jgit tests"
    Et la sortie ne contient pas "Dominique"
    Et la sortie ne contient pas "src/app.txt"
    Et la sortie ne contient pas "Camille"

  Scénario: Le titre de la PR accompagne le ticket
    Étant donné la PR de "feature/TEST-1" s'intitule "TEST-1 - Affiche le total TTC" sur GitHub
    Et "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Quand je lance "jgit audit tickets --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "tickets[ticket=feature/TEST-1].pr_title" égal à "Affiche le total TTC"
    Et le JSON a "tickets[ticket=feature/TEST-2].pr_title" nul
    Et la sortie contient "✖ feature/TEST-1 — en retard de 1 commit(s) sur develop : son rebase coince"
    Et la sortie contient "« Affiche le total TTC »"
    Et GitHub a reçu "pr list --state open --limit 1000 --json headRefName,title"

  # Un ticket créé avant que jgit enregistre la branche d'origine : rebaser
  # sur la préprod un ticket parti d'une branche de projet n'aurait pas de sens.
  # Sa base est supposée — la base connue dont il s'écarte le moins — et donnée
  # explicitement à la commande, que jgit feature rebase prendrait sinon sur
  # la préprod.
  Scénario: Un ancien ticket sans base enregistrée : sa base est supposée
    Étant donné je crée la branche locale "ripolin" depuis "develop"
    Et je me place sur la branche "ripolin"
    Et je commite le fichier "src/ripolin.txt" contenant "socle ripolin" avec le message "Socle ripolin"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create vitrine --based-on ripolin --no-interaction"
    Et un ancien ticket "feature/ANC-1" parti de "ripolin", sans branche d'origine enregistrée, ajoute le fichier "src/ancien.txt" contenant "ancien"
    Et "Camille" pousse le fichier "src/ripolin.txt" contenant "autre version" sur la branche "develop" avec le message "Crée ripolin.txt dans develop"
    Et "Dominique" pousse le fichier "src/ripolin2.txt" contenant "suite" sur la branche "ripolin" avec le message "Suite de ripolin"
    Quand je lance "jgit audit tickets --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[ticket=feature/ANC-1].base" égal à "ripolin"
    Et le JSON a "tickets[ticket=feature/ANC-1].base_source" égal à "inferred"
    Et le JSON a "tickets[ticket=feature/ANC-1].status" égal à "to_rebase"
    Et le JSON a "tickets[ticket=feature/ANC-1].behind_base" égal au nombre 1
    Et le JSON a "tickets[ticket=feature/ANC-1].command" égal à "jgit feature rebase ANC-1 --based-on ripolin"
    Et la sortie contient "3 autre(s) ticket(s) en retard sur leur base"
    Quand je lance "jgit feature rebase ANC-1 --based-on ripolin --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/ripolin2.txt" existe sur la branche distante "feature/ANC-1"
    Et le fichier "src/ripolin.txt" de la branche distante "feature/ANC-1" contient "socle ripolin"

  # Une branche que jgit n'a pas créée n'a pas de commit d'init : rien ne dit
  # quels commits sont les siens, jgit feature rebase ne saurait pas la rebaser.
  Scénario: Un ticket sans commit d'init est signalé, à rebaser à la main
    Étant donné je crée la branche locale "feature/fait-main" depuis "develop"
    Et je me place sur la branche "feature/fait-main"
    Et je commite le fichier "src/main.txt" contenant "à la main" avec le message "Travail fait à la main"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit audit tickets --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "tickets[ticket=feature/fait-main].status" égal à "no_init"
    Et le JSON a "tickets[ticket=feature/fait-main].command" nul
    Et le JSON a "summary.tickets.no_init" égal au nombre 1
    Et la sortie contient "1 autre(s) ticket(s) en retard, sans commit d'init : à rebaser à la main"
    Et la sortie contient "à faire par : jgit tests (1)"

  # « D'abord on rebase la branche elle-même » : son auteur y résout le
  # conflit, puis la démo reprend cette version résolue depuis la branche.
  Scénario: Une fois le ticket rebasé par son auteur, la démo reprend sa version résolue
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Et je lance "jgit feature rebase TEST-1 --on-conflict pause"
    Et je résous le conflit du fichier "src/app.txt" avec "feature 1 sur develop"
    Et je lance "jgit feature continue TEST-1"
    Et je lance "jgit feature rebase TEST-2 --no-interaction"
    Quand je lance "jgit audit demos --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "up_to_date"
    Et le JSON a "demos[0].status" égal à "feasible"
    Et la liste JSON "demos[0].prerequisites" contient 0 éléments
    Et le JSON a "demos[0].actions[0].command" égal à "jgit demo rebase sprint12 --from feature/TEST-1"
    Et le JSON a "demos[0].actions[0].reason" égal à "base develop en retard de 1 commit(s) ; reprend feature/TEST-1 depuis leur branche"
    Quand je lance "jgit demo rebase sprint12 --from feature/TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/app.txt" de la branche distante "demo/sprint12" contient "feature 1 sur develop"

  Scénario: Un conflit entre deux tickets se résout dans la démo, et désigne l'autre ticket
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de la feature 2" sur la branche "feature/TEST-2" avec le message "Modifie app.txt pour la feature 2"
    Quand je lance "jgit audit demos sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "tickets[ticket=feature/TEST-2].status" égal à "up_to_date"
    Et le JSON a "demos[0].conflicts[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].conflicts[0].step" égal à "add"
    Et le JSON a "demos[0].conflicts[0].commit.author" égal à "Camille"
    Et le JSON a "demos[0].conflicts[0].files[0].other.origin" égal à "feature/TEST-1"
    Et le JSON a "demos[0].conflicts[0].files[0].other.author" égal à "jgit tests"
    Et le JSON a "demos[0].conflicts[0].commands.resolve" égal à "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et le JSON a "demos[0].conflicts[0].commands.drop" égal à "jgit demo drop sprint12 --from feature/TEST-2"
    Et le JSON a "demos[0].actions[0].command" égal à "jgit demo add sprint12 --from feature/TEST-2 --on-conflict pause"
    Et la sortie contient "✖ Conflit : feature/TEST-2 (à l'ajout de ses nouveaux commits)"
    Et la sortie contient "concerne : Camille (feature/TEST-2), jgit tests (feature/TEST-1)"

  # Un ticket en conflit est écarté et la simulation reprend : tous les tickets
  # fautifs sont signalés, pas seulement le premier.
  Scénario: Tous les conflits d'une démo sont signalés, pas seulement le premier
    Étant donné "Dominique" pousse le fichier "src/feature2.txt" contenant "la 1 touche la 2" sur la branche "feature/TEST-1" avec le message "Touche feature2.txt depuis la feature 1"
    Et "Camille" pousse le fichier "src/app.txt" contenant "version de la feature 2" sur la branche "feature/TEST-2" avec le message "Modifie app.txt pour la feature 2"
    Quand je lance "jgit audit demos --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et la liste JSON "demos[0].conflicts" contient 2 éléments
    Et le JSON a "demos[0].conflicts[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "demos[0].conflicts[0].commit.author" égal à "Dominique"
    Et le JSON a "demos[0].conflicts[0].files[0].other.origin" égal à "feature/TEST-2"
    Et le JSON a "demos[0].conflicts[1].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].conflicts[1].commit.author" égal à "Camille"
    Et le JSON a "demos[0].conflicts[1].files[0].other.origin" égal à "feature/TEST-1"

  # Sur un vrai projet, des centaines de tickets : le rapport détaille ce qui
  # coince et les tickets des démos, et compte les autres par propriétaire.
  Scénario: Tous les tickets du serveur sont audités, même hors des démos
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/feature3.txt" contenant "feature 3" avec le message "Ajoute la feature 3"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "la 4 aussi" avec le message "Crée feature2.txt pour la feature 4"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et "Dominique" pousse le fichier "src/feature2.txt" contenant "autre version" sur la branche "develop" avec le message "Crée feature2.txt dans develop"
    Quand je lance "jgit audit --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et la liste JSON "tickets" contient 4 éléments
    Et le JSON a "tickets[ticket=feature/TEST-2].status" égal à "conflicts"
    Et le JSON a "tickets[ticket=feature/TEST-4].status" égal à "conflicts"
    Et le JSON a "tickets[ticket=feature/TEST-4].conflict.files[0].kind" égal à "both_added"
    Et le JSON a "tickets[ticket=feature/TEST-4].conflict.files[0].other.author" égal à "Dominique"
    Et la liste JSON "tickets[ticket=feature/TEST-4].demos" contient 0 éléments
    Et le JSON a "tickets[ticket=feature/TEST-3].status" égal à "to_rebase"
    Et le JSON a "summary.tickets.conflicts" égal au nombre 2
    Et le JSON a "summary.tickets.to_rebase" égal au nombre 2
    Et la sortie contient "TICKETS (4)"
    Et la sortie contient "✖ feature/TEST-4"
    Et la sortie contient "↻ feature/TEST-1"
    Et la sortie contient "1 autre(s) ticket(s) en retard sur leur base, rebase sans conflit"
    Et la sortie contient "à faire par : jgit tests (1)"

  Scénario: Un ticket dont la base a disparu est signalé
    Étant donné je crée la branche locale "release/9.9" depuis "develop"
    Et je me place sur la branche "release/9.9"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-5 --based-on release/9.9 --no-interaction --no-open"
    Et je commite le fichier "src/feature5.txt" contenant "feature 5" avec le message "Ajoute la feature 5"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et la branche "release/9.9" est supprimée sur GitHub
    Quand je lance "jgit audit tickets --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et le JSON a "scope" égal à "tickets"
    Et la liste JSON "demos" contient 0 éléments
    Et le JSON a "tickets[ticket=feature/TEST-5].status" égal à "base_missing"
    Et le JSON a "tickets[ticket=feature/TEST-5].base" égal à "release/9.9"
    Et le JSON a "tickets[ticket=feature/TEST-5].command" égal à "jgit feature rebase TEST-5 --based-on <branche>"
    Et le JSON a "summary.tickets.base_missing" égal au nombre 1
    Et la sortie contient "sa base release/9.9 n'existe plus"
    Et la sortie ne contient pas "DÉMOS"

  Scénario: Un ticket livré sera retiré de la démo, et l'audit le dit
    Étant donné la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 (#2)"
    Et la PR de "feature/TEST-2" est livrée dans "develop"
    Quand je lance "jgit audit --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "tickets[ticket=feature/TEST-2].status" égal à "delivered"
    Et le JSON a "tickets[ticket=feature/TEST-2].delivered" vrai
    Et le JSON a "demos[0].status" égal à "feasible"
    Et le JSON a "demos[0].dropped[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "demos[0].dropped[0].reason" égal à "delivered"
    Et le JSON a "demos[0].actions[1].command" égal à "jgit demo rebase sprint12"
    Et le JSON a "demos[0].actions[1].reason" qui contient "retire feature/TEST-2 (livré)"

  # L'audit peut tourner n'importe quand : espace de travail modifié, autre
  # branche, pour une IA ou un job planifié.
  Scénario: L'audit ne touche à rien
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Et je modifie le fichier "src/brouillon.txt" avec "en cours"
    Quand je lance "jgit audit"
    Alors jgit se termine avec le code 3
    Et je suis sur la branche "develop"
    Et le fichier de travail "src/brouillon.txt" contient "en cours"
    Et la branche distante "demo/sprint12" est inchangée
    Et aucune opération jgit n'est en pause
    Et aucune copie de travail temporaire ne reste

  Scénario: Une démo archivée ou à l'ancien format n'est pas auditée
    Étant donné je lance "jgit demo archive sprint12"
    Quand je lance "jgit audit demos demo-archive/AUJOURDHUI_sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "read_only"
    Étant donné une démo à l'ancien format "vitrine" basée sur "develop" contient les tickets "feature/TEST-1"
    Quand je lance "jgit audit demos --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "demos" contient 0 éléments
    Et le JSON a "summary.demos.skipped_legacy" égal au nombre 1

  Scénario: Les arguments de jgit audit sont vérifiés
    Quand je lance "jgit audit partout --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Quand je lance "jgit audit tickets sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Quand je lance "jgit audit demos inconnue --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "demo_not_found"
