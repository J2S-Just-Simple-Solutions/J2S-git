# language: fr
Fonctionnalité: Réponse aux questions de confirmation
  Le suffixe (Y/n) ou (y/N) met la réponse par défaut en majuscule : un
  développeur qui tape cette majuscule doit être compris. Les réponses sont donc
  lues sans tenir compte de la casse, et « oui » / « o » valent « y ».

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Un « Y » majuscule accepte le rebase
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-1" et que je réponds aux questions :
      | Souhaitez-vous continuer     | Y |
      | Confirmez-vous que le rebase | Y |
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "Opération annulée."
    Et la sortie contient "Rebase terminé avec succès"
    Et l'historique de "feature/TEST-1" contient "Livraison concurrente"

  Scénario: « oui » et « O » acceptent le rebase
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-2" et que je réponds aux questions :
      | Souhaitez-vous continuer     | oui |
      | Confirmez-vous que le rebase | O   |
    Alors jgit se termine sans erreur
    Et la sortie contient "Rebase terminé avec succès"

  Scénario: « YES » en majuscules accepte le rebase
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Quand je lance "jgit feature rebase TEST-3" et que je réponds aux questions :
      | Souhaitez-vous continuer     | YES |
      | Confirmez-vous que le rebase | Yes |
    Alors jgit se termine sans erreur
    Et la sortie contient "Rebase terminé avec succès"

  Scénario: Un « N » majuscule refuse et laisse tout en l'état
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-4"
    Et je note l'état de la branche distante "__PR__feature/TEST-4"
    Quand je lance "jgit feature rebase TEST-4" et que je réponds aux questions :
      | Souhaitez-vous continuer | N |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche distante "feature/TEST-4" est inchangée
    Et la branche distante "__PR__feature/TEST-4" est inchangée

  Scénario: Une réponse inconnue vaut refus
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-5"
    Quand je lance "jgit feature rebase TEST-5" et que je réponds aux questions :
      | Souhaitez-vous continuer | peut-être |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche distante "feature/TEST-5" est inchangée
