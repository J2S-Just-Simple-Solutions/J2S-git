# language: fr
Fonctionnalité: jgit tourne sur macOS et sous Linux, et nulle part ailleurs
  jgit vit sur les postes des développeurs (macOS) et dans les conteneurs et
  agents Jenkins (Linux). La suite de tests est jouée sur les deux.

  Tout autre système est refusé avant la moindre action : personne n'y a
  vérifié que les outils de base se comportent comme jgit l'attend, et un tel
  écart — « tail -r », absent de GNU — a déjà vidé une branche de travail en
  silence en annonçant « Rebase terminé avec succès ».

  Contexte:
    Étant donné un projet git initialisé pour jgit

  Scénario: Une commande fonctionne sous Linux
    Étant donné le système détecté est "Linux"
    Quand je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-1" existe

  Scénario: Une commande est refusée sur un système non supporté
    Étant donné le système détecté est "FreeBSD"
    Quand je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "jgit ne fonctionne que sur macOS et Linux (système détecté : FreeBSD)."
    Et la sortie contient "docs/05-portabilite.md"
    Et la branche distante "feature/TEST-1" n'existe pas
    Et la branche locale "feature/TEST-1" n'existe pas

  # C'est la commande la plus dangereuse : sans le garde-fou, un écart de
  # comportement d'un outil système peut écraser la branche sur le serveur.
  Scénario: Le rebase est refusé avant toute réécriture d'historique
    Étant donné je lance "jgit feature start TEST-2 --no-interaction --no-open"
    Et je commite le fichier "src/travail.txt" contenant "mon travail" avec le message "Mon travail"
    Et je pousse la branche courante
    Et je note l'état de la branche distante "feature/TEST-2"
    Et le système détecté est "FreeBSD"
    Quand je lance "jgit feature rebase TEST-2 --no-interaction"
    Alors jgit se termine en erreur
    Et la sortie contient "jgit ne fonctionne que sur macOS et Linux"
    Et la sortie ne contient pas "Rebase terminé avec succès"
    Et la branche distante "feature/TEST-2" est inchangée
    Et le fichier "src/travail.txt" existe sur la branche distante "feature/TEST-2"

  # Le diagnostic doit rester lisible : on doit pouvoir demander l'aide depuis
  # n'importe quel système pour comprendre ce que jgit attend.
  Scénario: L'aide reste accessible sur un système non supporté
    Étant donné le système détecté est "FreeBSD"
    Quand je lance "jgit --help"
    Alors jgit se termine sans erreur
    Et la sortie contient "Usage:"

  # Installé dans le PATH par un lien (/usr/local/bin/jgit, image Docker), jgit
  # doit retrouver ses modules à côté du vrai jgit.sh, pas à côté du lien.
  Scénario: jgit fonctionne lorsqu'il est appelé par un lien symbolique
    Étant donné jgit est installé par un lien symbolique
    Quand je lance "jgit feature start TEST-3 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-3" existe

  # Un journal Jenkins ou une IA qui lit la sortie n'a que faire des séquences
  # ANSI : la couleur est réservée au terminal.
  Scénario: Hors d'un terminal, la sortie n'est pas colorée
    Quand je lance "jgit feature start TEST-4 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie contient "JGit va créer la branche feature/TEST-4"
    Et la sortie ne contient aucune séquence de couleur

  Scénario: Sans variable TERM, tput ne pollue pas la sortie
    Étant donné le terminal n'est pas défini
    Quand je lance "jgit feature start TEST-5 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la sortie ne contient aucune séquence de couleur

  # Cas typique d'un agent de CI : un clone --depth n'a ni les commits d'init
  # ni la branche d'origine. Mieux vaut refuser que conclure à tort.
  Scénario: Un clone superficiel est refusé avant toute action
    Étant donné le dépôt de travail est un clone superficiel
    Quand je lance "jgit feature start TEST-6 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "Ce dépôt est un clone superficiel (--depth) : jgit a besoin de l'historique complet."
    Et la sortie contient "git fetch --unshallow origin"
    Et la branche distante "feature/TEST-6" n'existe pas

  # Autre cas de CI : un clone réduit à une branche. jgit rapatrie malgré tout
  # toutes les branches du serveur, sinon develop lui paraîtrait inexistante.
  Scénario: Un clone réduit à une seule branche fonctionne
    Étant donné le dépôt de travail est un clone de la seule branche "main"
    Quand je lance "jgit feature start TEST-7 --no-interaction --no-open"
    Alors jgit se termine sans erreur
    Et la branche distante "feature/TEST-7" est partie de "develop"

  Scénario: Sans identité git, jgit refuse avant de créer quoi que ce soit
    Étant donné aucune identité git n'est configurée
    Quand je lance "jgit feature start TEST-8 --no-interaction --no-open"
    Alors jgit se termine en erreur
    Et la sortie contient "Aucune identité git n'est configurée : jgit ne peut pas créer de commit."
    Et la sortie contient "git config --global user.email"
    Et la branche distante "feature/TEST-8" n'existe pas
    Et la branche distante "__PR__feature/TEST-8" n'existe pas
