#!/bin/bash

# Dossier d'installation de jgit, liens symboliques résolus : jgit peut être
# appelé par un alias, par son chemin, ou par un lien posé dans le PATH
# (/usr/local/bin/jgit dans l'image Docker). Sans résolution, un lien ferait
# chercher les modules à côté du lien. readlink sans -f : absent des vieux macOS.
jgit_resolve_home() {
    local source="${BASH_SOURCE[0]}"
    local dir

    while [[ -L "$source" ]]; do
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ "$source" == /* ]] || source="$dir/$source"
    done

    cd -P "$(dirname "$source")" && pwd
}

JGIT_HOME=$(jgit_resolve_home)

source "$JGIT_HOME/feature.sh"
source "$JGIT_HOME/release.sh"
source "$JGIT_HOME/rebase.sh"
source "$JGIT_HOME/demo.sh"

####################################
#
#         LOCAL PARAMETERS
# Update this section to fit your local
#
####################################

j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
# Nombre de commits de travail au delà duquel un rebase propose spontanément le squash.
squash_threshold=8

FILE=.jgit/conf_local.sh
if test -f "$FILE"; then
    # shellcheck disable=SC1090
    source "$FILE"
fi

####################################
#
#        MANDATORY PARAMETERS
# This section should be the same
#         for all developers
#
####################################
prefix_PR="__PR__"
prefix_commit="[jgit]"
prefix_init_commit="$prefix_commit INIT"
suffix_init_commit="[empty_commit]"
# Clés des trailers qui portent la branche d'origine dans le corps des commits
# d'init. Les changer rendrait illisibles toutes les branches déjà créées.
trailer_branch="jgit-branch"
trailer_based_on="jgit-based-on"

JGIT_NO_INTERACTION=false
JGIT_SQUASH=false
JGIT_SQUASH_THRESHOLD=$squash_threshold
JGIT_NO_OPEN=false
JGIT_BASED_ON_OVERRIDE=""
JGIT_INTO_TARGET=""
declare -a JGIT_FROM_SOURCES=()

stash=false
current_branch=$(git rev-parse --abbrev-ref HEAD)

################################################################################
# Help                                                                         #
################################################################################
help() {
    printf "\n${C_BLUE}Usage:${C_RESET}\n"
    printf "  jgit ${C_GREEN}<scope>${C_RESET} ${C_CYAN}<action>${C_RESET} ${C_ORANGE}[<target>]${C_RESET} ${C_ORANGE}[options…]${C_RESET}\n\n"

    printf "${C_BLUE}Scopes:${C_RESET} feature | hotfix | release | demo | util\n\n"

    printf "${C_BLUE}Options communes:${C_RESET}\n"
    printf "  --based-on <branch>   Branche de référence pour les créations / rebase.\n"
    printf "  --from <branch>       Source d'un merge (répétable).\n"
    printf "  --into <branch>       Destination explicite d'un merge.\n"
    printf "  --no-interaction      Ne pose aucune question et applique les réponses par défaut.\n"
    printf "  --no-open             N'ouvre pas automatiquement la PR.\n"
    printf "  --squash              Squash les commits de la branche en un seul avant le rebase.\n"
    printf "  -h | --help           Affiche cette aide.\n\n"

    printf "${C_BLUE}Feature & Hotfix:${C_RESET}\n"
    printf "  jgit feature start <ticket> [--based-on <branch>] [--no-open]\n"
    printf "  jgit feature restart <ticket> [--no-open]\n"
    printf "  jgit feature rebase <ticket> [--based-on <branch>] [--squash]\n"
    printf "  (idem avec hotfix)\n\n"

    printf "${C_BLUE}Release:${C_RESET}\n"
    printf "  jgit release start [<x.y.z>]\n"
    printf "  jgit release merge [<x.y.z>] --from <branch> [--into <branch>]\n"
    printf "  jgit release finish [--into <x.y.z>]\n\n"

    printf "${C_BLUE}Demo:${C_RESET}\n"
    printf "  jgit demo start [<demo_name>] [--based-on <branch>]\n"
    printf "  jgit demo merge [--from feature/<ticket>]... [--into <branch>]\n"
    printf "  jgit demo list\n"
    printf "  jgit demo remove [--no-interaction]\n\n"

    printf "${C_BLUE}Utility:${C_RESET}\n"
    printf "  jgit util clean                Supprime les branches locales jgit_rebase_*, jgit_verify_rebase_* et __PR__*.\n"
    printf "  jgit util check_rebase [--from <branche>]\n"
    printf "                                 Dit si la branche est à jour sur sa branche d'origine et si le rebase passerait.\n"
    printf "  jgit util verify_rebase --from <branche_source> --into <branche_cible>\n\n"

    printf "${C_BLUE}Syntaxes dépréciées${C_RESET} (encore acceptées, retirées à terme) :\n"
    printf "  jgit release merge <branche>   → jgit release merge --from <branche>\n"
    printf "  jgit clean                     → jgit util clean\n\n"
}

require_argument() {
    local option="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == -* ]]; then
        printf "${C_RED}Erreur : l'option %s requiert une valeur.${C_RESET}\n" "$option" >&2
        exit_safe 1
    fi
}

ensure_remote() {
    local remotes
    remotes=$(git remote -v)

    if [[ $remotes != *"$j2s_remote"* ]]; then
        echo "Please configure J2S remote as $j2s_remote"
        exit_safe 1
    fi
}

####################################
#
#      Manage parameters
#
####################################

if [[ $# -eq 0 ]]; then
    help
    exit_safe 0
fi

if [[ $1 == "-h" || $1 == "--help" ]]; then
    help
    exit_safe 0
fi

positional=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --based-on)
            require_argument "--based-on" "$2"
            JGIT_BASED_ON_OVERRIDE="$2"
            shift 2
            ;;
        --from)
            require_argument "--from" "$2"
            JGIT_FROM_SOURCES+=("$2")
            shift 2
            ;;
        --into)
            require_argument "--into" "$2"
            JGIT_INTO_TARGET="$2"
            shift 2
            ;;
        --no-interaction)
            JGIT_NO_INTERACTION=true
            shift
            ;;
        --no-open)
            JGIT_NO_OPEN=true
            shift
            ;;
        --squash)
            JGIT_SQUASH=true
            shift
            ;;
        --help)
            help
            exit_safe 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                positional+=("$1")
                shift
            done
            ;;
        -* )
            printf "${C_RED}Option inconnue : %s${C_RESET}\n" "$1" >&2
            exit_safe 1
            ;;
        *)
            positional+=("$1")
            shift
            ;;
    esac
done

JGIT_TYPE="${positional[0]}"
JGIT_ACTION="${positional[1]}"
JGIT_TARGET="${positional[2]}"
extra_positionals=()
if [[ ${#positional[@]} -gt 3 ]]; then
    extra_positionals=("${positional[@]:3}")
fi

if [[ -z "$JGIT_TYPE" ]]; then
    help
    exit_safe 0
fi

if [[ "$JGIT_TYPE" == "help" ]]; then
    help
    exit_safe 0
fi

if [[ "$JGIT_TYPE" == "-h" ]]; then
    help
    exit_safe 0
fi

if [[ ${#extra_positionals[@]} -gt 0 ]]; then
    printf "${C_RED}Arguments supplémentaires non reconnus : %s${C_RESET}\n" "${extra_positionals[*]}" >&2
    exit_safe 1
fi

####################################
#
#         RUNNING script
#
####################################

ensure_supported_platform || exit_safe 1
ensure_remote
ensure_full_history || exit_safe 1

# Seules les commandes qui ne commitent jamais se passent d'identité git.
case "$JGIT_TYPE $JGIT_ACTION" in
    "util clean"|"clean "*) ;;
    *) ensure_git_identity || exit_safe 1 ;;
esac

case "$JGIT_TYPE" in
    feature|hotfix)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            start)
                if [[ -z "$JGIT_TARGET" ]]; then
                    echo "Please set a $JGIT_TYPE identifier." >&2
                    exit_safe 1
                fi
                verify_stash
                feature_start "$JGIT_TYPE" "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            restart)
                if [[ -z "$JGIT_TARGET" ]]; then
                    echo "Please set a $JGIT_TYPE identifier." >&2
                    exit_safe 1
                fi
                verify_stash
                feature_restart "$JGIT_TYPE" "$JGIT_TARGET"
                ;;
            rebase)
                if [[ -z "$JGIT_TARGET" ]]; then
                    echo "Please set a $JGIT_TYPE identifier." >&2
                    exit_safe 1
                fi
                verify_stash
                feature_rebase "$JGIT_TYPE" "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            *)
                printf "${C_RED}Action '%s' non supportée pour %s.${C_RESET}\n" "$JGIT_ACTION" "$JGIT_TYPE" >&2
                exit_safe 1
                ;;
        esac
        ;;
    release)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            start)
                refuse_if_worktree_dirty "Une release" || exit_safe 1
                release_start "$JGIT_TARGET"
                ;;
            merge)
                # Rétrocompatibilité : « jgit release merge <branche> » désignait la
                # source à intégrer. La cible positionnelle est aujourd'hui une version
                # (x.y.z), ce qui permet de distinguer les deux sans ambiguïté.
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 && -n "$JGIT_TARGET" ]] \
                   && ! is_release_version "$JGIT_TARGET"; then
                    warn_deprecated_syntax \
                        "jgit release merge $JGIT_TARGET" \
                        "jgit release merge --from $JGIT_TARGET"
                    JGIT_FROM_SOURCES+=("$JGIT_TARGET")
                    JGIT_TARGET=""
                fi
                if [[ -n "$JGIT_TARGET" ]] && ! is_release_version "$JGIT_TARGET"; then
                    printf "${C_RED}Version de release attendue au format x.y.z, reçu '%s'.${C_RESET}\n" "$JGIT_TARGET" >&2
                    printf "Pour désigner une branche source, utilisez --from %s.\n" "$JGIT_TARGET" >&2
                    exit_safe 1
                fi
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    echo "Veuillez spécifier au moins une source avec --from." >&2
                    exit_safe 1
                fi
                refuse_if_worktree_dirty "Une release" || exit_safe 1
                release_merge "$JGIT_TARGET" "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            finish)
                refuse_if_worktree_dirty "Une release" || exit_safe 1
                release_finish "$JGIT_INTO_TARGET"
                ;;
            *)
                printf "${C_RED}Action '%s' non supportée pour release.${C_RESET}\n" "$JGIT_ACTION" >&2
                exit_safe 1
                ;;
        esac
        ;;
    demo)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            start)
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_start "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            merge)
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    echo "Veuillez préciser au moins une source avec --from." >&2
                    exit_safe 1
                fi
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_merge "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            list)
                demo_list
                ;;
            remove)
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_remove
                ;;
            *)
                printf "${C_RED}Action '%s' non supportée pour demo.${C_RESET}\n" "$JGIT_ACTION" >&2
                exit_safe 1
                ;;
        esac
        ;;
    util)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            clean)
                clean_branches
                ;;
            check_rebase)
                # Le positionnel serait ignoré en silence : on préfère le dire.
                if [[ -n "$JGIT_TARGET" ]]; then
                    printf "${C_RED}Pour désigner une branche, utilisez --from %s.${C_RESET}\n" "$JGIT_TARGET" >&2
                    exit_safe 1
                fi
                util_check_rebase ${JGIT_FROM_SOURCES[@]+"${JGIT_FROM_SOURCES[@]}"}
                exit $?
                ;;
            verify_rebase)
                util_verify_rebase "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                exit $?
                ;;
            *)
                printf "${C_RED}Action '%s' non supportée pour util.${C_RESET}\n" "$JGIT_ACTION" >&2
                exit_safe 1
                ;;
        esac
        ;;
    clean)
        # Rétrocompatibilité : « jgit clean » est devenu « jgit util clean ».
        warn_deprecated_syntax "jgit clean" "jgit util clean"
        clean_branches
        ;;
    *)
        printf "${C_RED}Scope '%s' non supporté.${C_RESET}\n" "$JGIT_TYPE" >&2
        exit_safe 1
        ;;
 esac

exit_safe 0
