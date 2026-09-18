# language: fr
Fonctionnalité: Branche d'origine et fraîcheur
  Toute branche fabriquée par jgit inscrit sa branche de départ dans le corps de
  son commit d'initialisation. « util check_rebase » s'en sert pour dire, à tout
  instant, si la branche est encore à jour sur cette base et si le rebase
  passerait. Une branche créée avant ce mécanisme n'a pas cette trace : la
  commande refuse de répondre plutôt que de supposer develop.

  Contexte:
    Étant donné un projet git initialisé pour jgit

  # --- L'enregistrement -----------------------------------------------------

  Scénario: Une feature enregistre la branche dont elle part
    Quand je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-1" est partie de "develop"
    Et la branche distante "__PR__feature/TEST-1" est partie de "develop"

  # La trace ne doit jamais remonter dans le sujet : c'est ce qui la rend
  # invisible dans un git log --oneline comme dans la liste des commits de
  # GitHub, où elle n'apprendrait rien à personne.
  Scénario: La branche d'origine reste hors des sujets de commit
    Quand je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et aucun sujet de commit de la branche distante "feature/TEST-2" ne montre la branche d'origine
    Et l'historique de "feature/TEST-2" contient "[jgit] INIT feature/TEST-2 [empty_commit]"

  Scénario: Un hotfix enregistre la production
    Quand je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "hotfix/URGENT-1" est partie de "main"

  Scénario: --based-on est ce qui est enregistré
    Quand je lance "jgit feature start TEST-3 --based-on main --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-3" est partie de "main"

  Scénario: Une démo enregistre sa base
    Quand je lance "jgit demo start salon --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo_salon" est partie de "main"

  Scénario: Une release enregistre la production
    Quand je lance "jgit release start"
    Alors jgit se termine sans erreur
    Et la branche distante "release/1.1.0" est partie de "main"

  # Un restart ne choisit pas de base : il reprend celle que porte la branche de
  # PR, seule à survivre au squash-and-merge.
  Scénario: Un restart conserve la branche d'origine
    Étant donné je lance "jgit feature start TEST-4 --based-on main --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-4" est squash-mergée sur GitHub avec le message "TEST-4 (#4)"
    Quand je lance "jgit feature restart TEST-4 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-4" est partie de "main"

  # --- util check_rebase ----------------------------------------------------

  Scénario: Une branche fraîchement créée est à jour
    Étant donné je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Quand je lance "jgit util check_rebase"
    Alors jgit se termine avec le code 0
    Et la sortie contient "Basée sur : develop"
    Et la sortie contient "à jour sur develop, il n'y a rien à rebaser."

  Scénario: Une branche en retard qui se rebase proprement
    Étant donné je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit util check_rebase"
    Alors jgit se termine avec le code 2
    Et la sortie contient "en retard de 1 commit(s) sur develop."
    Et la sortie contient "Rebase    : passerait sans conflit."
    Et la sortie contient "jgit feature rebase TEST-6"
    Et je suis sur la branche "feature/TEST-6"
    Et l'espace de travail est propre

  Scénario: Une branche en retard dont le rebase conflicterait
    Étant donné je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Et je commite le fichier "src/partage.txt" contenant "ma version" avec le message "Ma version"
    Et un autre développeur pousse le fichier "src/partage.txt" contenant "sa version" sur la branche "develop" avec le message "Sa version"
    Quand je lance "jgit util check_rebase"
    Alors jgit se termine avec le code 3
    Et la sortie contient "Rebase    : des conflits sont à prévoir."
    Et la sortie contient "--squash"
    Et je suis sur la branche "feature/TEST-7"

  # La vérification rejoue un rebase à blanc puis efface tout : aucune branche
  # temporaire ne doit rester derrière elle.
  Scénario: La vérification ne laisse aucune trace
    Étant donné je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et un autre développeur pousse le fichier "src/b.txt" contenant "B" sur la branche "develop" avec le message "Commit B"
    Et je note l'état de la branche distante "feature/TEST-8"
    Et je note l'état de la branche distante "develop"
    Quand je lance "jgit util check_rebase"
    Alors jgit se termine avec le code 2
    Et la branche distante "feature/TEST-8" est inchangée
    Et la branche distante "develop" est inchangée

  Scénario: Une autre branche s'interroge avec --from
    Étant donné je lance "jgit feature start TEST-10 --no-interaction --no-open"
    Et je me place sur la branche "develop"
    Quand je lance "jgit util check_rebase --from feature/TEST-10"
    Alors jgit se termine avec le code 0
    Et la sortie contient "Branche   : feature/TEST-10"
    Et je suis sur la branche "develop"

  # --- Les anciennes branches -----------------------------------------------

  # Une branche que jgit n'a pas créée est, de son point de vue, une branche
  # d'avant le mécanisme : elle ne porte aucune trace de son point de départ.
  Scénario: Une branche sans trace obtient un refus, pas une supposition
    Étant donné je crée la branche locale "feature/ancienne" depuis "develop"
    Et je pousse la branche courante
    Quand je lance "jgit util check_rebase --from feature/ancienne"
    Alors jgit se termine avec le code 1
    Et la sortie contient "Désolé : jgit ne sait pas répondre pour les anciennes branches."
    Et la sortie contient "jgit util verify_rebase --from feature/ancienne --into <branche_de_base>"

  # Le piège à éviter : les commits d'init remontent dans les branches livrées
  # (une release intègre l'historique des branches __PR__, main celui de la
  # release). Une vieille branche partant de là compte donc, dans ses ancêtres,
  # des commits porteurs d'une origine qui n'est pas la sienne.
  Scénario: Une ancienne branche n'hérite pas de la trace d'un ancêtre
    Étant donné je lance "jgit feature start TEST-11 --no-interaction --no-open"
    Et je commite le fichier "src/livre.txt" contenant "livré" avec le message "Fonctionnalité livrée"
    Et je pousse la branche courante
    Et la PR de "feature/TEST-11" est squash-mergée sur GitHub avec le message "TEST-11 (#11)"
    Et je lance "jgit release merge --from feature/TEST-11"
    Et je lance "jgit release finish"
    Et je récupère les nouveautés du remote
    Et je me place sur la branche "main"
    Et je crée la branche locale "hotfix/ancien" depuis "main"
    Et je pousse la branche courante
    Quand je lance "jgit util check_rebase --from hotfix/ancien"
    Alors jgit se termine avec le code 1
    Et la sortie contient "Désolé : jgit ne sait pas répondre pour les anciennes branches."

  # --- Les refus de check_rebase --------------------------------------------

  Scénario: Un espace de travail sale interdit la vérification
    Étant donné je lance "jgit feature start TEST-12 --no-interaction --no-open"
    Et je modifie le fichier "src/app.txt" avec "travail en cours"
    Quand je lance "jgit util check_rebase"
    Alors jgit se termine avec le code 1
    Et la sortie contient "La vérification rejoue un rebase à blanc : elle a besoin d'un dépôt propre."
    Et le fichier de travail "src/app.txt" contient "travail en cours"

  Scénario: Une branche inconnue est refusée
    Quand je lance "jgit util check_rebase --from feature/inexistante"
    Alors jgit se termine avec le code 1
    Et la sortie contient "La branche feature/inexistante n'existe pas (ni en local ni sur origin)."

  Scénario: Deux branches sources sont refusées
    Quand je lance "jgit util check_rebase --from develop --from main"
    Alors jgit se termine avec le code 1
    Et la sortie contient "une seule branche à la fois, via --from."

  Scénario: Une branche en positionnel renvoie vers --from
    Quand je lance "jgit util check_rebase develop"
    Alors jgit se termine en erreur
    Et la sortie contient "Pour désigner une branche, utilisez --from develop."

  # --- Le rebase et la base enregistrée --------------------------------------

  # Jusqu'ici le rebase visait la référence du projet sans rien demander : une
  # feature partie d'une démo ou d'un hotfix se retrouvait silencieusement
  # rejouée sur develop.
  Scénario: Le rebase propose la base enregistrée quand elle diffère de la référence
    Étant donné je lance "jgit feature start TEST-13 --based-on main --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Livraison en production"
    Quand je lance "jgit feature rebase TEST-13" et que je réponds aux questions :
      | est partie de main                          | y |
      | Souhaitez-vous continuer                    | y |
      | Confirmez-vous que le rebase                | y |
    Alors jgit se termine sans erreur
    Et la sortie contient "est partie de main, et non de la référence du projet develop."
    Et le fichier "src/prod.txt" existe sur la branche distante "feature/TEST-13"
    Et la branche distante "feature/TEST-13" est partie de "main"

  Scénario: Répondre non au rebase renvoie sur la référence du projet
    Étant donné je lance "jgit feature start TEST-14 --based-on main --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit feature rebase TEST-14" et que je réponds aux questions :
      | est partie de main                          | n |
      | Souhaitez-vous continuer                    | y |
      | Confirmez-vous que le rebase                | y |
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-14"
    Et la branche distante "feature/TEST-14" est partie de "develop"
    Et la branche distante "__PR__feature/TEST-14" est partie de "develop"

  # La réponse par défaut est la base enregistrée : --no-interaction l'applique.
  Scénario: Sans interaction le rebase reste sur la base enregistrée
    Étant donné je lance "jgit feature start TEST-15 --based-on main --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Livraison en production"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit feature rebase TEST-15 --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/prod.txt" existe sur la branche distante "feature/TEST-15"
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "feature/TEST-15"
    Et la branche distante "feature/TEST-15" est partie de "main"

  # --based-on explicite reste le dernier mot : aucune question n'est posée.
  Scénario: --based-on remplace la base enregistrée sans poser de question
    Étant donné je lance "jgit feature start TEST-16 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/prod.txt" contenant "prod" sur la branche "main" avec le message "Livraison en production"
    Quand je lance "jgit feature rebase TEST-16 --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie ne contient pas "et non de la référence du projet"
    Et la branche distante "feature/TEST-16" est partie de "main"
    Et la branche distante "__PR__feature/TEST-16" est partie de "main"

  # --- Quand la base enregistrée a disparu -----------------------------------

  # Le cas se produit pour de bon : une démo sert de base, puis on la supprime
  # une fois la démo passée. Se rabattre en silence sur develop déplacerait la
  # branche — et le résultat partirait en push --force.
  Scénario: Le rebase refuse quand la base enregistrée n'existe plus
    Étant donné je lance "jgit demo start sprint12 --no-interaction"
    Et je lance "jgit feature start TEST-18 --based-on demo_sprint12 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint12"
    Et je lance "jgit demo remove --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je note l'état de la branche distante "feature/TEST-18"
    Et je note l'état de la branche distante "__PR__feature/TEST-18"
    Quand je lance "jgit feature rebase TEST-18 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base demo_sprint12 n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "C'est la branche d'origine de feature/TEST-18, enregistrée à sa création"
    Et la sortie contient "Rien n'a été modifié : ni vos branches, ni le serveur."
    Et la sortie contient "jgit feature rebase TEST-18 --based-on <branche>"
    Et la sortie contient "jgit feature rebase TEST-18 --based-on develop"
    Et la sortie contient "jgit util check_rebase --from feature/TEST-18"

  # Le refus doit être un refus : rien n'a bougé, ni sur le serveur, ni chez moi.
  Scénario: Le refus ne touche ni le serveur ni la branche de travail
    Étant donné je lance "jgit demo start sprint13 --no-interaction"
    Et je lance "jgit feature start TEST-19 --based-on demo_sprint13 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint13"
    Et je lance "jgit demo remove --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Et je note l'état de la branche distante "feature/TEST-19"
    Et je note l'état de la branche distante "__PR__feature/TEST-19"
    Quand je lance "jgit feature rebase TEST-19 --no-interaction"
    Alors jgit se termine en erreur
    Et la branche distante "feature/TEST-19" est inchangée
    Et la branche distante "__PR__feature/TEST-19" est inchangée
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "feature/TEST-19"
    Et l'historique local de "feature/TEST-19" ne contient pas "Livraison en préprod"
    Et la branche locale "jgit_rebase_feature/TEST-19" n'existe pas
    Et la branche distante "feature/TEST-19" est partie de "demo_sprint13"

  # Le remède donné par le message doit fonctionner du premier coup.
  Scénario: Relancer avec --based-on débloque la situation
    Étant donné je lance "jgit demo start sprint14 --no-interaction"
    Et je lance "jgit feature start TEST-20 --based-on demo_sprint14 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint14"
    Et je lance "jgit demo remove --no-interaction"
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit feature rebase TEST-20 --based-on develop --no-interaction"
    Alors jgit se termine sans erreur
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-20"
    Et le fichier "src/a.txt" existe sur la branche distante "feature/TEST-20"
    Et la branche distante "feature/TEST-20" est partie de "develop"
    Et la branche distante "__PR__feature/TEST-20" est partie de "develop"

  # La règle : une base introuvable se refuse de la même façon, qu'elle vienne
  # d'une saisie ou d'une valeur par défaut. Sans quoi une faute de frappe et
  # une release supprimée se diagnostiqueraient différemment, pour un problème
  # rigoureusement identique.
  Scénario: Saisie erronée et base enregistrée disparue donnent le même refus
    Étant donné je lance "jgit demo start sprint20 --no-interaction"
    Et je lance "jgit feature start TEST-22 --based-on demo_sprint20 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    # 1. la saisie est mauvaise
    Quand je lance "jgit feature rebase TEST-22 --based-on inexistante --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "Elle a été demandée par --based-on : vérifiez son orthographe."
    Et la sortie contient "Rien n'a été modifié : ni vos branches, ni le serveur."
    Et la sortie contient "jgit ne devine pas sur quelle branche vous vouliez partir"
    Et la sortie contient "jgit feature rebase TEST-22 --based-on <branche>"
    # 2. la valeur par défaut est mauvaise : mêmes phrases, seule la provenance change
    Étant donné je me place sur la branche "demo_sprint20"
    Et je lance "jgit demo remove --no-interaction"
    Quand je lance "jgit feature rebase TEST-22 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base demo_sprint20 n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "C'est la branche d'origine de feature/TEST-22, enregistrée à sa création"
    Et la sortie contient "Rien n'a été modifié : ni vos branches, ni le serveur."
    Et la sortie contient "jgit ne devine pas sur quelle branche vous vouliez partir"
    Et la sortie contient "jgit feature rebase TEST-22 --based-on <branche>"

  Scénario: feature start et demo start refusent dans les mêmes termes
    Quand je lance "jgit feature start TEST-23 --based-on inexistante --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "Elle a été demandée par --based-on : vérifiez son orthographe."
    Et la sortie contient "jgit feature start TEST-23 --based-on <branche>"
    Et la branche distante "feature/TEST-23" n'existe pas
    Quand je lance "jgit demo start vitrine --based-on inexistante --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base inexistante n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "Elle a été demandée par --based-on : vérifiez son orthographe."
    Et la sortie contient "jgit demo start vitrine --based-on <branche>"
    Et la branche distante "demo_vitrine" n'existe pas

  Scénario: Un hotfix refuse lui aussi, en nommant son propre scope
    Étant donné je lance "jgit demo start sprint15 --no-interaction"
    Et je lance "jgit hotfix start URGENT-9 --based-on demo_sprint15 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint15"
    Et je lance "jgit demo remove --no-interaction"
    Quand je lance "jgit hotfix rebase URGENT-9 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche de base demo_sprint15 n'existe pas (ni en local ni sur origin)."
    Et la sortie contient "jgit hotfix rebase URGENT-9 --based-on <branche>"
    Et la sortie contient "La référence du projet est main."

  Scénario: check_rebase refuse aussi, et renvoie vers le même remède
    Étant donné je lance "jgit demo start sprint16 --no-interaction"
    Et je lance "jgit feature start TEST-21 --based-on demo_sprint16 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et je me place sur la branche "demo_sprint16"
    Et je lance "jgit demo remove --no-interaction"
    Quand je lance "jgit util check_rebase --from feature/TEST-21"
    Alors jgit se termine avec le code 1
    Et la sortie contient "La branche d'origine demo_sprint16 n'existe plus (ni en local ni sur origin)."
    Et la sortie contient "jgit feature rebase TEST-21 --based-on <branche>"

  # Un rebase est aussi l'occasion de donner sa trace à une branche qui n'en a
  # pas : elle cesse d'être une ancienne branche.
  Scénario: Le rebase donne sa trace à une branche qui n'en avait pas
    Étant donné je lance "jgit feature start TEST-17 --no-interaction --no-open"
    Et je commite le fichier "src/a.txt" contenant "A" avec le message "Commit A"
    Et je pousse la branche courante
    Et un autre développeur pousse le fichier "src/preprod.txt" contenant "préprod" sur la branche "develop" avec le message "Livraison en préprod"
    Quand je lance "jgit feature rebase TEST-17 --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-17" est partie de "develop"
    Et la branche distante "__PR__feature/TEST-17" est partie de "develop"
