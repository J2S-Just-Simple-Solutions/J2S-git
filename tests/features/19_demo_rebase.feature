# language: fr
Fonctionnalité: Rebaser une démo sur la version actuelle de sa base
  « demo rebase » reconstruit la démo sur la version serveur de sa base, en
  rejouant ses propres commits : les résolutions de conflit qu'ils contiennent
  sont reprises. Les tickets livrés entre-temps dans la base et ceux dont la
  branche a disparu sont retirés, sauf --keep-delivered / --keep-missing. Une
  démo déjà à jour n'est pas republiée.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-1 --from feature/TEST-2 --no-interaction"

  Scénario: La démo est reconstruite sur une base qui a avancé
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "rebase"
    Et le JSON a "changed" vrai
    Et le JSON a "pushed" vrai
    Et le JSON a "base" égal à "develop"
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo/sprint12"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "demo.behind_base" égal au nombre 0
    Et le JSON a "tickets[0].status" égal à "up_to_date"
    Et le JSON a "tickets[1].status" égal à "up_to_date"

  # C'est ce que Jenkins fera toutes les heures : il ne doit déclencher aucun
  # déploiement quand rien n'a changé.
  Scénario: Une démo déjà à jour n'est pas republiée
    Étant donné je note l'état de la branche distante "demo/sprint12"
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "changed" faux
    Et le JSON a "pushed" faux
    Et la sortie contient "est déjà à jour sur develop : rien n'a été modifié."
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Un ticket livré dans la base est retiré
    Étant donné la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 (#1)"
    Et la PR de "feature/TEST-1" est livrée dans "develop"
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dropped[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "dropped[0].reason" égal à "delivered"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-2 |
    # Son code est là quand même : il est dans la base.
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo/sprint12"

  Scénario: --keep-delivered garde un ticket livré
    Étant donné la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 (#1)"
    Et la PR de "feature/TEST-1" est livrée dans "develop"
    Quand je lance "jgit demo rebase sprint12 --keep-delivered --no-interaction"
    Alors jgit se termine sans erreur
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |

  Scénario: Un ticket dont la branche a disparu est retiré
    Étant donné la branche "feature/TEST-2" est supprimée sur GitHub
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dropped[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "dropped[0].reason" égal à "missing"
    Et le fichier "src/feature2.txt" n'existe pas sur la branche distante "demo/sprint12"

  # La démo contient les commits du ticket : on peut le garder même quand sa
  # branche n'existe plus.
  Scénario: --keep-missing garde un ticket dont la branche a disparu
    Étant donné la branche "feature/TEST-2" est supprimée sur GitHub
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo rebase sprint12 --keep-missing --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/feature2.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo/sprint12"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |

  Scénario: --based-on déplace la démo sur une autre base
    Quand je lance "jgit demo rebase sprint12 --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo/sprint12" est partie de "main"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "demo.base" égal à "main"

  Scénario: Les commits ajoutés à la main sont rejoués à la fin, et signalés
    Étant donné un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit demo rebase sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "warnings[0].code" égal à "foreign_commits_kept"
    Et le fichier "src/rustine.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo/sprint12"

  Scénario: --drop-foreign écarte les commits ajoutés à la main
    Étant donné un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Quand je lance "jgit demo rebase sprint12 --drop-foreign --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/rustine.txt" n'existe pas sur la branche distante "demo/sprint12"

  Scénario: --dry-run annonce la reconstruction sans rien publier
    Étant donné la PR de "feature/TEST-1" est squash-mergée sur GitHub avec le message "TEST-1 (#1)"
    Et la PR de "feature/TEST-1" est livrée dans "develop"
    Et je note l'état de la branche distante "demo/sprint12"
    Quand je lance "jgit demo rebase sprint12 --dry-run --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dry_run" vrai
    Et le JSON a "dropped[0].reason" égal à "delivered"
    Et la sortie contient "- feature/TEST-1 (déjà livré dans develop)"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Une base disparue se refuse comme partout ailleurs
    Étant donné je lance "jgit demo create salon --based-on main --no-interaction"
    Quand je lance "jgit demo rebase salon --based-on inexistante --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "base_not_found"
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
