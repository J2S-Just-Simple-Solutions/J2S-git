#!/bin/bash
#
# Mettre-a-jour-jgit.sh — met jgit à jour sur main, en transformant au
# besoin une installation faite depuis un zip en clone git du dépôt officiel.
# Ce programme est réutilisé par « jgit auto-update » pour les mises à jour.
#
# Usage, depuis le dossier contenant le fichier téléchargé :
#   chmod +x Mettre-a-jour-jgit.sh
#   ./Mettre-a-jour-jgit.sh
# Ce fichier contient tout le programme : aucun autre script à télécharger.
# Il est aussi le moteur de « jgit auto-update » : --installation désigne
# alors explicitement l'installation appelée, sans rechercher un alias.
#
# Le script vérifie l'installation avant de la remplacer. La préparation
# télécharge le dépôt (ou rafraîchit les références du clone existant).
# Au moindre doute, il s'arrête. Une fois les vérifications passées, il résume
# ce qu'il va faire et demande une seule confirmation, puis :
#
# - installation par zip :
#   1. renomme le dossier actuel en <dossier>.zip-sauvegarde-<date> (rien n'est
#      supprimé) ;
#   2. installe à la même place un clone git du dépôt officiel : l'alias jgit
#      continue de fonctionner sans être modifié ;
#   3. vérifie que jgit répond, et tente de restaurer l'ancien dossier sinon ;
#
# - déjà un clone git : met main à jour (git merge --ff-only sur le commit
#   récupéré et présenté), vérifie que jgit
#   répond, et tente de revenir à la version d'avant sinon.

set -uo pipefail

DEPOT_URL="git@github.com:J2S-Just-Simple-Solutions/J2S-git.git"
BRANCHE="main"
FICHIERS_SHELL=".zprofile .zshrc .zshenv .zlogin .bash_profile .bashrc .profile"
INSTALLATION=""
SANS_INTERACTION=false

if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] && command -v tput >/dev/null 2>&1; then
    VERT=$(tput setaf 2 2>/dev/null); ROUGE=$(tput setaf 1 2>/dev/null)
    GRAS=$(tput bold 2>/dev/null); NORMAL=$(tput sgr0 2>/dev/null)
else
    VERT=""; ROUGE=""; GRAS=""; NORMAL=""
fi

ok()     { printf '  %s✓%s %s\n' "$VERT" "$NORMAL" "$1"; }
etape()  { printf '\n%s%s%s\n' "$GRAS" "$1" "$NORMAL"; }
arret()  {
    printf '\n  %s✗ %s%s\n' "$ROUGE" "$1" "$NORMAL" >&2
    shift
    for ligne in "$@"; do printf '%s\n' "$ligne" | sed 's/^/    /' >&2; done
    printf '\nTransmettez ce message à la personne qui vous a envoyé ce script.\n' >&2
    exit 1
}

# Dossier de travail temporaire (clone, comparaison). Il est créé à côté de
# l'installation pour que l'échange final soit un simple renommage, et il est
# supprimé à la sortie, sauf si une restauration échoue.
TRAVAIL=""
RESTAURATION=""
nettoyer() {
    local statut=$? conserver=""
    trap - EXIT INT TERM HUP
    case "$RESTAURATION" in
        zip)
            if [ -d "$SAUVEGARDE" ]; then
                if { [ ! -e "$DOSSIER" ] || mv "$DOSSIER" "$TRAVAIL/clone-rejete"; } \
                    && mv "$SAUVEGARDE" "$DOSSIER"; then
                    printf '\nAncien dossier remis en place : %s\n' "$DOSSIER" >&2
                else
                    printf '\nÉCHEC de la restauration. Sauvegarde : %s ; clone : %s\n' "$SAUVEGARDE" "$TRAVAIL" >&2
                    conserver=1
                fi
            fi ;;
        clone)
            if git -C "$DOSSIER" reset --quiet --keep "$AVANT"; then
                printf '\nClone revenu à la version précédente : %s\n' "$AVANT" >&2
            else
                printf '\nÉCHEC de la restauration. Version précédente à restaurer : %s\n' "$AVANT" >&2
            fi ;;
    esac
    if [ -z "$conserver" ] && [ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ]; then
        rm -rf "$TRAVAIL"
    fi
    exit "$statut"
}
trap nettoyer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

export GIT_TERMINAL_PROMPT=0
git_sur() { git -c core.quotePath=false -c core.autocrlf=false "$@"; }

# Suit les liens symboliques jusqu'au vrai fichier (readlink -f n'existe pas
# sur le macOS de base).
vrai_chemin() {
    f=$1; n=0
    while [ -L "$f" ]; do
        n=$((n + 1)); [ "$n" -gt 20 ] && return 1
        cible=$(readlink "$f") || return 1
        case "$cible" in
            /*) f=$cible ;;
            *)  f=$(dirname "$f")/$cible ;;
        esac
    done
    d=$(cd -P "$(dirname "$f")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$d" "$(basename "$f")"
}

# Extrait le chemin d'une ligne « alias jgit=… » : guillemets simples, doubles,
# ou rien ; « bash » ou « sh » devant le chemin est accepté. Tout le reste
# (arguments, variables autres que $HOME, commandes) est un doute.
chemin_alias() {
    local valeur reste
    valeur=${1#*jgit=}
    case "$valeur" in
        \'*)
            valeur=${valeur#\'}
            case "$valeur" in *\'*) ;; *) return 1 ;; esac
            reste=${valeur#*\'}; valeur=${valeur%%\'*} ;;
        \"*)
            valeur=${valeur#\"}
            case "$valeur" in *\"*) ;; *) return 1 ;; esac
            reste=${valeur#*\"}; valeur=${valeur%%\"*} ;;
        *) reste="" ;;
    esac
    reste=$(printf '%s' "$reste" | sed 's/^[[:space:]]*//')
    case "$reste" in "" | \#*) ;; *) return 1 ;; esac
    case "$valeur" in
        "bash "*) valeur=${valeur#bash } ;;
        "sh "*)   valeur=${valeur#sh } ;;
    esac
    case "$valeur" in
        "~/"*)       valeur="$HOME/${valeur#\~/}" ;;
        '$HOME/'*)   valeur="$HOME/${valeur#\$HOME/}" ;;
        '${HOME}/'*) valeur="$HOME/${valeur#\$\{HOME\}/}" ;;
    esac
    case "$valeur" in
        /*/jgit.sh) ;;
        *) return 1 ;;
    esac
    case "$valeur" in
        *'$'* | *'`'* | *[[:space:]]* | *';'* | *'&'* | *'|'* | *'<'* | *'>'* | *'('* | *')'* | *'*'* | *'?'* | *'['* | *'\'*) return 1 ;;
    esac
    printf '%s\n' "$valeur"
}

# Pose la question finale ; toute autre réponse que « o » ou « oui » annule.
confirmer() {
    if [ "$SANS_INTERACTION" = true ]; then
        printf '[no-interaction] %s -> non\nAnnulé. Installation inchangée.\n' "$1"
        exit 0
    fi
    [ -r /dev/tty ] || arret "Pas de terminal pour demander la confirmation : lancez « bash $0 » dans un terminal."
    printf '%s%s [o/N] %s' "$GRAS" "$1" "$NORMAL"
    read -r reponse < /dev/tty || reponse=""
    case "$reponse" in
        o | O | oui | OUI | Oui) ;;
        *) printf '\nAnnulé. Rien n'"'"'a été modifié.\n'; exit 0 ;;
    esac
}

jgit_repond() { (cd "$HOME" && bash "$1/jgit.sh" help >/dev/null 2>&1); }

# Propre = aucun fichier suivi modifié. Les fichiers non suivis (.DS_Store du
# Finder, notes…) ne comptent pas : l'avance rapide refuse d'elle-même d'en
# écraser un, et --no-overwrite-ignore protège les fichiers ignorés.
clone_propre() {
    local etat
    etat=$(git -C "$1" status --porcelain --untracked-files=no) || return 1
    [ -z "$etat" ]
}

# « 1.0.0 (2026-10-19) » : le numéro de version le plus haut posé sur le
# commit, sinon la description git la plus proche.
decrire() {
    tag=$(git -C "$1" tag --points-at "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$tag" ] || tag=$(git -C "$1" describe --tags "$2" 2>/dev/null || git -C "$1" rev-parse --short "$2")
    printf '%s (%s)\n' "$tag" "$(git -C "$1" log -1 --format=%cd --date=short "$2")"
}

# Le prompt à donner à une IA pour configurer SSH. Il est dans sa propre
# fonction : bash 3.2 analyse mal un heredoc avec apostrophes placé dans $( ).
texte_prompt_ssh() {
    sortie=$(printf '%s\n' "$1" | sed 's/^/    /'); cles=$2
    cat <<EOF
Je suis sur un Mac (macOS $(sw_vers -productVersion 2>/dev/null), $(uname -m)). Je dois pouvoir cloner un dépôt GitHub en SSH :

    git clone $DEPOT_URL

mais la connexion SSH à GitHub ne fonctionne pas. Voici ce que répond « ssh -T git@github.com » :

$sortie

Clés publiques présentes dans ~/.ssh : ${cles:-aucune}

Guide-moi pas à pas, une commande à la fois, en attendant mon retour entre chaque étape, jusqu'à ce que « ssh -T git@github.com » réponde « successfully authenticated » :
- si l'erreur parle de « Host key verification failed », vérifier l'empreinte de GitHub avec la documentation officielle avant de l'accepter ;
- regarder si j'ai déjà une clé, et si elle est chargée dans l'agent SSH et le trousseau macOS ;
- sinon, en créer une (ed25519) ;
- l'ajouter à mon compte GitHub (Settings → SSH and GPG keys) ;
- configurer ~/.ssh/config pour que macOS garde la phrase de passe dans le trousseau.
Mon compte GitHub fait partie de l'organisation J2S-Just-Simple-Solutions : si elle impose le SSO, rappelle-moi d'autoriser la clé (« Configure SSO »).
Ne me demande jamais ma clé privée ni mes mots de passe.
EOF
}

# Vérifie que la connexion SSH à GitHub fonctionne, sans rien modifier : pas de
# question, et GitHub n'est pas ajouté aux hôtes connus s'il n'y est pas. En cas
# d'échec, affiche un prompt à donner à une IA pour configurer SSH.
verifier_ssh() {
    sortie=$(ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no -o ConnectTimeout=10 git@github.com 2>&1 < /dev/null)
    if printf '%s' "$sortie" | grep -q "successfully authenticated"; then
        compte=$(printf '%s' "$sortie" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')
        ok "connexion SSH à GitHub${compte:+ (compte $compte)}"
        return 0
    fi
    case "$sortie" in
        *"Could not resolve"* | *"timed out"* | *"Network is unreachable"* | *"Connection refused"*)
            arret "GitHub est injoignable en SSH :" "$sortie" \
                  "Vérifiez la connexion internet (et le VPN), puis relancez." ;;
    esac
    cles=$(cd "$HOME/.ssh" 2>/dev/null && ls -- *.pub 2>/dev/null | tr '\n' ' ')
    prompt=$(texte_prompt_ssh "$sortie" "$cles")
    printf '\n  %s✗ La connexion SSH à GitHub ne fonctionne pas.%s\n' "$ROUGE" "$NORMAL" >&2
    printf '%s\n' "$sortie" | sed 's/^/    /' >&2
    printf '\n  Pour la configurer, donnez ce texte à une IA (Claude, ChatGPT…)' >&2
    if printf '%s\n' "$prompt" | LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8 pbcopy 2>/dev/null; then
        printf ' : il est déjà copié dans le presse-papiers.' >&2
    fi
    printf '\n\n%s\n%s\n%s\n' "-----------------------------------------------------------------------" \
        "$prompt" "-----------------------------------------------------------------------" >&2
    printf '\n%sRien n'"'"'a été modifié.%s Relancez ce script une fois la connexion SSH en place.\n' "$GRAS" "$NORMAL" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --installation)
            [ "$#" -ge 2 ] && [ -n "$2" ] || arret "--installation requiert un dossier."
            [ -z "$INSTALLATION" ] || arret "--installation ne peut être donné qu'une fois."
            INSTALLATION=$2
            shift 2 ;;
        --no-interaction) SANS_INTERACTION=true; shift ;;
        -h|--help)
            printf 'Usage : bash Mettre-a-jour-jgit.sh [--installation <dossier>] [--no-interaction]\nOu : jgit auto-update [--no-interaction] [--json]\n'
            exit 0 ;;
        *) arret "Argument non reconnu : $1" ;;
    esac
done

# Utiliser le dossier personnel quel que soit le dossier de lancement.
cd "$HOME" || arret "Impossible d'ouvrir votre dossier personnel : $HOME."

printf '%sjgit : mise à jour sur %s (et passage en clone git si besoin)%s\n' "$GRAS" "$BRANCHE" "$NORMAL"

# ---------------------------------------------------------------------------
etape "1. Le poste"

[ "$(uname -s)" = "Darwin" ] || arret "Ce script est prévu pour macOS (système détecté : $(uname -s))."
ok "macOS"
[ "$(id -u)" -ne 0 ] || arret "Ne lancez pas ce script avec sudo ni en tant que root."
ok "lancé sans sudo"
command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1 \
    || arret "git ne répond pas (« git --version » échoue)." \
             "Installez les outils en ligne de commande : xcode-select --install"
ok "$(git --version)"

# ---------------------------------------------------------------------------
etape "2. L'installation jgit"

ALIAS_TROUVES=""
CHEMIN_JGIT=""
if [ -n "$INSTALLATION" ]; then
    [ -f "$INSTALLATION/jgit.sh" ] || arret "jgit.sh manque dans $INSTALLATION."
    CHEMIN_JGIT=$(vrai_chemin "$INSTALLATION/jgit.sh") \
        || arret "Impossible de résoudre le chemin de l'installation : $INSTALLATION."
    ALIAS_TROUVES=" installation appelée par jgit"
else
for nom in $FICHIERS_SHELL; do
    fichier="$HOME/$nom"
    [ -f "$fichier" ] || continue
    lignes=$(grep -E '^[[:space:]]*alias[[:space:]]+jgit=' "$fichier" 2>/dev/null)
    [ -n "$lignes" ] || continue
    while IFS= read -r ligne; do
        chemin=$(chemin_alias "$ligne") \
            || arret "Alias jgit non reconnu dans ~/$nom :" "$ligne" \
                     "Attendu : alias jgit='/chemin/vers/le/dossier/jgit.sh'"
        [ -f "$chemin" ] || arret "L'alias de ~/$nom pointe vers un fichier qui n'existe pas :" "$chemin"
        reel=$(vrai_chemin "$chemin") || arret "Impossible de suivre le chemin de l'alias :" "$chemin"
        if [ -n "$CHEMIN_JGIT" ] && [ "$reel" != "$CHEMIN_JGIT" ]; then
            arret "Plusieurs alias jgit pointent vers des endroits différents :" \
                  "$CHEMIN_JGIT" "$reel" "Gardez-en un seul, puis relancez le script."
        fi
        CHEMIN_JGIT=$reel
        ALIAS_TROUVES="$ALIAS_TROUVES ~/$nom"
        ok "~/$nom : $ligne"
    done <<EOF
$lignes
EOF
done
[ -n "$CHEMIN_JGIT" ] || arret "Aucun alias jgit trouvé." \
    "Fichiers regardés dans $HOME : $FICHIERS_SHELL"
fi

DOSSIER=$(dirname "$CHEMIN_JGIT")
PARENT=$(dirname "$DOSSIER")
ok "dossier jgit : $DOSSIER"

# ---------------------------------------------------------------------------
etape "3. Le dossier"

case "$DOSSIER" in
    / | "$HOME" | /Users | /Applications | /usr | /usr/* | /bin | /sbin | /System | /System/*)
        arret "Le dossier de jgit est un dossier système ou personnel ($DOSSIER) : migration refusée." ;;
esac
[ -d "$DOSSIER" ] && [ ! -L "$DOSSIER" ] || arret "$DOSSIER n'est pas un vrai dossier."

EST_CLONE=""
if [ -e "$DOSSIER/.git" ]; then
    origine=$(git -C "$DOSSIER" config --get remote.origin.url 2>/dev/null || true)
    case "$origine" in
        git@github.com:J2S-Just-Simple-Solutions/J2S-git.git | \
        https://github.com/J2S-Just-Simple-Solutions/J2S-git.git | \
        ssh://git@github.com/J2S-Just-Simple-Solutions/J2S-git.git) EST_CLONE=1 ;;
        *) arret "$DOSSIER contient déjà un dossier .git, mais pas celui du dépôt jgit officiel." \
                 "remote origin : ${origine:-aucun}" ;;
    esac
    # -ef compare les dossiers eux-mêmes : macOS ignore la casse des noms.
    [ "$(git -C "$DOSSIER" rev-parse --show-toplevel 2>/dev/null)" -ef "$DOSSIER" ] \
        || arret "Le dépôt git de $DOSSIER n'est pas dans l'état attendu."
    ok "déjà un clone git du dépôt officiel ($origine)"
else
    ok "ce n'est pas encore un dépôt git"
fi

for f in jgit.sh README.md; do
    [ -f "$DOSSIER/$f" ] || arret "$DOSSIER ne contient pas $f : ce n'est pas un dossier jgit."
done
grep -qi 'jgit' "$DOSSIER/README.md" \
    || arret "Le README.md de $DOSSIER ne parle pas de jgit : ce n'est pas le dossier attendu."
ok "jgit.sh et README.md présents"

[ -O "$DOSSIER" ] || arret "Le dossier n'appartient pas à votre utilisateur ($(whoami))."
[ -w "$DOSSIER" ] && [ -w "$PARENT" ] || arret "Droits d'écriture insuffisants sur $DOSSIER ou sur $PARENT."
ok "dossier modifiable par $(whoami)"

# Le processus jgit appelant attend ce programme : il ne compte pas comme
# une utilisation concurrente. Tous les autres processus restent contrôlés.
if ps -A -o pid=,command= | awk -v self="$$" -v parent="$PPID" '$1 != self && $1 != parent' \
    | grep -F "$DOSSIER/" | grep -v -F "$0" | grep -v grep >/dev/null; then
    arret "jgit est en cours d'utilisation. Fermez-le (et jgit ui), puis relancez le script."
fi
ok "jgit n'est pas en cours d'utilisation"

# ---------------------------------------------------------------------------
# Déjà un clone : on met main à jour, en avance rapide seulement.
if [ -n "$EST_CLONE" ]; then
    etape "4. La mise à jour de $BRANCHE"

    branche=$(git -C "$DOSSIER" symbolic-ref --short -q HEAD) \
        || arret "Le clone n'est sur aucune branche (HEAD détachée)." \
                 "Revenez sur $BRANCHE : git -C \"$DOSSIER\" switch $BRANCHE"
    [ "$branche" = "$BRANCHE" ] \
        || arret "Le clone est sur la branche $branche, pas sur $BRANCHE." \
                 "Si vous travaillez sur jgit, terminez votre travail puis revenez sur $BRANCHE :" \
                 "git -C \"$DOSSIER\" switch $BRANCHE"
    ok "sur la branche $BRANCHE"

    modifies=$(git -C "$DOSSIER" status --porcelain --untracked-files=no) \
        || arret "Impossible de lire l'état du clone."
    [ -z "$modifies" ] || arret "Des fichiers de jgit ont été modifiés localement :" "$modifies"
    for operation in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
        chemin_operation=$(git -C "$DOSSIER" rev-parse --git-path "$operation")
        case "$chemin_operation" in /*) ;; *) chemin_operation="$DOSSIER/$chemin_operation" ;; esac
        [ ! -e "$chemin_operation" ] || arret "Une opération git est en cours ($operation). Terminez-la avant de relancer."
    done
    ok "aucune modification locale"

    case "$origine" in
        git@github.com:* | ssh://*github.com*) verifier_ssh ;;
    esac

    git -C "$DOSSIER" fetch --quiet origin "$BRANCHE" >/dev/null 2>&1 \
        || arret "Impossible de récupérer les nouveautés depuis origin ($origine)." \
                 "Vérifiez la connexion internet (et le VPN), puis relancez."
    AVANT=$(git -C "$DOSSIER" rev-parse HEAD)
    DISTANT=$(git -C "$DOSSIER" rev-parse FETCH_HEAD)
    ok "nouveautés récupérées"

    if [ "$AVANT" = "$DISTANT" ]; then
        printf '\n%sjgit est déjà à jour sur %s : version %s.%s\n' "$VERT$GRAS" "$BRANCHE" "$(decrire "$DOSSIER" HEAD)" "$NORMAL"
        exit 0
    fi
    git -C "$DOSSIER" merge-base --is-ancestor "$AVANT" "$DISTANT" \
        || arret "Votre $BRANCHE contient des commits qui ne sont pas sur le dépôt officiel :" \
                 "$(git -C "$DOSSIER" log --oneline "$DISTANT..$AVANT" | head -10)" \
                 "La mise à jour écraserait ce travail : le script préfère ne rien faire."
    ok "mise à jour possible sans rien écraser"

    etape "Tout est vérifié. Voici ce qui va être fait :"
    cat <<EOF

  Dossier jgit       : $DOSSIER
  Version actuelle   : $(decrire "$DOSSIER" "$AVANT")
  Version après      : $(decrire "$DOSSIER" "$DISTANT"), $(git -C "$DOSSIER" rev-list --count "$AVANT..$DISTANT") commit(s) de plus

  1. mettre $BRANCHE à jour sur le commit vérifié : $DISTANT
  2. vérifier que jgit répond ; sinon, revenir à la version actuelle

EOF
    confirmer "Lancer la mise à jour ?"

    etape "Mise à jour"
    [ "$(git -C "$DOSSIER" rev-parse HEAD)" = "$AVANT" ] \
        && [ "$(git -C "$DOSSIER" symbolic-ref --short -q HEAD)" = "$BRANCHE" ] \
        && clone_propre "$DOSSIER" \
        || arret "Le clone a changé pendant la confirmation. Relancez le script."
    RESTAURATION=clone
    git -C "$DOSSIER" -c core.hooksPath=/dev/null merge --quiet --ff-only --no-overwrite-ignore "$DISTANT" \
        || arret "La mise à jour a échoué."
    if ! jgit_repond "$DOSSIER" || ! clone_propre "$DOSSIER"; then
        arret "La vérification après mise à jour a échoué."
    fi
    RESTAURATION=""
    ok "jgit répond"
    printf '\n%sjgit est à jour sur %s : version %s.%s\n\n' "$VERT$GRAS" "$BRANCHE" "$(decrire "$DOSSIER" HEAD)" "$NORMAL"
    exit 0
fi

HORODATAGE=$(date +%Y%m%d-%H%M%S)
SAUVEGARDE="$DOSSIER.zip-sauvegarde-$HORODATAGE"
[ ! -e "$SAUVEGARDE" ] || arret "$SAUVEGARDE existe déjà."

# ---------------------------------------------------------------------------
etape "4. Le dépôt officiel"

verifier_ssh

git ls-remote --exit-code --heads "$DEPOT_URL" "$BRANCHE" >/dev/null 2>&1 \
    || arret "Impossible de joindre $DEPOT_URL." "Vérifiez la connexion internet (et le VPN), puis relancez."
ok "dépôt joignable"

TRAVAIL=$(mktemp -d "$PARENT/.jgit-migration.XXXXXX") \
    || arret "Impossible de créer un dossier temporaire dans $PARENT."
CLONE="$TRAVAIL/clone"
git clone --quiet --branch "$BRANCHE" "$DEPOT_URL" "$CLONE" >/dev/null 2>&1 \
    || arret "Le téléchargement du dépôt a échoué."
[ -f "$CLONE/jgit.sh" ] && clone_propre "$CLONE" \
    || arret "Le clone téléchargé n'est pas dans l'état attendu."
VERSION_NOUVELLE=$(decrire "$CLONE" HEAD)
ok "dépôt téléchargé (version $VERSION_NOUVELLE)"

# ---------------------------------------------------------------------------
etape "5. Comparaison avec les versions officielles"

# Empreinte du dossier actuel : « chemin<TAB>contenu » pour chaque fichier,
# sans rien écrire nulle part (hash-object sans -w). Les fichiers qu'ajoute
# macOS ou que produit jgit lui-même ne comptent pas.
cat > "$TRAVAIL/exclusions" <<'EOF'
.DS_Store
._*
.AppleDouble
.jgit/
node_modules/
ui/dist/
__pycache__/
*.py[cod]
tests/**/tmp/
.idea/
*.swp
*~
EOF
(
    cd "$DOSSIER" || exit 1
    export GIT_DIR="$CLONE/.git" GIT_WORK_TREE="$DOSSIER" GIT_INDEX_FILE="$TRAVAIL/index-vide"
    git_sur ls-files --others --exclude-from="$TRAVAIL/exclusions" > "$TRAVAIL/fichiers" || exit 1
    while IFS= read -r fichier; do
        # Git cite les noms spéciaux ; ne pas les interpréter comme des chemins.
        case "$fichier" in \"*) exit 1 ;; esac
        [ ! -L "$fichier" ] || exit 1
    done < "$TRAVAIL/fichiers"
    git_sur hash-object --no-filters --stdin-paths < "$TRAVAIL/fichiers" > "$TRAVAIL/contenus" || exit 1
) || arret "Impossible de lire le contenu de $DOSSIER (fichier illisible, nom spécial ou lien symbolique ?)."
[ "$(wc -l < "$TRAVAIL/fichiers")" -eq "$(wc -l < "$TRAVAIL/contenus")" ] \
    || arret "Lecture incomplète du contenu de $DOSSIER."
paste "$TRAVAIL/fichiers" "$TRAVAIL/contenus" | LC_ALL=C sort > "$TRAVAIL/local"
ok "$(wc -l < "$TRAVAIL/local" | tr -d ' ') fichiers lus"

# Même empreinte pour chaque version de l'historique officiel ; on cherche
# celle qui correspond exactement (les droits d'exécution sont ignorés : un zip
# peut les avoir perdus).
empreinte() {
    git_sur -C "$CLONE" ls-tree -r --full-tree "$1" | awk -F'\t' '{ split($1, a, " "); print $2 "\t" a[3] }' | LC_ALL=C sort
}
COMMIT_ZIP=""
MEILLEUR=""; MEILLEUR_ECARTS=999999
for c in $(git -C "$CLONE" rev-list "origin/$BRANCHE"); do
    empreinte "$c" > "$TRAVAIL/officiel"
    if cmp -s "$TRAVAIL/officiel" "$TRAVAIL/local"; then
        # Plusieurs commits peuvent avoir le même contenu : on préfère celui
        # qui porte un numéro de version.
        [ -z "$COMMIT_ZIP" ] && COMMIT_ZIP=$c
        if [ -n "$(git -C "$CLONE" tag --points-at "$c")" ]; then COMMIT_ZIP=$c; break; fi
        continue
    fi
    ecarts=$(LC_ALL=C comm -3 "$TRAVAIL/officiel" "$TRAVAIL/local" | wc -l | tr -d ' ')
    if [ "$ecarts" -lt "$MEILLEUR_ECARTS" ]; then MEILLEUR=$c; MEILLEUR_ECARTS=$ecarts; fi
done

if [ -z "$COMMIT_ZIP" ]; then
    empreinte "$MEILLEUR" > "$TRAVAIL/officiel"
    LC_ALL=C comm -3 "$TRAVAIL/officiel" "$TRAVAIL/local" \
        | awk -F'\t' '
            NF == 3 { local[$2] = 1; next }   # colonne 2 de comm : présent ici seulement
                    { off[$1] = 1 }           # colonne 1 : présent dans la version officielle
            END {
                for (p in local) print (p in off ? "  modifié  : " : "  ajouté   : ") p
                for (p in off) if (!(p in local)) print "  manquant : " p
            }' \
        | LC_ALL=C sort -k3 | head -30 > "$TRAVAIL/ecarts"
    arret "Le dossier ne correspond exactement à aucune version officielle de jgit." \
          "Version la plus proche : $(decrire "$CLONE" "$MEILLEUR"), avec ces différences :" \
          "$(cat "$TRAVAIL/ecarts")" \
          "" \
          "Ces fichiers ont peut-être été modifiés à la main : le script préfère ne rien faire."
fi
VERSION_ACTUELLE=$(decrire "$CLONE" "$COMMIT_ZIP")
ok "le dossier correspond exactement à la version officielle $VERSION_ACTUELLE"

# ---------------------------------------------------------------------------
etape "Tout est vérifié. Voici ce qui va être fait :"

cat <<EOF

  Dossier jgit       : $DOSSIER
  Alias              :$ALIAS_TROUVES (inchangé)
  Version actuelle   : $VERSION_ACTUELLE
  Version après      : $VERSION_NOUVELLE

  1. renommer  $DOSSIER
     en        $SAUVEGARDE
     (sauvegarde complète, vous pourrez la supprimer quand vous voulez)
  2. installer le clone git du dépôt officiel à sa place, au même chemin
  3. vérifier que jgit répond ; sinon, remettre l'ancien dossier en place

EOF

confirmer "Lancer la migration ?"

# ---------------------------------------------------------------------------
etape "Migration"

RESTAURATION=zip
mv "$DOSSIER" "$SAUVEGARDE" || arret "Le renommage de $DOSSIER a échoué."
ok "ancien dossier sauvegardé : $SAUVEGARDE"

mv "$CLONE" "$DOSSIER" || arret "L'installation du clone a échoué."
ok "clone git installé : $DOSSIER"

if ! jgit_repond "$DOSSIER" \
   || ! clone_propre "$DOSSIER" \
   || [ "$(git -C "$DOSSIER" rev-parse --abbrev-ref HEAD)" != "$BRANCHE" ]; then
    arret "La vérification après installation a échoué."
fi
RESTAURATION=""
ok "jgit répond"

cat <<EOF

${VERT}${GRAS}Migration terminée.${NORMAL}

  jgit est maintenant un clone git à jour sur $BRANCHE, au même endroit :
  l'alias jgit n'a pas changé.
  Pour mettre jgit à jour, à l'avenir :

      jgit auto-update

  Ou manuellement :

      git -C "$DOSSIER" pull --ff-only

  L'ancienne installation est conservée ici, supprimez-la quand vous voulez :

      $SAUVEGARDE

EOF
