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
    echo "options:"
    echo "-h                                    Print this Help."

    echo
}

####################################
#
#         RUNNING script
#
####################################

# Manage options
while getopts ':hs:' option; do
  case "$option" in
    h) help
       exit_safe 1
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit_safe 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit_safe 1
       ;;
  esac
done

# GLOBAL VERIFICATIONS
remotes=$( git remote -v )

if [[ $remotes != *$j2s_remote* ]]; then
  echo "Please configure J2S remote as "$j2s_remote
  exit_safe 0
fi

if [[ $(git status --porcelain) ]]; then
    echo "You have uncommited modifications."
    read -p "Do you want to stash and unstash changes at the end of process ? [y/n] " yn
    echo
    if [[ ! $yn =~ ^[Yy]$ ]]; then
        exit_safe 0
    fi
    git stash save "[jGIT]"
    stash=true;
fi

# Manage syntax
if [[ $1 == "feature" ]] || [[ $1 == "hotfix" ]]; then
    if [[ -z $3 ]]; then
        echo "Please set a $1 name as third argument"
        exit_safe 0;
    fi
    feature_name=$3
    
    if [[ -z $2 ]]; then
        help
    fi
    if [[ $2 == "start" ]]; then
        feature_start $1 $feature_name;
    elif [[ $2 == "rebase" ]]; then
        feature_rebase $1 $feature_name
    else
        echo "argument $2 note supported"
        exit_safe 0
    fi
elif [[ $1 == "release" ]]; then
    if [[ -z $2 ]]; then
        help
    fi
    if [[ $2 == "start" ]]; then 
        release_start;
    elif [[ $2 == "finish" ]]; then 
        release_finish;
    elif [[ $2 == "merge" ]]; then 
        if [[ -z $3 ]]; then
            echo "Please set a branch name as third argument"
            exit_safe 0;
        fi
        branch_PR=$prefix_PR$3
        release_merge;
    else
        echo "argument $2 note supported"
        exit_safe 0
    fi
elif [[ $1 == "help" ]]; then
    help
    exit_safe 1;
else
    echo "argument $1 note supported"
    exit_safe 0
fi
exit_safe 1
