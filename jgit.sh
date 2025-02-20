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

################################################################################
# Help                                                                         #
################################################################################
help()
{
    echo "This script is used to manage feature, hotfix or release creation for development purpose."
    echo
    echo "Syntax:"
    echo "jgit [feature|hotfix] start <feature_name>"
    echo " -> Create a new feature or hotfix or checkout on it."
    echo "jgit [feature|hotfix] rebase <feature_name>"
    echo " -> Rebase the feature or hotfix on main branch. In case of conflicts follow git commands before re-running this script"
    echo "jgit release merge <branch_name>"
    echo " -> Merge a branch in the current release."
    echo "jgit release finish "
    echo " -> Will close the current release : merge the current release branch, create the tag and the release in github."
    echo "jgit clean "
    echo " -> Will clean all local branches to remove working branches as rebase and __PR__."
    echo "options:"
    echo "-h                                    Print this Help."

    echo
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
        exit 1
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
  exit_safe 0
fi

# Manage syntax
if [[ $JGIT_TYPE == "feature" ]] || [[ $JGIT_TYPE == "hotfix" ]]; then
    if [[ -z $JGIT_NAME ]]; then
        echo "Please set a $JGIT_TYPE name as third argument"
        exit_safe 0;
    fi
    
    if [[ -z $JGIT_ACTION ]]; then
        help
    fi
    if [[ $JGIT_ACTION == "start" ]]; then
        verify_stash
        feature_start $JGIT_TYPE $JGIT_NAME $JGIT_BASED_ON;
    elif [[ $JGIT_ACTION == "rebase" ]]; then
        verify_stash
        feature_rebase $JGIT_TYPE $JGIT_NAME $JGIT_BASED_ON
    else
        echo "argument $JGIT_ACTION note supported"
        exit_safe 0
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
            exit_safe 0;
        fi
        branch_PR=$prefix_PR$JGIT_NAME
        release_merge;
    else
        echo "argument $JGIT_ACTION not supported"
        exit_safe 0
    fi
elif [[ $JGIT_TYPE == "help" ]] || [[ $JGIT_TYPE == "-h" ]]; then
    help
    exit_safe 1;
elif [[ $JGIT_TYPE == "clean" ]]; then
    clean_branches
else
    echo "argument $JGIT_TYPE not supported"
    exit_safe 0
fi
exit_safe 1
