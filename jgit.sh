source "$(dirname "$0")/feature.sh"
source "$(dirname "$0")/release.sh"
source "$(dirname "$0")/rebase.sh"

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
    source $FILE
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
stash=false;

current_branch=$(git rev-parse --abbrev-ref HEAD)

################################################################################
# Help                                                                         #
################################################################################
help() {
    printf "\n\033[1;34mUsage:\033[0m\n"
    printf "  jgit \033[1;32m[feature|hotfix]\033[0m start \033[1;36m<feature_name>\033[0m \033[38;5;214m[OPTIONAL]\033[0m --based-on \033[1;36m<branch_name>\033[0m\n"
    printf "    → Crée une nouvelle feature ou hotfix ou permet de s'y positionner.\n"
    printf "    → --based-on permet de choisir la branche sur laquelle se baser.\n\n"

    printf "  jgit \033[1;32m[feature|hotfix]\033[0m rebase \033[1;36m<feature_name>\033[0m \033[38;5;214m[OPTIONAL]\033[0m --based-on \033[1;36m<branch_name>\033[0m\n"
    printf "    → Rebase la feature ou le hotfix sur la branche principale.\n"
    printf "      En cas de conflits, suivez les commandes git avant de relancer ce script.\n\n"
    printf "    → --based-on permet de choisir la branche sur laquelle se baser.\n"

    printf "  jgit \033[1;32mrelease\033[0m merge \033[1;36m<branch_name>\033[0m\n"
    printf "    → Fusionne une branche dans la release en cours.\n"
    printf "    → La release est créée à la volée au besoin.\n\n"

    printf "  jgit \033[1;32mrelease\033[0m finish\n"
    printf "    → Ferme la release en cours : fusion de la branche release,\n"
    printf "      création du tag et publication sur GitHub.\n\n"

    printf "  jgit \033[1;32mclean\033[0m\n"
    printf "    → Nettoie les branches locales temporaires comme les branches de rebase et __PR__.\n\n"

    printf "\033[1;34mOptions:\033[0m\n"
    printf "  -h    Affiche cette aide.\n\n"
}


####################################
#
#      Manage parameters
#
####################################
# Définition des variables
JGIT_TYPE=$1
JGIT_ACTION=$2
JGIT_NAME=$3
JGIT_BASED_ON=""  # Valeur par défaut


# Parcourir tous les arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --based-on)
      if [[ -n "$2" && "$2" != -* ]]; then
        JGIT_BASED_ON="$2"  # Récupérer la valeur suivante
        shift 2         # Passer à l'argument suivant
      else
        echo "Erreur : L'option --based-on nécessite un argument." >&2
        exit_safe 1
      fi
      ;;
    *)
      shift
      ;;
  esac
done

####################################
#
#         RUNNING script
#
####################################

# GLOBAL VERIFICATIONS
remotes=$( git remote -v )

if [[ $remotes != *$j2s_remote* ]]; then
  echo "Please configure J2S remote as "$j2s_remote
  exit_safe 1
fi

# Manage syntax
if [[ $JGIT_TYPE == "feature" ]] || [[ $JGIT_TYPE == "hotfix" ]]; then
    if [[ -z $JGIT_NAME ]]; then
        echo "Please set a $JGIT_TYPE name as third argument"
        exit_safe 1;
    fi
    
    if [[ -z $JGIT_ACTION ]]; then
        help
    fi
    if [[ $JGIT_ACTION == "start" ]]; then
        verify_stash
        feature_start $JGIT_TYPE $JGIT_NAME $JGIT_BASED_ON;
    elif [[ $JGIT_ACTION == "restart" ]]; then
        verify_stash
        feature_restart $JGIT_TYPE $JGIT_NAME $JGIT_BASED_ON
    elif [[ $JGIT_ACTION == "rebase" ]]; then
        verify_stash
        feature_rebase $JGIT_TYPE $JGIT_NAME $JGIT_BASED_ON
    else
        echo "argument $JGIT_ACTION note supported"
        exit_safe 1
    fi
elif [[ $JGIT_TYPE == "release" ]]; then
    if [[ -z $JGIT_ACTION ]]; then
        help
    fi
    verify_stash
    if [[ $JGIT_ACTION == "start" ]]; then 
        release_start;
    elif [[ $JGIT_ACTION == "finish" ]]; then 
        release_finish;
    elif [[ $JGIT_ACTION == "merge" ]]; then 
        if [[ -z $JGIT_NAME ]]; then
            echo "Please set a branch name as third argument"
            exit_safe 1;
        fi
        branch_PR=$prefix_PR$JGIT_NAME
        release_merge;
    else
        echo "argument $JGIT_ACTION not supported"
        exit_safe 1
    fi
elif [[ $JGIT_TYPE == "help" ]] || [[ $JGIT_TYPE == "-h" ]]; then
    help
    exit_safe 0;
elif [[ $JGIT_TYPE == "clean" ]]; then
    clean_branches
else
    echo "argument $JGIT_TYPE not supported"
    exit_safe 1
fi
exit_safe 0
