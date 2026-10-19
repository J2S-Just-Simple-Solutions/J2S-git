# language: fr
Fonctionnalité: Appliquer ce que l'état des lieux trouve faisable sans conflit
  « jgit audit --apply » fait l'état des lieux, montre le plan, puis lance ce
  qui passe sans conflit : le rebase de mes tickets en retard sur leur base,
  puis la mise à jour des démos faisables. Chaque opération est la vraie
  commande jgit, avec son lease et son abandon propre.

  Le reste est laissé de côté et listé : les tickets des autres (leur branche
  locale divergerait sans qu'ils le sachent), les tickets dont la base n'est
  que supposée, et tout ce qui coince.

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

  Scénario: Mes tickets en retard sont rebasés, puis la démo est remise à jour
    Étant donné je supprime la branche locale "feature/TEST-2"
    Et je supprime la branche locale "__PR__feature/TEST-2"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit audit --apply --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "apply.dry_run" faux
    Et le JSON a "apply.confirmed" vrai
    Et la liste JSON "apply.operations" contient 3 éléments
    # Les tickets d'abord (du plus récemment modifié au plus ancien), puis la démo.
    Et le JSON a "apply.operations[target=feature/TEST-1].command" égal à "jgit feature rebase TEST-1"
    Et le JSON a "apply.operations[target=feature/TEST-1].status" égal à "done"
    Et le JSON a "apply.operations[target=feature/TEST-2].command" égal à "jgit feature rebase TEST-2"
    Et le JSON a "apply.operations[target=feature/TEST-2].status" égal à "done"
    Et le JSON a "apply.operations[2].kind" égal à "demo"
    Et le JSON a "apply.operations[2].command" égal à "jgit demo rebase sprint12"
    Et le JSON a "apply.operations[2].status" égal à "done"
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-2"
    Et le fichier "src/preprod.txt" existe sur la branche distante "demo/sprint12"
    Et la démo distante "demo/sprint12" contient dans l'ordre les tickets :
      | feature/TEST-1 |
      | feature/TEST-2 |
    Et la sortie contient "Appliqué : 3 sur 3."
    # On revient là où l'on était, sans les branches créées en route.
    Et je suis sur la branche "develop"
    Et la branche locale "feature/TEST-2" n'existe pas
    Et la branche locale "__PR__feature/TEST-2" n'existe pas
    Et aucune opération jgit n'est en pause
    Et aucune copie de travail temporaire ne reste

  Scénario: Les tickets des autres ne sont pas touchés
    Étant donné "Camille" pousse le fichier "src/notes.txt" contenant "notes" sur la branche "feature/TEST-2" avec le message "Ajoute des notes"
    Et je note l'état de la branche distante "feature/TEST-2"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit audit tickets --apply --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et la liste JSON "apply.operations" contient 1 éléments
    Et le JSON a "apply.operations[0].command" égal à "jgit feature rebase TEST-1"
    Et le JSON a "apply.left_aside[0].ticket" égal à "feature/TEST-2"
    Et le JSON a "apply.left_aside[0].reason" égal à "not_mine"
    Et le JSON a "apply.left_aside[0].concerned[0]" égal à "Camille"
    Et la branche distante "feature/TEST-2" est inchangée
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-1"
    Et la sortie contient "1 ticket(s) d'autres personnes, à rebaser par elles : Camille (1)"

  Scénario: Ce qui coince est laissé de côté, le reste est appliqué
    Étant donné "Camille" pousse le fichier "src/app.txt" contenant "version de develop" sur la branche "develop" avec le message "Modifie app.txt dans develop"
    Et je note l'état de la branche distante "feature/TEST-1"
    Quand je lance "jgit audit --apply --json" en lisant le JSON
    Alors jgit se termine avec le code 3
    Et la liste JSON "apply.operations" contient 1 éléments
    Et le JSON a "apply.operations[0].command" égal à "jgit feature rebase TEST-2"
    Et le JSON a "apply.operations[0].status" égal à "done"
    Et le JSON a "tickets[ticket=feature/TEST-1].status" égal à "conflicts"
    Et le fichier "src/app.txt" de la branche distante "feature/TEST-2" contient "version de develop"
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: --dry-run montre le plan sans rien appliquer
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je note l'état de la branche distante "feature/TEST-1"
    Quand je lance "jgit audit --apply --dry-run --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "apply.dry_run" vrai
    Et le JSON a "apply.confirmed" faux
    Et le JSON a "apply.operations[0].status" égal à "planned"
    Et la sortie contient "jgit feature rebase TEST-1"
    Et la sortie contient "--dry-run : rien n'a été appliqué."
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "demo/sprint12" est inchangée

  Scénario: Le plan se confirme, et peut se refuser
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je note l'état de la branche distante "feature/TEST-1"
    Quand je lance "jgit audit --apply" et que je réponds aux questions :
      | Appliquer le plan ci-dessus | n |
    Alors jgit se termine sans erreur
    Et la sortie contient "Rien n'a été appliqué."
    Et la branche distante "feature/TEST-1" est inchangée
    Et la branche distante "demo/sprint12" est inchangée

  # Un ticket créé avant que jgit enregistre la branche d'origine : sa base est
  # supposée, et une supposition ne réécrit pas une branche toute seule.
  Scénario: Un ticket à base supposée est listé, pas rebasé
    Étant donné je crée la branche locale "ripolin" depuis "develop"
    Et je me place sur la branche "ripolin"
    Et je commite le fichier "src/ripolin.txt" contenant "socle ripolin" avec le message "Socle ripolin"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et je lance "jgit demo create vitrine --based-on ripolin --no-interaction"
    Et un ancien ticket "feature/ANC-1" parti de "ripolin", sans branche d'origine enregistrée, ajoute le fichier "src/ancien.txt" contenant "ancien"
    Et "Dominique" pousse le fichier "src/ripolin2.txt" contenant "suite" sur la branche "ripolin" avec le message "Suite de ripolin"
    Et je note l'état de la branche distante "feature/ANC-1"
    Quand je lance "jgit audit --apply --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "apply.left_aside[0].ticket" égal à "feature/ANC-1"
    Et le JSON a "apply.left_aside[0].reason" égal à "inferred_base"
    Et le JSON a "apply.left_aside[0].command" égal à "jgit feature rebase ANC-1 --based-on ripolin"
    Et la sortie contient "feature/ANC-1 — base supposée ripolin, à vérifier avant de lancer : jgit feature rebase ANC-1 --based-on ripolin"
    Et la branche distante "feature/ANC-1" est inchangée
    # La démo partie de ripolin, elle, est remise à jour.
    Et le fichier "src/ripolin2.txt" existe sur la branche distante "demo/vitrine"

  Scénario: Rien à appliquer quand tout est à jour
    Quand je lance "jgit audit --apply"
    Alors jgit se termine sans erreur
    Et la sortie contient "Rien à appliquer sans conflit."
    Et la branche distante "demo/sprint12" est inchangée

  # --apply réécrit des branches : comme pour une démo, jgit ne range pas le
  # travail en cours à la place de son auteur.
  Scénario: Un espace de travail modifié est refusé
    Étant donné un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je note l'état de la branche distante "feature/TEST-1"
    Et je modifie le fichier "src/brouillon.txt" avec "en cours"
    Quand je lance "jgit audit --apply --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "worktree_dirty"
    Et le fichier de travail "src/brouillon.txt" contient "en cours"
    Et la branche distante "feature/TEST-1" est inchangée

  Scénario: --apply ne s'utilise qu'avec jgit audit
    Quand je lance "jgit demo list --apply --json" en lisant le JSON
    Alors jgit se termine avec le code 1
    Et le JSON a "error.code" égal à "usage"
    Et le JSON a "error.message" qui contient "jgit audit"
