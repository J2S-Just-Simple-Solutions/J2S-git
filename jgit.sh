#!/bin/bash

source "$(dirname "$0")/feature.sh"
source "$(dirname "$0")/release.sh"
source "$(dirname "$0")/rebase.sh"
source "$(dirname "$0")/demo.sh"

####################################
#
#         LOCAL PARAMETERS
# Update this section to fit your local
#
####################################

j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"

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

JGIT_AUTO_YES=false
JGIT_DRY_RUN=false
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
    printf "\n\033[1;34mUsage:\033[0m\n"
    printf "  jgit \033[1;32m<scope>\033[0m \033[1;36m<action>\033[0m \033[38;5;214m[<target>]\033[0m \033[38;5;214m[options…]\033[0m\n\n"

    printf "\033[1;34mScopes:\033[0m feature | hotfix | release | demo | util\n\n"

    printf "\033[1;34mOptions communes:\033[0m\n"
    printf "  --based-on <branch>   Branche de référence pour les créations / rebase.\n"
    printf "  --from <branch>       Source d'un merge (répétable).\n"
    printf "  --into <branch>       Destination explicite d'un merge.\n"
    printf "  --yes                 Valide automatiquement les confirmations.\n"
    printf "  --dry-run             Affiche les actions sans les exécuter.\n"
    printf "  --no-open             N'ouvre pas automatiquement la PR.\n"
    printf "  -h | --help           Affiche cette aide.\n\n"

    printf "\033[1;34mFeature & Hotfix:\033[0m\n"
    printf "  jgit feature start <ticket> [--based-on <branch>] [--no-open]\n"
    printf "  jgit feature restart <ticket>\n"
    printf "  jgit feature rebase <ticket> [--based-on <branch>]\n"
    printf "  (idem avec hotfix)\n\n"

    printf "\033[1;34mRelease:\033[0m\n"
    printf "  jgit release start [<x.y.z>]\n"
    printf "  jgit release merge [<x.y.z>] --from <branch> [--into <branch>]\n"
    printf "  jgit release finish\n\n"

    printf "\033[1;34mDemo:\033[0m\n"
    printf "  jgit demo start [<demo_name>] [--based-on <branch>]\n"
    printf "  jgit demo merge [--from feature/<ticket>]... [--into <branch>]\n"
    printf "  jgit demo list\n"
    printf "  jgit demo remove [--yes]\n\n"

    printf "\033[1;34mUtility:\033[0m\n"
    printf "  jgit util clean\n\n"
}

require_argument() {
    local option="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == -* ]]; then
        printf "\033[1;31mErreur : l'option %s requiert une valeur.\033[0m\n" "$option" >&2
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
        --yes|-y)
            JGIT_AUTO_YES=true
            shift
            ;;
        --dry-run)
            JGIT_DRY_RUN=true
            shift
            ;;
        --no-open)
            JGIT_NO_OPEN=true
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
            printf "\033[1;31mOption inconnue : %s\033[0m\n" "$1" >&2
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
    printf "\033[1;31mArguments supplémentaires non reconnus : %s\033[0m\n" "${extra_positionals[*]}" >&2
    exit_safe 1
fi

####################################
#
#         RUNNING script
#
####################################

ensure_remote

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
                printf "\033[1;31mAction '%s' non supportée pour %s.\033[0m\n" "$JGIT_ACTION" "$JGIT_TYPE" >&2
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
                verify_stash
                release_start "$JGIT_TARGET"
                ;;
            merge)
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    echo "Veuillez spécifier au moins une source avec --from." >&2
                    exit_safe 1
                fi
                verify_stash
                release_merge "$JGIT_TARGET" "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            finish)
                verify_stash
                release_finish "$JGIT_INTO_TARGET"
                ;;
            *)
                printf "\033[1;31mAction '%s' non supportée pour release.\033[0m\n" "$JGIT_ACTION" >&2
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
                verify_stash
                demo_start "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            merge)
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    echo "Veuillez préciser au moins une source avec --from." >&2
                    exit_safe 1
                fi
                verify_stash
                demo_merge "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            list)
                demo_list
                ;;
            remove)
                verify_stash
                demo_remove
                ;;
            *)
                printf "\033[1;31mAction '%s' non supportée pour demo.\033[0m\n" "$JGIT_ACTION" >&2
                exit_safe 1
                ;;
        esac
        ;;
    util)
        if [[ "$JGIT_ACTION" == "clean" ]]; then
            clean_branches
        else
            printf "\033[1;31mAction '%s' non supportée pour util.\033[0m\n" "$JGIT_ACTION" >&2
            exit_safe 1
        fi
        ;;
    *)
        printf "\033[1;31mScope '%s' non supporté.\033[0m\n" "$JGIT_TYPE" >&2
        exit_safe 1
        ;;
 esac

exit_safe 0
