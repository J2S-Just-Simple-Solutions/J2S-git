# language: fr
Fonctionnalité: Les démos à l'ancien format (demo_<nom>)
  La première version des démos fabriquait des branches demo_<nom>, rejouées
  par-dessus chaque ticket ajouté. Il en existe encore sur les dépôts : jgit
  les liste et les lit, refuse de les modifier, et sait les convertir au format
  actuel (demo/<nom>) avec les mêmes tickets.

  Contexte:
    Étant donné un projet git initialisé pour jgit
    Et je lance "jgit feature start TEST-1 --no-interaction --no-open"
    Et je commite le fichier "src/feature1.txt" contenant "feature 1" avec le message "Ajoute la feature 1"
    Et je pousse la branche courante
    Et je lance "jgit hotfix start URGENT-1 --no-interaction --no-open"
    Et je commite le fichier "src/correctif.txt" contenant "correctif" avec le message "Applique le correctif"
    Et je pousse la branche courante
    Et je me place sur la branche "develop"
    Et une démo à l'ancien format "vitrine" basée sur "develop" contient les tickets "feature/TEST-1 hotfix/URGENT-1"

  Scénario: Une démo à l'ancien format figure dans la liste
    Quand je lance "jgit demo list --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demos[0].name" égal à "vitrine"
    Et le JSON a "demos[0].branch" égal à "demo_vitrine"
    Et le JSON a "demos[0].format" égal à "legacy"
    Et le JSON a "demos[0].read_only" vrai
    Et le JSON a "demos[0].base" égal à "develop"
    Et la sortie contient "ancien format : jgit demo migrate vitrine"

  Scénario: Une démo à l'ancien format se lit
    Quand je lance "jgit demo show vitrine --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "demo.format" égal à "legacy"
    Et la liste JSON "tickets" contient 2 éléments
    Et le JSON a "tickets[0].ticket" égal à "feature/TEST-1"
    Et le JSON a "tickets[1].ticket" égal à "hotfix/URGENT-1"
    Et le JSON a "release_command" égal à "jgit release merge --from feature/TEST-1 --from hotfix/URGENT-1"
    Et la sortie contient "ancien format, lecture seule"
    Et la sortie contient "jgit demo migrate vitrine"

  Scénario: Une démo à l'ancien format ne se modifie pas
    Quand je lance "jgit demo add vitrine --from feature/TEST-1 --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "legacy_format"
    Et le JSON a "error.hint" égal à "Pour la convertir au format actuel : jgit demo migrate vitrine"

  Scénario: migrate recrée la démo au format actuel, avec les mêmes tickets
    Quand je lance "jgit demo migrate vitrine --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "operation" égal à "migrate"
    Et le JSON a "branch" égal à "demo/vitrine"
    Et le JSON a "base" égal à "develop"
    Et la démo distante "demo/vitrine" contient dans l'ordre les tickets :
      | feature/TEST-1  |
      | hotfix/URGENT-1 |
    Et la branche distante "demo/vitrine" est partie de "develop"
    Et le fichier "src/feature1.txt" existe sur la branche distante "demo/vitrine"
    # L'ancienne est conservée : on la supprime quand on veut.
    Et la branche distante "demo_vitrine" existe
    Et la sortie contient "jgit demo delete demo_vitrine"
    Quand je lance "jgit demo show vitrine --json" en lisant le JSON
    Alors le JSON a "demo.format" égal à "v2"
    Et le JSON a "tickets[0].status" égal à "up_to_date"

  Scénario: Un ticket disparu depuis n'est pas repris par migrate
    Étant donné la branche "hotfix/URGENT-1" est supprimée sur GitHub
    Quand je lance "jgit demo migrate vitrine --no-interaction --json" en lisant le JSON
    Alors jgit se termine sans erreur
    Et le JSON a "dropped[0].ticket" égal à "hotfix/URGENT-1"
    Et le JSON a "dropped[0].reason" égal à "missing"
    Et la démo distante "demo/vitrine" contient dans l'ordre les tickets :
      | feature/TEST-1 |

  Scénario: Sans base enregistrée, migrate demande laquelle
    Étant donné une démo à l'ancien format "ancienne" sans base enregistrée contient les tickets "feature/TEST-1"
    Quand je lance "jgit demo migrate ancienne --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "base_unknown"
    Et le JSON a "error.hint" égal à "Nommez sa base : jgit demo migrate ancienne --based-on <branche>"
    Quand je lance "jgit demo migrate ancienne --based-on develop --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo/ancienne" est partie de "develop"

  Scénario: Une démo déjà au format actuel n'a rien à convertir
    Étant donné je lance "jgit demo create sprint12 --no-interaction"
    Quand je lance "jgit demo migrate sprint12 --no-interaction --json" en lisant le JSON
    Alors jgit se termine avec le code 2
    Et le JSON a "error.code" égal à "not_legacy"

  Scénario: Une démo à l'ancien format se supprime
    Quand je lance "jgit demo delete demo_vitrine --no-interaction"
    Alors jgit se termine sans erreur
    Et la branche distante "demo_vitrine" n'existe pas

  Scénario: demo list lancée depuis une démo montre cette démo
    Étant donné je récupère la branche distante "demo_vitrine" en local
    Et je me place sur la branche "demo_vitrine"
    Quand je lance "jgit demo list"
    Alors jgit se termine sans erreur
    Et la sortie contient "[déprécié] « jgit demo list (depuis demo_vitrine) » : utilisez désormais « jgit demo show vitrine »."
    Et la sortie contient "Démo vitrine (demo_vitrine)"
    Et la sortie contient "feature/TEST-1"
