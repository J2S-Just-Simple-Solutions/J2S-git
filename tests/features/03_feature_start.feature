# language: fr
Fonctionnalité: Création d'une feature ou d'un hotfix
  « jgit feature start » crée une paire de branches : la branche de travail et
  la branche __PR__ qui lui sert de base de PR. Le scope détermine la branche de
  référence : develop pour une feature, main pour un hotfix.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je me place sur la branche "develop"
    Et je commite le fichier "src/preprod.txt" contenant "déjà en préprod" avec le message "Contenu déjà livré en préprod"
    Et je pousse la branche courante

  Scénario: Une feature se base sur develop
    Quand je lance "jgit feature start TEST-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et la sortie contient "qui se basera sur la branche"
    Et je suis sur la branche "feature/TEST-1"
    Et la branche distante "feature/TEST-1" existe
    Et la branche distante "__PR__feature/TEST-1" existe
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-1"
    Et le fichier "src/preprod.txt" existe sur la branche distante "__PR__feature/TEST-1"

  Scénario: Un hotfix se base sur main
    Quand je lance "jgit hotfix start URGENT-1 --no-interaction"
    Alors jgit se termine sans erreur
    Et je suis sur la branche "hotfix/URGENT-1"
    Et la branche distante "hotfix/URGENT-1" existe
    Et la branche distante "__PR__hotfix/URGENT-1" existe
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "hotfix/URGENT-1"
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "__PR__hotfix/URGENT-1"
    Et GitHub a reçu "--base=__PR__hotfix/URGENT-1"
    Et GitHub a reçu "--head=hotfix/URGENT-1"
    Et GitHub a reçu "--title URGENT-1"
    Et GitHub a reçu "--label NFR"

  Scénario: La branche de PR ne reste pas en local
    Quand je lance "jgit feature start TEST-2 --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche locale "feature/TEST-2" existe
    Et la branche locale "__PR__feature/TEST-2" n'existe pas
    Et le dernier commit de "__PR__feature/TEST-2" contient "[jgit] INIT feature/TEST-2 [empty_commit]"
    Et le dernier commit de "feature/TEST-2" contient "START feature/TEST-2 [empty_commit]"

  Scénario: --based-on impose la branche de référence
    Quand je lance "jgit feature start TEST-3 --based-on main --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-3" existe
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "feature/TEST-3"

  Scénario: --based-on sur une branche inconnue est refusé
    Quand je lance "jgit feature start TEST-4 --based-on inexistante --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La branche référence 'inexistante' n'existe pas."
    Et la branche distante "feature/TEST-4" n'existe pas
    Et la branche locale "feature/TEST-4" n'existe pas

  Scénario: --no-open crée les branches sans ouvrir de PR
    Quand je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "Skipping pull request creation (--no-open)."
    Et la branche distante "feature/TEST-5" existe
    Et la branche distante "__PR__feature/TEST-5" existe
    Et GitHub n'a pas reçu "pr create"
    Et GitHub a reçu exactement 0 appels

  Scénario: Refuser la confirmation n'a aucun effet sur le dépôt
    Quand je lance "jgit feature start TEST-6" et que je réponds aux questions :
      | Souhaitez-vous continuer | n |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche locale "feature/TEST-6" n'existe pas
    Et la branche distante "feature/TEST-6" n'existe pas
    Et la branche distante "__PR__feature/TEST-6" n'existe pas
    Et GitHub a reçu exactement 0 appels

  Scénario: Relancer start sur une feature existante réutilise la branche locale
    Quand je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Quand je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "Exists in remote and local"
    Et la sortie contient "Use local branch"
    Et je suis sur la branche "feature/TEST-7"
    Et GitHub a reçu exactement 0 appels

  Scénario: Une feature déjà sur GitHub mais absente en local est rapatriée
    Quand je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Quand je me place sur la branche "develop"
    Et je supprime la branche locale "feature/TEST-8"
    Et je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "Exists in remote but not in local"
    Et la sortie contient "Use remote branch"
    Et la branche locale "feature/TEST-8" existe
    Et je suis sur la branche "feature/TEST-8"

  # La situation réelle : la feature a été livrée et sa branche nettoyée sur le
  # serveur, mais la copie locale du développeur est restée.
  Scénario: Une branche locale sans équivalent distant fait suspecter un merge
    Étant donné je lance "jgit feature start TEST-9 --no-interaction --no-open"
    Et la branche "feature/TEST-9" est supprimée sur GitHub
    Quand je lance "jgit feature start TEST-9 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "Exists in local and not in remote"
    Et la sortie contient "Is this feature already merged ?"
    Et la branche distante "feature/TEST-9" n'existe pas
    Et GitHub a reçu exactement 0 appels

  # C'est l'état de tout clone frais : seule la branche par défaut est une
  # branche locale, develop n'existe que sous forme de origin/develop. Se
  # rabattre sur main ici ferait partir la feature de la production.
  Scénario: Sans develop en local, jgit utilise quand même la préprod du serveur
    Étant donné je me place sur la branche "main"
    Et je supprime la branche locale "develop"
    Quand je lance "jgit feature start TEST-10 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "qui se basera sur la branche develop"
    Et la branche distante "feature/TEST-10" existe
    Et le fichier "src/preprod.txt" existe sur la branche distante "feature/TEST-10"

  # Le repli sur master/main ne concerne que les projets qui n'ont pas de
  # préprod du tout, nulle part.
  Scénario: Sans préprod nulle part, jgit se replie sur la production
    Étant donné je me place sur la branche "main"
    Et je supprime la branche locale "develop"
    Et la branche "develop" est supprimée sur GitHub
    Quand je lance "jgit feature start TEST-17 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "qui se basera sur la branche main"
    Et la branche distante "feature/TEST-17" existe
    Et le fichier "src/preprod.txt" n'existe pas sur la branche distante "feature/TEST-17"

  # Supprimer develop et main en local ne suffit plus : jgit les retrouve sur le
  # serveur, et c'est voulu. Le seul cas réel où aucune référence n'existe est un
  # projet dont les branches portent d'autres noms, sans .jgit/conf_local.sh pour
  # le lui dire.
  #
  # get_reference_branch est appelée en substitution de commande : son message
  # doit partir sur stderr et l'échec passer par le code de retour, sinon il est
  # capturé comme un nom de branche et le diagnostic devient illisible.
  Scénario: Sans aucune branche de référence, le refus est explicite
    Étant donné le projet utilise "trunk" au lieu de develop, master ou main
    Quand je lance "jgit feature start TEST-11 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "Erreur : aucune branche de référence valide trouvée."
    Et la sortie ne contient pas "La branche référence"
    Et la branche distante "feature/TEST-11" n'existe pas

  Scénario: Valider sans rien saisir applique la réponse par défaut
    Quand je lance "jgit feature start TEST-12" et que je réponds aux questions :
      | Souhaitez-vous continuer |  |
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-12" existe

  Scénario: Une réponse autre que y vaut refus
    Quand je lance "jgit feature start TEST-13" et que je réponds aux questions :
      | Souhaitez-vous continuer | bidule |
    Alors jgit se termine en erreur
    Et la sortie contient "Opération annulée."
    Et la branche distante "feature/TEST-13" n'existe pas

  # Les deux branches sont déjà poussées quand gh échoue : jgit doit le dire
  # sans laisser croire qu'il faut tout recommencer.
  Scénario: Un échec de gh pr create est signalé
    Étant donné le client gh échoue pour les commandes "pr create"
    Quand je lance "jgit feature start TEST-14 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "La pull request n'a pas pu être créée sur GitHub."
    Et la sortie contient "il ne reste que la PR à ouvrir."
    Et la branche distante "feature/TEST-14" existe
    Et la branche distante "__PR__feature/TEST-14" existe
