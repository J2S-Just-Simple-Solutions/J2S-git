# language: fr
Fonctionnalité: Rebase d'une feature sur sa branche de référence
  Le rebase rejoue en cherry-pick les commits de la branche __PR__ puis ceux de
  la branche de travail au-dessus de la référence remise à jour, puis pousse les
  deux branches en force. Tant que l'utilisateur n'a pas confirmé, le remote
  reste intact.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Une feature est rebasée sur une develop qui a avancé
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je commite le fichier "src/b.txt" contenant "B" avec le message "Commit B"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré en préprod" sur la branche "develop" avec le message "Livraison concurrente en préprod"
    Quand je lance "jgit feature rebase TEST-1" et que je réponds aux questions :
      | Souhaitez-vous continuer                   | y |
      | Confirmez-vous que le rebase                | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "Rebase terminé avec succès"
    Et je suis sur la branche "feature/TEST-1"
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/preprod.txt" existe sur la branche distante "__PR__feature/TEST-1"
    Et le fichier "src/a.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/b.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/a.txt" n'existe pas sur la branche distante "__PR__feature/TEST-1"
    Et l'historique de "feature/TEST-1" contient "Livraison concurrente en préprod"
    Et l'historique de "__PR__feature/TEST-1" contient "Livraison concurrente en préprod"
    Et la branche distante "feature/TEST-1" a 3 commits d'avance sur "__PR__feature/TEST-1"
    Et la branche distante "__PR__feature/TEST-1" a 1 commits d'avance sur "develop"

  Scénario: Le rebase nettoie les branches de travail temporaires
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-2 --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche locale "jgit_rebase_feature/TEST-2" n'existe pas
    Et la branche locale "jgit_rebase___PR__feature/TEST-2" n'existe pas
    Et la branche locale "__PR__feature/TEST-2" n'existe pas
    Et la branche locale "feature/TEST-2" existe

  Scénario: Un hotfix se rebase sur main
    Étant donné je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Livraison en production"
    Quand je lance "jgit hotfix rebase URGENT-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/prod.txt" existe sur la branche distante "hotfix/URGENT-1"
    Et le fichier "src/correctif.txt" existe sur la branche distante "hotfix/URGENT-1"

  Scénario: --based-on impose la branche de référence du rebase
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Livraison en production"
    Quand je lance "jgit feature rebase TEST-3 --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/prod.txt" existe sur la branche distante "feature/TEST-3"

  Scénario: --based-on sur une branche inconnue est refusé
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-4"
    Quand je lance "jgit feature rebase TEST-4 --based-on inexistante --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "Elle a été demandée par --based-on"
    Et la sortie contient "jgit feature rebase TEST-4 --based-on <branche>"
    Et la branche distante "feature/TEST-4" est inchangée

  # --- Squash des commits de travail ---------------------------------------

  Scénario: --squash réduit les commits de travail à un seul
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je commite le fichier "src/b.txt" contenant "B" avec le message "Commit B"
    Et je commite le fichier "src/c.txt" contenant "C" avec le message "Commit C"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-5 --no-interaction --squash"
    Alors jgit se termine sans erreur
    Et la sortie contient "Commits squashés dans un unique commit : Commit A"
    Et la branche distante "feature/TEST-5" a 2 commits d'avance sur "__PR__feature/TEST-5"
    Et l'historique de "feature/TEST-5" ne contient pas "Commit B"
    Et l'historique de "feature/TEST-5" ne contient pas "Commit C"
    Et le fichier "src/a.txt" existe sur la branche distante "feature/TEST-5"
    Et le fichier "src/b.txt" existe sur la branche distante "feature/TEST-5"
    Et le fichier "src/c.txt" existe sur la branche distante "feature/TEST-5"

  Scénario: --squash sur un seul commit de travail ne fait rien
    Étant donné je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-6 --no-interaction --squash"
    Alors jgit se termine sans erreur
    Et la sortie contient "Rien à squasher : la branche feature/TEST-6 ne contient qu'un seul commit de travail."
    Et l'historique de "feature/TEST-6" contient "Commit A"
    Et la branche distante "feature/TEST-6" a 2 commits d'avance sur "__PR__feature/TEST-6"

  Scénario: Au-delà du seuil, le squash est proposé mais refusé par défaut
    Étant donné je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Et je commite le fichier "src/t1.txt" contenant "1" avec le message "Commit numéro 1"
    Et je commite le fichier "src/t2.txt" contenant "2" avec le message "Commit numéro 2"
    Et je commite le fichier "src/t3.txt" contenant "3" avec le message "Commit numéro 3"
    Et je commite le fichier "src/t4.txt" contenant "4" avec le message "Commit numéro 4"
    Et je commite le fichier "src/t5.txt" contenant "5" avec le message "Commit numéro 5"
    Et je commite le fichier "src/t6.txt" contenant "6" avec le message "Commit numéro 6"
    Et je commite le fichier "src/t7.txt" contenant "7" avec le message "Commit numéro 7"
    Et je commite le fichier "src/t8.txt" contenant "8" avec le message "Commit numéro 8"
    Et je commite le fichier "src/t9.txt" contenant "9" avec le message "Commit numéro 9"
    Et je pousse la branche courante
    Quand je lance "jgit feature rebase TEST-7 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "contient 9 commits de travail."
    Et la sortie contient "Souhaitez-vous squasher ces commits avant le rebase ? -> n"
    Et l'historique de "feature/TEST-7" contient "Commit numéro 1"
    Et l'historique de "feature/TEST-7" contient "Commit numéro 9"
    Et la branche distante "feature/TEST-7" a 10 commits d'avance sur "__PR__feature/TEST-7"

  Scénario: Sous le seuil, le squash n'est pas proposé
    Étant donné je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Et je commite le fichier "src/t1.txt" contenant "1" avec le message "Commit numéro 1"
    Et je commite le fichier "src/t2.txt" contenant "2" avec le message "Commit numéro 2"
    Et je pousse la branche courante
    Quand je lance "jgit feature rebase TEST-8 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "Souhaitez-vous squasher ces commits avant le rebase ?"
    Et la branche distante "feature/TEST-8" a 3 commits d'avance sur "__PR__feature/TEST-8"

  Scénario: Le squash proposé au-delà du seuil peut être accepté
    Étant donné je lance "jgit feature start TEST-9 --no-interaction --no-open"
    Et je commite le fichier "src/t1.txt" contenant "1" avec le message "Commit numéro 1"
    Et je commite le fichier "src/t2.txt" contenant "2" avec le message "Commit numéro 2"
    Et je commite le fichier "src/t3.txt" contenant "3" avec le message "Commit numéro 3"
    Et je commite le fichier "src/t4.txt" contenant "4" avec le message "Commit numéro 4"
    Et je commite le fichier "src/t5.txt" contenant "5" avec le message "Commit numéro 5"
    Et je commite le fichier "src/t6.txt" contenant "6" avec le message "Commit numéro 6"
    Et je commite le fichier "src/t7.txt" contenant "7" avec le message "Commit numéro 7"
    Et je commite le fichier "src/t8.txt" contenant "8" avec le message "Commit numéro 8"
    Et je commite le fichier "src/t9.txt" contenant "9" avec le message "Commit numéro 9"
    Et je pousse la branche courante
    Quand je lance "jgit feature rebase TEST-9" et que je réponds aux questions :
      | Souhaitez-vous squasher ces commits | y                    |
      | Message du commit squashé           | Tout le travail TEST-9 |
      | Souhaitez-vous continuer            | y                    |
      | Confirmez-vous que le rebase        | y                    |
    Alors jgit se termine sans erreur
    Et l'historique de "feature/TEST-9" contient "Tout le travail TEST-9"
    Et l'historique de "feature/TEST-9" ne contient pas "Commit numéro 9"
    Et la branche distante "feature/TEST-9" a 2 commits d'avance sur "__PR__feature/TEST-9"
    Et le fichier "src/t9.txt" existe sur la branche distante "feature/TEST-9"

  # --- Refus et garde-fous --------------------------------------------------

  Scénario: Refuser la première confirmation laisse tout en l'état
    Étant donné je lance "jgit feature start TEST-10 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-10"
    Et je note l'état de la branche distante "__PR__feature/TEST-10"
    Quand je lance "jgit feature rebase TEST-10" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche distante "feature/TEST-10" est inchangée
    Et la branche distante "__PR__feature/TEST-10" est inchangée

  Scénario: Refuser la confirmation finale annule le rebase sans rien pousser
    Étant donné je lance "jgit feature start TEST-11 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Et je note l'état de la branche distante "feature/TEST-11"
    Et je note l'état de la branche distante "__PR__feature/TEST-11"
    Quand je lance "jgit feature rebase TEST-11" et que je réponds aux questions :
      | Souhaitez-vous continuer     | y |
      | Confirmez-vous que le rebase | n |
    Alors jgit se termine en erreur
    Et la sortie contient "les branches locales ne sont plus correctes"
    Et la branche distante "feature/TEST-11" est inchangée
    Et la branche distante "__PR__feature/TEST-11" est inchangée
    Et l'historique local de "feature/TEST-11" ne contient pas "Livraison concurrente"

  Scénario: Un conflit ne peut pas être validé tout seul en --no-interaction
    Étant donné je lance "jgit feature start TEST-12 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature" avec le message "Modifie app.txt côté feature"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt côté develop"
    Et je note l'état de la branche distante "feature/TEST-12"
    Et je note l'état de la branche distante "__PR__feature/TEST-12"
    Quand je lance "jgit feature rebase TEST-12 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Conflit détecté."
    Et la sortie contient "Le mode --no-interaction ne permet pas de résoudre un conflit."
    Et la sortie contient "Le rebase a été annulé, l'état local est restauré et le remote n'a pas été modifié."
    Et la branche distante "feature/TEST-12" est inchangée
    Et la branche distante "__PR__feature/TEST-12" est inchangée
    Et la branche locale "jgit_rebase_feature/TEST-12" n'existe pas
    Et la branche locale "jgit_rebase___PR__feature/TEST-12" n'existe pas

  Scénario: Un conflit survenu après un squash restaure l'historique initial
    Étant donné je lance "jgit feature start TEST-13 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature" avec le message "Modifie app.txt côté feature"
    Et je commite le fichier "src/autre.txt" contenant "autre" avec le message "Ajoute un autre fichier"
    Et je commite le fichier "src/encore.txt" contenant "encore" avec le message "Ajoute encore un fichier"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt côté develop"
    Et je note l'état de la branche distante "feature/TEST-13"
    Quand je lance "jgit feature rebase TEST-13 --no-interaction --squash"
    Alors jgit se termine en erreur
    Et la sortie contient "Restauration de l'historique initial de feature/TEST-13 (annulation du squash)."
    Et la branche distante "feature/TEST-13" est inchangée
    Et l'historique local de "feature/TEST-13" contient "Ajoute un autre fichier"
    Et l'historique local de "feature/TEST-13" contient "Ajoute encore un fichier"

  Scénario: Une PR déjà mergée n'est plus un fast-forward et bloque le rebase
    Étant donné je lance "jgit feature start TEST-14 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-14" est squash-mergée sur GitHub avec le message "TEST-14 : A (#3)"
    Et je note l'état de la branche distante "feature/TEST-14"
    Quand je lance "jgit feature rebase TEST-14 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche feature/TEST-14 n'est PAS un fast-forward de __PR__feature/TEST-14."
    Et la sortie contient "Cela peut se produire si vous avez déjà cloturé la PR."
    Et la branche distante "feature/TEST-14" est inchangée

  Scénario: Un commit de fusion sur la branche de travail bloque le rebase
    Étant donné je lance "jgit feature start TEST-15 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Et je récupère les nouveautés du remote
    Et je merge la branche "origin/develop" dans la branche courante
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-15"
    Quand je lance "jgit feature rebase TEST-15 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "est un commit de fusion. On ne peut pas rebase automatiquement un commit de fusion."
    Et la sortie contient "Pensez à toujours squash and merge vos PRs"
    Et la branche distante "feature/TEST-15" est inchangée

  Scénario: Rebaser une feature inconnue est refusé
    Quand je lance "jgit feature rebase INCONNUE --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche feature/INCONNUE n'existe pas (ni en local ni sur origin)."
    Et la branche distante "feature/INCONNUE" n'existe pas

  # Les deux branches sont de vraies branches jgit, avec leurs commits d'init ;
  # c'est le serveur qui ne les a plus, parce qu'elles y ont été supprimées.
  Scénario: Une paire de branches absente du serveur est refusée
    Étant donné je lance "jgit feature start ORPHELINE --no-interaction --no-open"
    Et je récupère la branche distante "__PR__feature/ORPHELINE" en local
    Et la branche "feature/ORPHELINE" est supprimée sur GitHub
    Et la branche "__PR__feature/ORPHELINE" est supprimée sur GitHub
    Quand je lance "jgit feature rebase ORPHELINE --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "Something get wrong, feature/ORPHELINE doesn't exist on remote"
    Et la branche distante "feature/ORPHELINE" n'existe pas
