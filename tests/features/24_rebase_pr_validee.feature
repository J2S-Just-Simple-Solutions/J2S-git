# language: fr
Fonctionnalité: Rebase d'une PR validée, en attente de son merge
  Une fois la PR squash-mergée, le code validé est sur la branche __PR__, et
  c'est elle qui sera mergée dans sa branche finale : celle dont le ticket est
  parti. Si cette branche a bougé entre-temps, le merge risque de coincer. Le
  rebase reconstruit alors la seule branche __PR__ sur sa base, pour que le
  conflit soit résolu par le développeur, avant le merge. La branche de
  travail, qui a le même code, ne sert plus : elle est supprimée. Une branche
  __PR__ déjà mergée ne sert plus non plus.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: La branche de PR est reconstruite seule, la branche de travail est supprimée
    Étant donné je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 : A (#3)"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-1" et que je réponds aux questions :
      | Souhaitez-vous continuer     | y |
      | Confirmez-vous que le rebase | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "La PR de feature/TEST-1 a été validée : seule la branche __PR__feature/TEST-1 est reconstruite"
    Et la sortie contient "elle sera supprimée en local et sur le serveur"
    Et la sortie contient "Rebase terminé avec succès : __PR__feature/TEST-1 peut être mergée dans develop."
    Et je suis sur la branche "develop"
    Et le fichier "src/preprod.txt" existe sur la branche distante "__PR__feature/TEST-1"
    Et le fichier "src/a.txt" existe sur la branche distante "__PR__feature/TEST-1"
    Et l'historique de "__PR__feature/TEST-1" contient "TEST-1 : A (#3)"
    Et la branche distante "__PR__feature/TEST-1" a 2 commits d'avance sur "develop"
    Et la branche distante "__PR__feature/TEST-1" est partie de "develop"
    Et la branche distante "feature/TEST-1" n'existe pas
    Et la branche locale "feature/TEST-1" n'existe pas
    Et la branche locale "__PR__feature/TEST-1" n'existe pas

  Scénario: Sans branche de travail, la branche de PR est reconstruite seule
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-2" est squash-mergée sur GitHub avec le message "TEST-2 : A (#4)"
    Et la branche "feature/TEST-2" est supprimée sur GitHub
    Et je me place sur la branche "develop"
    Et je supprime la branche locale "feature/TEST-2"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-2 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "elle sera supprimée"
    Et le fichier "src/preprod.txt" existe sur la branche distante "__PR__feature/TEST-2"
    Et le fichier "src/a.txt" existe sur la branche distante "__PR__feature/TEST-2"
    Et la branche distante "__PR__feature/TEST-2" a 2 commits d'avance sur "develop"
    Et la branche distante "feature/TEST-2" n'existe pas

  Scénario: Le conflit avec la branche finale est résolu avant le merge, puis repris
    Étant donné je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Et je commite le fichier "src/app.txt" contenant "version de la feature" avec le message "Modifie app.txt côté feature"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-3" est squash-mergée sur GitHub avec le message "TEST-3 : app (#5)"
    Et un autre développeur pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt côté develop"
    Et je note l'état de la branche distante "__PR__feature/TEST-3"
    Et je lance "jgit feature rebase TEST-3 --no-interaction --on-conflict pause"
    Et une opération jgit est en pause
    Et la branche distante "__PR__feature/TEST-3" est inchangée
    Et la branche distante "feature/TEST-3" existe
    Et je résous le conflit du fichier "src/app.txt" avec "version résolue"
    Quand je lance "jgit feature continue TEST-3 --no-interaction"
    Alors jgit se termine sans erreur
    Et aucune opération jgit n'est en pause
    Et le fichier "src/app.txt" de la branche distante "__PR__feature/TEST-3" contient "version résolue"
    Et l'historique de "__PR__feature/TEST-3" contient "Modifie app.txt côté develop"
    Et la branche distante "feature/TEST-3" n'existe pas

  Scénario: Après ce rebase, le ticket peut repartir pour un second lot
    Étant donné je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 : A (#6)"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré" sur la branche "develop" avec le message "Livraison concurrente"
    Et je lance "jgit feature rebase TEST-4 --no-interaction"
    Quand je lance "jgit feature restart TEST-4 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "feature/TEST-4"
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-4"
    Et la branche distante "feature/TEST-4" a 1 commits d'avance sur "__PR__feature/TEST-4"

  Scénario: Du travail poussé après la validation bloque le rebase, sans rien toucher
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-5" est squash-mergée sur GitHub avec le message "TEST-5 : A (#7)"
    Et je commite le fichier "src/b.txt" contenant "B" avec le message "Commit B, après la validation"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré" sur la branche "develop" avec le message "Livraison concurrente"
    Et je note l'état de la branche distante "feature/TEST-5"
    Et je note l'état de la branche distante "__PR__feature/TEST-5"
    Quand je lance "jgit feature rebase TEST-5 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "pr_validated_new_work"
    Et le JSON a "error.hint" égal à "Pour voir ce travail : git diff __PR__feature/TEST-5 feature/TEST-5"
    Et la sortie contient "du travail ajouté après la validation, qui n'a pas été relu"
    Et la branche distante "feature/TEST-5" est inchangée
    Et la branche distante "__PR__feature/TEST-5" est inchangée
    Et la branche locale "feature/TEST-5" existe

  Scénario: Un commit local non poussé après la validation bloque aussi le rebase
    Étant donné je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-6" est squash-mergée sur GitHub avec le message "TEST-6 : A (#8)"
    Et je commite le fichier "src/b.txt" contenant "B" avec le message "Commit B, pas encore poussé"
    Et je note l'état de la branche distante "feature/TEST-6"
    Quand je lance "jgit feature rebase TEST-6 --no-interaction"
    Alors jgit se termine avec le code 2
    Et la sortie contient "du travail ajouté après la validation"
    Et la branche distante "feature/TEST-6" est inchangée
    Et l'historique local de "feature/TEST-6" contient "Commit B, pas encore poussé"

  Scénario: Une PR jamais validée dont la branche de travail a disparu est refusée
    Étant donné je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Et la branche "feature/TEST-7" est supprimée sur GitHub
    Et je me place sur la branche "develop"
    Et je supprime la branche locale "feature/TEST-7"
    Et je note l'état de la branche distante "__PR__feature/TEST-7"
    Quand je lance "jgit feature rebase TEST-7 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "pr_not_validated"
    Et le JSON a "error.hint" égal à "Si le ticket est abandonné, __PR__feature/TEST-7 ne sert plus à rien : git push origin --delete __PR__feature/TEST-7"
    Et la branche distante "__PR__feature/TEST-7" est inchangée

  Scénario: Une PR déjà mergée dans sa branche finale : ses branches sont supprimées
    Étant donné je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-8" est squash-mergée sur GitHub avec le message "TEST-8 : A (#9)"
    Et la PR de "feature/TEST-8" est livrée dans "develop"
    Quand je lance "jgit feature rebase TEST-8" et que je réponds aux questions :
      | Supprimer __PR__feature/TEST-8 et feature/TEST-8 | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "La branche __PR__feature/TEST-8 est déjà mergée dans develop : il n'y a rien à rebaser."
    Et je suis sur la branche "develop"
    Et la branche distante "__PR__feature/TEST-8" n'existe pas
    Et la branche distante "feature/TEST-8" n'existe pas
    Et la branche locale "feature/TEST-8" n'existe pas
    Et le fichier "src/a.txt" existe sur la branche distante "develop"

  Scénario: Refuser la suppression d'une PR déjà mergée ne touche à rien
    Étant donné je lance "jgit feature start TEST-9 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-9" est squash-mergée sur GitHub avec le message "TEST-9 : A (#10)"
    Et la PR de "feature/TEST-9" est livrée dans "develop"
    Quand je lance "jgit feature rebase TEST-9" et que je réponds aux questions :
      | Supprimer __PR__feature/TEST-9 et feature/TEST-9 | n |
    Alors jgit se termine sans erreur
    Et la sortie contient "Rien n'a été supprimé."
    Et la branche distante "__PR__feature/TEST-9" existe
    Et la branche distante "feature/TEST-9" existe

  Scénario: Une PR rouverte puis de nouveau validée ne rejoue que son nouveau lot
    Étant donné je lance "jgit feature start TEST-10 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Premier lot"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-10" est squash-mergée sur GitHub avec le message "TEST-10 : premier lot (#11)"
    Et la PR de "feature/TEST-10" est livrée dans "develop"
    Et je lance "jgit feature restart TEST-10 --no-interaction --no-open"
    Et je commite le fichier "src/b.txt" contenant "B" avec le message "Second lot"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-10" est squash-mergée sur GitHub avec le message "TEST-10 : second lot (#12)"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "livré" sur la branche "develop" avec le message "Livraison concurrente"
    Quand je lance "jgit feature rebase TEST-10 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" existe sur la branche distante "__PR__feature/TEST-10"
    Et le fichier "src/b.txt" existe sur la branche distante "__PR__feature/TEST-10"
    Et la branche distante "__PR__feature/TEST-10" a 1 commits d'avance sur "develop"
    Et la branche distante "feature/TEST-10" n'existe pas

  Scénario: Un hotfix validé est reconstruit sur main
    Étant donné je lance "jgit hotfix start TEST-11 --no-interaction --no-open"
    Et je commite le fichier "src/fix.txt" contenant "fix" avec le message "Corrige"
    Et je pousse la branche courante
    Et la PR de "hotfix/TEST-11" est squash-mergée sur GitHub avec le message "TEST-11 : fix (#13)"
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Correctif concurrent"
    Quand je lance "jgit hotfix rebase TEST-11 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/prod.txt" existe sur la branche distante "__PR__hotfix/TEST-11"
    Et la branche distante "__PR__hotfix/TEST-11" a 2 commits d'avance sur "main"
    Et la branche distante "hotfix/TEST-11" n'existe pas
