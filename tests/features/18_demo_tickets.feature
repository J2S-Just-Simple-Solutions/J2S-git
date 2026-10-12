# language: fr
Fonctionnalité: Ajouter, retirer et reprendre les tickets d'une démo
  « demo add » pose un ticket à la suite de la démo — ou seulement ses commits
  arrivés depuis — sans rien réécrire. « demo drop » reconstruit la démo sans
  un ticket, à partir de la démo elle-même : ce qui précède le ticket retiré
  ne bouge pas, ce qui suit est rejoué tel quel. « demo refresh » reprend un
  ticket réécrit (squash) en entier, à sa place.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je commite le fichier "src/feature1-bis.txt" contenant "feature 1 bis" avec le message "Complète la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/feature2.txt" contenant "feature 2" avec le message "Ajoute la feature 2"
    Et je pousse la branche courante
    Et je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create sprint12 --from feature/TEST-1 --no-interaction"
    Et je note l'état de la branche distante "demo/sprint12"

  # --- demo add --------------------------------------------------------------

  Scénario: Un ticket s'ajoute à la suite, sans réécrire la démo
    Quand je lance "jgit demo add sprint12 --from hotfix/URGENT-1 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "schema" égal à "jgit.demo.result/1"
    Et le JSON a "operation" égal à "add"
    Et le JSON a "added[0]" égal à "hotfix/URGENT-1"
    Et le JSON a "changed" vrai
    Et la branche distante "demo/sprint12" a avancé sans réécriture
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1  |
      | hotfix/URGENT-1 |
    Et le fichier "src/correctif.txt" existe sur la branche distante "demo/sprint12"
    Et je suis sur la branche "develop"

  Scénario: Plusieurs tickets s'ajoutent en une commande, dans l'ordre donné
    Quand je lance "jgit demo add sprint12 --from hotfix/URGENT-1 --from feature/TEST-2"
    Alors jgit se termine sans erreur
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1  |
      | hotfix/URGENT-1 |
      | feature/TEST-2  |

  Scénario: Les nouveaux commits d'un ticket déjà présent s'ajoutent à la suite
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2"
    Et je me place sur la branche "feature/TEST-1"
    Et je commite le fichier "src/feature1-ter.txt" contenant "suite" avec le message "Poursuit la feature 1"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je note l'état de la branche distante "demo/sprint12"
    Quand je lance "jgit demo add sprint12 --from feature/TEST-1 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "updated[0]" égal à "feature/TEST-1"
    Et la liste JSON "added" contient 0 éléments
    Et la branche distante "demo/sprint12" a avancé sans réécriture
    Et le fichier "src/feature1-ter.txt" existe sur la branche distante "demo/sprint12"
    # Le ticket garde sa place dans la recette : sa première apparition.
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "tickets[ticket=feature/TEST-1].status" égal à "up_to_date"
    Et le JSON a "tickets[ticket=feature/TEST-1].segments" égal au nombre 2
    Et le JSON a "tickets[ticket=feature/TEST-1].commits_in_demo" égal au nombre 3

  # Une démo inchangée n'est jamais republiée : un déploiement qui la surveille
  # ne se relance pas pour rien.
  Scénario: Ajouter un ticket déjà à jour ne publie rien
    Quand je lance "jgit demo add sprint12 --from feature/TEST-1 --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "changed" faux
    Et le JSON a "pushed" faux
    Et la sortie contient "feature/TEST-1 est déjà à jour dans la démo."
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Un ticket réécrit depuis son ajout ne s'ajoute plus à la suite
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je lance "jgit feature rebase TEST-1 --squash --no-interaction"
    Quand je lance "jgit demo add sprint12 --from feature/TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "ticket_diverged"
    Et le JSON a "error.hint" égal à "Pour le reprendre en entier : jgit demo refresh sprint12 --from feature/TEST-1"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Un ticket déjà livré dans la base ne s'ajoute pas
    Étant donné la PR de "hotfix/URGENT-1" est squash-mergée sur GitHub avec le message "URGENT-1 (#1)"
    Et la PR de "hotfix/URGENT-1" est livrée dans "develop"
    Quand je lance "jgit demo add sprint12 --from hotfix/URGENT-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "ticket_delivered"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Ajouter sans ticket, ou à une démo inconnue, est refusé
    Quand je lance "jgit demo add sprint12 --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Quand je lance "jgit demo add inconnue --from feature/TEST-2 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "demo_not_found"

  Scénario: Sans nom, add vise la démo de la branche courante
    Étant donné je récupère la branche distante "demo/sprint12" en local
    Et je me place sur la branche "demo/sprint12"
    Quand je lance "jgit demo add --from feature/TEST-2"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "demo/sprint12"
    Et le fichier de travail "src/feature2.txt" contient "feature 2"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |

  # --- demo drop -------------------------------------------------------------

  Scénario: Un ticket est retiré, les autres gardent leur ordre
    Étant donné je lance "jgit demo add sprint12 --from hotfix/URGENT-1 --from feature/TEST-2"
    Quand je lance "jgit demo drop sprint12 --from hotfix/URGENT-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "drop"
    Et le JSON a "dropped[0].ticket" égal à "hotfix/URGENT-1"
    Et le JSON a "dropped[0].reason" égal à "requested"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |
    Et le fichier "src/correctif.txt" n'existe pas sur la branche distante "demo/sprint12"
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/feature2.txt" existe sur la branche distante "demo/sprint12"
    Et la branche locale "jgit_demo_sprint12" n'existe pas
    Et je suis sur la branche "develop"

  Scénario: Le premier ticket peut être retiré
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2"
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-2 |
    Et le fichier "src/feature1.txt" n'existe pas sur la branche distante "demo/sprint12"
    Et la branche distante "demo/sprint12" est partie de "develop"

  Scénario: Le retrait demande confirmation
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-1" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "JGit va reconstruire la démo demo/sprint12 sans :"
    Et la sortie contient "- feature/TEST-1 (retiré à votre demande)"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: --dry-run montre le retrait sans rien publier
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-1 --dry-run --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dry_run" vrai
    Et le JSON a "dropped[0].ticket" égal à "feature/TEST-1"
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Retirer un ticket absent de la démo est refusé
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-2 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "ticket_not_in_demo"
    Et la branche distante "demo/sprint12" est inchangée

  # Un commit poussé à la main sur la démo n'appartient à aucun ticket : jgit
  # ne décide pas seul de le jeter.
  Scénario: Un commit ajouté à la main survit au retrait d'un ticket
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2"
    Et un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-2 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/rustine.txt" existe sur la branche distante "demo/sprint12"
    Et le fichier "src/feature2.txt" n'existe pas sur la branche distante "demo/sprint12"
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "demo.foreign_commit_count" égal au nombre 1

  Scénario: --drop-foreign écarte les commits ajoutés à la main
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2"
    Et un autre développeur pousse le fichier "src/rustine.txt" contenant "rustine" sur la branche "demo/sprint12" avec le message "Rustine pour la démo"
    Quand je lance "jgit demo drop sprint12 --from feature/TEST-2 --drop-foreign --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le fichier "src/rustine.txt" n'existe pas sur la branche distante "demo/sprint12"
    Et le JSON a "dropped[ticket=-].reason" égal à "foreign"

  # --- demo refresh ----------------------------------------------------------

  Scénario: Un ticket réécrit est repris en entier, à sa place
    Étant donné je lance "jgit demo add sprint12 --from feature/TEST-2"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je lance "jgit feature rebase TEST-1 --squash --no-interaction"
    Quand je lance "jgit demo refresh sprint12 --from feature/TEST-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "refresh"
    Et le JSON a "updated[0]" égal à "feature/TEST-1"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |
    Quand je lance "jgit demo show sprint12 --json" en lisant le JSON
    Alors le JSON a "tickets[ticket=feature/TEST-1].status" égal à "up_to_date"
    Et le JSON a "tickets[ticket=feature/TEST-1].commits_in_demo" égal au nombre 1
    Et le JSON a "tickets[ticket=feature/TEST-2].status" égal à "up_to_date"

  Scénario: Reprendre un ticket déjà à jour ne publie rien
    Quand je lance "jgit demo refresh sprint12 --from feature/TEST-1 --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "changed" faux
    Et la branche distante "demo/sprint12" est inchangée
