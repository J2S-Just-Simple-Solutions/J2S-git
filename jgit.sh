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

# --json est repéré avant tout le reste : dès la première ligne écrite, la
# sortie standard doit être réservée au document, y compris pour une erreur de
# syntaxe dans la suite de la ligne de commande. Après « -- », plus d'option.
JGIT_JSON_REQUESTED=false
for jgit_arg in "$@"; do
    [[ "$jgit_arg" == "--" ]] && break
    [[ "$jgit_arg" == "--json" ]] && JGIT_JSON_REQUESTED=true
done
unset jgit_arg

source "$JGIT_HOME/feature.sh"
source "$JGIT_HOME/release.sh"
source "$JGIT_HOME/rebase.sh"
source "$JGIT_HOME/demo.sh"
source "$JGIT_HOME/ui.sh"

if [[ $JGIT_JSON_REQUESTED == true ]]; then
    jgit_json_enable
    jgit_disable_colors
fi

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
JGIT_NO_FETCH=false
JGIT_ON_CONFLICT=""
JGIT_DEMO_SCOPE="active"
JGIT_DRY_RUN=false
JGIT_KEEP_DELIVERED=false
JGIT_KEEP_MISSING=false
JGIT_DROP_FOREIGN=false
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

    printf "${C_BLUE}Scopes:${C_RESET} feature | hotfix | release | demo | audit | util | ui\n\n"

    printf "${C_BLUE}Options communes:${C_RESET}\n"
    printf "  --based-on <branch>   Branche de référence pour les créations / rebase.\n"
    printf "  --from <branch>       Source d'un merge (répétable).\n"
    printf "  --into <branch>       Destination explicite d'un merge.\n"
    printf "  --no-interaction      Ne pose aucune question et applique les réponses par défaut.\n"
    printf "  --json                Sortie machine : un seul document JSON sur la sortie standard,\n"
    printf "                        les messages sur la sortie d'erreur. Implique --no-interaction.\n"
    printf "  --no-fetch            Ne contacte pas le serveur : travaille sur les références déjà rapatriées.\n"
    printf "  --no-open             N'ouvre pas automatiquement la PR.\n"
    printf "  --squash              Squash les commits de la branche en un seul avant le rebase.\n"
    printf "  --on-conflict <mode>  Conduite face à un conflit de rebase : ask (défaut en interactif),\n"
    printf "                        abort (défaut sans interaction) ou pause (reprise par continue).\n"
    printf "  -h | --help           Affiche cette aide.\n\n"

    printf "${C_BLUE}Feature & Hotfix:${C_RESET}\n"
    printf "  jgit feature start <ticket> [--based-on <branch>] [--no-open]\n"
    printf "  jgit feature restart <ticket> [--no-open]\n"
    printf "  jgit feature rebase <ticket> [--based-on <branch>] [--squash] [--on-conflict <mode>]\n"
    printf "  jgit feature continue <ticket>   Reprend un rebase mis en pause sur un conflit.\n"
    printf "  jgit feature abort <ticket>      Annule un rebase mis en pause : rien n'a été poussé.\n"
    printf "  (idem avec hotfix)\n\n"

    printf "${C_BLUE}Release:${C_RESET}\n"
    printf "  jgit release start [<x.y.z>]\n"
    printf "  jgit release merge [<x.y.z>] --from <branch> [--into <branch>]\n"
    printf "  jgit release finish [--into <x.y.z>]\n\n"

    printf "${C_BLUE}Demo:${C_RESET}\n"
    printf "  jgit demo list [--archived | --all]   Les démos du projet et leur état.\n"
    printf "  jgit demo show [<nom>]                Le contenu d'une démo, ticket par ticket.\n"
    printf "  jgit demo candidates [<nom>] [--based-on <branch>]\n"
    printf "                                        Les tickets que l'on peut ajouter à une démo (ou à une démo sur cette base).\n"
    printf "  jgit demo bases                       Les branches dont une démo peut partir.\n"
    printf "  jgit demo create <nom> [--based-on <branch>] [--from <ticket>]...\n"
    printf "  jgit demo add [<nom>] --from <ticket>...      Ajoute des tickets, ou leurs nouveaux commits.\n"
    printf "  jgit demo drop [<nom>] --from <ticket>...     Reconstruit la démo sans ces tickets.\n"
    printf "  jgit demo refresh [<nom>] --from <ticket>...  Reprend ces tickets en entier depuis leur branche.\n"
    printf "  jgit demo rebase [<nom>] [--based-on <branch>] [--from <ticket>]... [--keep-delivered] [--keep-missing]\n"
    printf "                                        Reconstruit la démo sur la version actuelle de sa base ;\n"
    printf "                                        --from reprend ce ticket depuis sa branche (une fois rebasé chez lui).\n"
    printf "  jgit demo continue [<nom>] | abort [<nom>]   Reprend ou annule une opération en pause.\n"
    printf "  jgit demo archive <nom>               Archive la démo (demo-archive/<date>_<nom>) et libère son nom.\n"
    printf "  jgit demo unarchive <archive>         Restaure une démo archivée sous son nom.\n"
    printf "  jgit demo delete <nom|archive>        Supprime une démo du serveur.\n"
    printf "  jgit demo migrate <nom> [--based-on <branch>]\n"
    printf "                                        Recrée une démo demo_<nom> (ancien format) au format actuel.\n"
    printf "  Options des commandes qui modifient : --dry-run, --drop-foreign, --on-conflict <mode>\n\n"

    printf "${C_BLUE}Audit:${C_RESET} (simulation : rien n'est modifié)\n"
    printf "  jgit audit                     État des lieux de tous les tickets du serveur et de toutes les démos.\n"
    printf "  jgit audit tickets             Chaque ticket est-il à jour sur sa base ? Son rebase passerait-il ?\n"
    printf "  jgit audit demos [<nom>]       Les démos : tickets à rebaser d'abord, puis remise à jour de la démo.\n"
    printf "                                 Pour chaque action : qui doit intervenir, et la commande à lancer.\n\n"

    printf "${C_BLUE}Interface:${C_RESET}\n"
    printf "  jgit ui                        Les démos dans une interface en terminal (Docker ; JGIT_UI=native sans Docker).\n\n"

    printf "${C_BLUE}Utility:${C_RESET}\n"
    printf "  jgit util clean                Supprime les branches locales jgit_rebase_*, jgit_demo_*, jgit_verify_rebase_* et __PR__*.\n"
    printf "  jgit util status               Dit si une opération attend la résolution d'un conflit, et où elle en est.\n"
    printf "  jgit util check_rebase [--from <branche>]\n"
    printf "                                 Dit si la branche est à jour sur sa branche d'origine et si le rebase passerait.\n"
    printf "  jgit util verify_rebase --from <branche_source> --into <branche_cible>\n\n"

    printf "${C_BLUE}Syntaxes dépréciées${C_RESET} (encore acceptées, retirées à terme) :\n"
    printf "  jgit release merge <branche>   → jgit release merge --from <branche>\n"
    printf "  jgit clean                     → jgit util clean\n"
    printf "  jgit demo start [<nom>]        → jgit demo create <nom>\n"
    printf "  jgit demo merge --from <ticket> [--into <nom>] → jgit demo add <nom> --from <ticket>\n"
    printf "  jgit demo remove               → jgit demo delete <nom>\n"
    printf "  jgit demo list (depuis une démo) → jgit demo show <nom>\n\n"
}

require_argument() {
    local option="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == -* ]]; then
        jgit_fail usage "$JGIT_EXIT_ERROR" "Erreur : l'option $option requiert une valeur."
    fi
}

ensure_remote() {
    local remotes
    remotes=$(git remote -v)

    if [[ $remotes != *"$j2s_remote"* ]]; then
        jgit_fail remote_missing "$JGIT_EXIT_ERROR" "Please configure J2S remote as $j2s_remote"
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
        --json)
            # Déjà traité avant le chargement des modules.
            JGIT_NO_INTERACTION=true
            shift
            ;;
        --no-fetch)
            JGIT_NO_FETCH=true
            shift
            ;;
        --archived)
            JGIT_DEMO_SCOPE="archived"
            shift
            ;;
        --dry-run)
            JGIT_DRY_RUN=true
            shift
            ;;
        --keep-delivered)
            JGIT_KEEP_DELIVERED=true
            shift
            ;;
        --keep-missing)
            JGIT_KEEP_MISSING=true
            shift
            ;;
        --drop-foreign)
            JGIT_DROP_FOREIGN=true
            shift
            ;;
        --all)
            JGIT_DEMO_SCOPE="all"
            shift
            ;;
        --on-conflict|--on-conflict=*)
            if [[ "$1" == --on-conflict=* ]]; then
                JGIT_ON_CONFLICT="${1#--on-conflict=}"
                shift
            else
                require_argument "--on-conflict" "$2"
                JGIT_ON_CONFLICT="$2"
                shift 2
            fi
            case "$JGIT_ON_CONFLICT" in
                ask|abort|pause) ;;
                *) jgit_fail usage "$JGIT_EXIT_ERROR" \
                       "Valeur inconnue pour --on-conflict : '$JGIT_ON_CONFLICT'." \
                       "Valeurs acceptées : ask, abort, pause." ;;
            esac
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
            jgit_fail usage "$JGIT_EXIT_ERROR" "Option inconnue : $1"
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
    jgit_fail usage "$JGIT_EXIT_ERROR" "Arguments supplémentaires non reconnus : ${extra_positionals[*]}"
fi

JGIT_COMMAND="$JGIT_TYPE${JGIT_ACTION:+ $JGIT_ACTION}"

# Sans interaction, git ne doit rien demander non plus : ni identifiants, ni
# message de commit dans un éditeur.
if [[ $JGIT_NO_INTERACTION == true ]]; then
    export GIT_TERMINAL_PROMPT=0
    export GIT_EDITOR=true
    export GIT_MERGE_AUTOEDIT=no
fi

# Les références déjà rapatriées font foi : utile pour un affichage répété
# (interface, tableau de bord) qui n'a pas besoin d'interroger le serveur.
if [[ $JGIT_NO_FETCH == true ]]; then
    JGIT_FETCH_DONE=true
fi

####################################
#
#         RUNNING script
#
####################################

ensure_supported_platform || exit_safe 1
ensure_remote
ensure_full_history || exit_safe 1

# Commandes qui ne font que lire : elles ne commitent rien, ne touchent ni à
# l'espace de travail ni à la branche courante.
jgit_command_is_read_only() {
    case "$JGIT_TYPE $JGIT_ACTION" in
        "ui ") return 0 ;;
        "demo list"|"demo show"|"demo candidates"|"demo bases"|"util status") return 0 ;;
        "audit "*) return 0 ;;
    esac
    return 1
}

# Seules les commandes qui ne commitent jamais se passent d'identité git.
case "$JGIT_TYPE $JGIT_ACTION" in
    "util clean"|"clean "*) ;;
    *) jgit_command_is_read_only || ensure_git_identity || exit_safe 1 ;;
esac

# Une opération en pause sur un conflit occupe l'espace de travail : seules la
# reprise, l'annulation et les commandes de lecture peuvent tourner tant
# qu'elle n'est pas terminée.
case "$JGIT_ACTION" in
    continue|abort) ;;
    *) jgit_command_is_read_only || refuse_if_operation_paused ;;
esac

case "$JGIT_TYPE" in
    feature|hotfix)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            jgit_error_set usage "Action manquante pour le scope $JGIT_TYPE." "jgit --help"
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            start)
                if [[ -z "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Please set a $JGIT_TYPE identifier."
                fi
                verify_stash
                feature_start "$JGIT_TYPE" "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            restart)
                if [[ -z "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Please set a $JGIT_TYPE identifier."
                fi
                verify_stash
                feature_restart "$JGIT_TYPE" "$JGIT_TARGET"
                ;;
            rebase)
                if [[ -z "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Please set a $JGIT_TYPE identifier."
                fi
                verify_stash
                feature_rebase "$JGIT_TYPE" "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            continue|abort)
                if [[ -z "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Please set a $JGIT_TYPE identifier."
                fi
                # Pas de verify_stash : l'espace de travail est celui du conflit.
                if [[ "$JGIT_ACTION" == "continue" ]]; then
                    feature_rebase_continue "$JGIT_TYPE" "$JGIT_TARGET"
                else
                    feature_rebase_abort "$JGIT_TYPE" "$JGIT_TARGET"
                fi
                ;;
            *)
                jgit_fail usage "$JGIT_EXIT_ERROR" "Action '$JGIT_ACTION' non supportée pour $JGIT_TYPE."
                ;;
        esac
        ;;
    release)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            jgit_error_set usage "Action manquante pour le scope $JGIT_TYPE." "jgit --help"
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
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Version de release attendue au format x.y.z, reçu '$JGIT_TARGET'." \
                        "Pour désigner une branche source, utilisez --from $JGIT_TARGET."
                fi
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Veuillez spécifier au moins une source avec --from."
                fi
                refuse_if_worktree_dirty "Une release" || exit_safe 1
                release_merge "$JGIT_TARGET" "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            finish)
                refuse_if_worktree_dirty "Une release" || exit_safe 1
                release_finish "$JGIT_INTO_TARGET"
                ;;
            *)
                jgit_fail usage "$JGIT_EXIT_ERROR" "Action '$JGIT_ACTION' non supportée pour release."
                ;;
        esac
        ;;
    demo)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            jgit_error_set usage "Action manquante pour le scope $JGIT_TYPE." "jgit --help"
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            start)
                # Rétrocompatibilité : « demo start » est devenu « demo create ».
                # Sans nom, la démo prenait celui de sa base : c'est conservé.
                jgit_demo_name="$JGIT_TARGET"
                if [[ -z "$jgit_demo_name" ]]; then
                    jgit_demo_name="$JGIT_BASED_ON_OVERRIDE"
                    [[ -n "$jgit_demo_name" ]] || jgit_demo_name=$(get_reference_branch feature) || exit_safe 1
                fi
                warn_deprecated_syntax "jgit demo start${JGIT_TARGET:+ $JGIT_TARGET}" "jgit demo create $jgit_demo_name"
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_create_cmd "$jgit_demo_name" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            merge)
                # Rétrocompatibilité : « demo merge [--into <démo>] » est devenu
                # « demo add <démo> ». Sans --into, la démo de la branche courante.
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Veuillez préciser au moins une source avec --from."
                fi
                jgit_demo_name="${JGIT_INTO_TARGET#demo_}"
                jgit_demo_name="${jgit_demo_name#demo/}"
                warn_deprecated_syntax "jgit demo merge --from …${JGIT_INTO_TARGET:+ --into $JGIT_INTO_TARGET}" \
                    "jgit demo add ${jgit_demo_name:-<nom>} --from …"
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_add_cmd "$jgit_demo_name" "${JGIT_FROM_SOURCES[@]}"
                ;;
            remove)
                # Rétrocompatibilité : « demo remove » supprimait la démo de la
                # branche courante. C'est « demo delete <nom> ».
                warn_deprecated_syntax "jgit demo remove" "jgit demo delete <nom>"
                if ! demo_parse_branch "$current_branch" 2>/dev/null; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" \
                        "Cette commande doit être exécutée depuis une branche de démo (branche actuelle : $current_branch)." \
                        "Nommez la démo : jgit demo delete <nom>"
                fi
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_delete_cmd "$current_branch"
                ;;
            list)
                if [[ -n "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" \
                        "demo list n'attend pas de nom de démo." \
                        "Le contenu d'une démo : jgit demo show $JGIT_TARGET"
                fi
                # Rétrocompatibilité : lancée depuis une démo, « demo list »
                # affichait le contenu de cette démo.
                if [[ "$JGIT_DEMO_SCOPE" == "active" ]] && demo_parse_branch "$current_branch" 2>/dev/null; then
                    warn_deprecated_syntax "jgit demo list (depuis $current_branch)" "jgit demo show $DEMO_NAME"
                    demo_show_cmd "$current_branch"
                else
                    demo_list_cmd "$JGIT_DEMO_SCOPE"
                fi
                ;;
            show)
                demo_show_cmd "$JGIT_TARGET"
                ;;
            create)
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_create_cmd "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE" ${JGIT_FROM_SOURCES[@]+"${JGIT_FROM_SOURCES[@]}"}
                ;;
            add|drop|refresh)
                if [[ ${#JGIT_FROM_SOURCES[@]} -eq 0 ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" \
                        "Précisez au moins un ticket avec --from." \
                        "jgit demo $JGIT_ACTION ${JGIT_TARGET:-<nom>} --from feature/<ticket>"
                fi
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                "demo_${JGIT_ACTION}_cmd" "$JGIT_TARGET" "${JGIT_FROM_SOURCES[@]}"
                ;;
            rebase)
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_rebase_cmd "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE" ${JGIT_FROM_SOURCES[@]+"${JGIT_FROM_SOURCES[@]}"}
                ;;
            continue)
                demo_continue_cmd "$JGIT_TARGET"
                ;;
            abort)
                demo_abort_cmd "$JGIT_TARGET"
                ;;
            candidates)
                demo_candidates_cmd "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            bases)
                demo_bases_cmd
                ;;
            archive)
                demo_archive_cmd "$JGIT_TARGET"
                ;;
            unarchive)
                demo_unarchive_cmd "$JGIT_TARGET"
                ;;
            delete)
                demo_delete_cmd "$JGIT_TARGET"
                ;;
            migrate)
                refuse_if_worktree_dirty "Une démo" || exit_safe 1
                demo_migrate_cmd "$JGIT_TARGET" "$JGIT_BASED_ON_OVERRIDE"
                ;;
            *)
                jgit_fail usage "$JGIT_EXIT_ERROR" "Action '$JGIT_ACTION' non supportée pour demo."
                ;;
        esac
        ;;
    util)
        if [[ -z "$JGIT_ACTION" ]]; then
            help
            jgit_error_set usage "Action manquante pour le scope $JGIT_TYPE." "jgit --help"
            exit_safe 1
        fi
        case "$JGIT_ACTION" in
            clean)
                clean_branches
                ;;
            status)
                util_status_cmd
                ;;
            check_rebase)
                # Le positionnel serait ignoré en silence : on préfère le dire.
                if [[ -n "$JGIT_TARGET" ]]; then
                    jgit_fail usage "$JGIT_EXIT_ERROR" "Pour désigner une branche, utilisez --from $JGIT_TARGET."
                fi
                util_check_rebase ${JGIT_FROM_SOURCES[@]+"${JGIT_FROM_SOURCES[@]}"}
                exit $?
                ;;
            verify_rebase)
                util_verify_rebase "$JGIT_INTO_TARGET" "${JGIT_FROM_SOURCES[@]}"
                exit $?
                ;;
            *)
                jgit_fail usage "$JGIT_EXIT_ERROR" "Action '$JGIT_ACTION' non supportée pour util."
                ;;
        esac
        ;;
    audit)
        case "$JGIT_ACTION" in
            ""|tickets|demos) ;;
            *) jgit_fail usage "$JGIT_EXIT_ERROR" \
                   "Action '$JGIT_ACTION' non supportée pour audit." \
                   "jgit audit, jgit audit tickets ou jgit audit demos [<nom>]" ;;
        esac
        if [[ -n "$JGIT_TARGET" && "$JGIT_ACTION" != "demos" ]]; then
            jgit_fail usage "$JGIT_EXIT_ERROR" "Seul « jgit audit demos » accepte un nom de démo."
        fi
        audit_cmd "${JGIT_ACTION:-all}" "$JGIT_TARGET"
        ;;
    ui)
        if [[ -n "$JGIT_ACTION" ]]; then
            jgit_fail usage "$JGIT_EXIT_ERROR" "jgit ui ne prend pas d'action : jgit ui"
        fi
        jgit_ui
        ;;
    clean)
        # Rétrocompatibilité : « jgit clean » est devenu « jgit util clean ».
        warn_deprecated_syntax "jgit clean" "jgit util clean"
        clean_branches
        ;;
    *)
        jgit_fail usage "$JGIT_EXIT_ERROR" "Scope '$JGIT_TYPE' non supporté."
        ;;
 esac

exit_safe 0
