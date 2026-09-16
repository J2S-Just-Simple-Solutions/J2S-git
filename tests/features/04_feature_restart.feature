# language: fr
Fonctionnalité: Redémarrage d'une feature après le merge de sa PR
  Une fois la PR squash-mergée, la branche de travail est recréée à partir de la
  branche __PR__ et une nouvelle PR est ouverte. L'opération n'est autorisée que
  si les deux branches contiennent exactement le même code.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: La feature est relancée après le squash-merge de sa PR
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "premier lot" avec le message "Premier lot de travail"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 : premier lot (#7)"
    Quand je lance "jgit feature restart TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "Les deux branches contiennent exactement le même code."
    Et je suis sur la branche "feature/TEST-1"
    Et la branche locale "__PR__feature/TEST-1" n'existe pas
    Et le dernier commit de "feature/TEST-1" contient "RESTART feature/TEST-1 [empty_commit]"
    Et l'historique de "feature/TEST-1" contient "TEST-1 : premier lot (#7)"
    Et le fichier "src/travail.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/travail.txt" existe sur la branche distante "__PR__feature/TEST-1"
    Et la branche distante "feature/TEST-1" a 1 commits d'avance sur "__PR__feature/TEST-1"
    Et GitHub a reçu "--title 'TEST-1 - RESTART'"
    Et GitHub a reçu "--base=__PR__feature/TEST-1"
    Et GitHub a reçu "--head=feature/TEST-1"

  Scénario: Le travail continue normalement après un restart
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "premier lot" avec le message "Premier lot de travail"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 : premier lot (#8)"
    Et je lance "jgit feature restart TEST-2 --no-interaction --no-open"
    Quand je commite le fichier "src/travail2.txt" contenant "second lot" avec le message "Second lot de travail"
    Et je pousse la branche courante
    Alors le fichier "src/travail2.txt" existe sur la branche distante "feature/TEST-2"
    Et le fichier "src/travail2.txt" n'existe pas sur la branche distante "__PR__feature/TEST-2"

  Scénario: Un restart est refusé tant que la PR n'a pas été mergée
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "pas encore mergé" avec le message "Travail non mergé"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-3"
    Quand je lance "jgit feature restart TEST-3 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "Le code de 'feature/TEST-3' et '__PR__feature/TEST-3' est différent !"
    Et la sortie contient "Le restart ne peut se faire que sur deux branches identiques"
    Et la branche distante "feature/TEST-3" est inchangée
    Et le fichier "src/travail.txt" n'existe pas sur la branche distante "__PR__feature/TEST-3"
    Et GitHub n'a pas reçu "pr create"

  Scénario: --no-open recrée la branche sans rouvrir de PR
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "lot unique" avec le message "Lot unique"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 : lot unique (#9)"
    Quand je lance "jgit feature restart TEST-4 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "Skipping pull request creation (--no-open)."
    Et GitHub a reçu exactement 0 appels

  Scénario: Un hotfix se relance comme une feature
    Étant donné je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et la PR de "hotfix/URGENT-1" est squash-mergée sur GitHub avec le message "URGENT-1 : correctif (#10)"
    Quand je lance "jgit hotfix restart URGENT-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "hotfix/URGENT-1"
    Et le dernier commit de "hotfix/URGENT-1" contient "RESTART hotfix/URGENT-1"
    Et GitHub a reçu "--title 'URGENT-1 - RESTART'"

  # Le garde-fou repose sur `git ls-remote --exit-code` : sans --exit-code la
  # commande renvoie 0 même sans correspondance, et jgit publiait une feature
  # orpheline au lieu de refuser.
  Scénario: Le restart d'une feature inconnue est refusé
    Quand je lance "jgit feature restart INCONNUE --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de PR '__PR__feature/INCONNUE' n'existe pas."
    Et la branche locale "feature/INCONNUE" n'existe pas
    Et la branche distante "feature/INCONNUE" n'existe pas
    Et la branche distante "__PR__feature/INCONNUE" n'existe pas
