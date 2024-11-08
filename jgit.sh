####################################
#
#         LOCAL PARAMETERS
# Update this section to fit your local
#
####################################

own_remote="bankette"
j2s_remote="origin"
reference_branch="main"

github_own_remote_name=$own_remote
github_project_name="J2S-Akeneo"

remotes=$( git remote -v )

####################################
#
#         GLOBAL VERIFICATIONS
#
####################################

if [[ $remotes != *$j2s_remote* ]]; then
  echo "Please configure J2S remote as "$j2s_remote
  exit 0
fi

if [[ $remotes != *$own_remote* ]]; then
  echo "Please configure your own remote as "$own_remote
  exit 0
fi

diff=$( git diff )

if [[ -n $diff ]]; then
  echo "Please commit or stash all changes before resuming"
  git diff
  exit 0
fi


####################################
#
#         Functions
#
####################################

create_all_branches() {
    echo "Checkout and update $reference_branch branch"
    git checkout $reference_branch
    git fetch $j2s_remote
    git pull $j2s_remote $reference_branch
    git checkout -B $branch
    git push $j2s_remote $branch
    git commit --allow-empty -m "[jgit INIT COMMIT $reference_branch]"
    git push $own_remote $branch
# Les pull request ne focntionne pas car le client ne permet pas de créé des PR entre deux remotes...
#    gh pr create --title $feature_name --body "jira/"$feature_name --web
}

create() {
    branch_in_local=$( git branch --list ${branch} )
    branch_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch})

    if [[ -n ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Existe en distant et en local"
        echo "Non géré pour le moment"
    elif [[ -z ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Existe en distant mais pas en local"
        echo "Non géré pour le moment"
    elif [[ -n ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
        echo "Existe en local mais pas en distant"
        echo "Non géré pour le moment"
    elif [[ -z ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
    #    echo "N'existe pas"
        create_all_branches
    else
        echo "On est dans la Matrix"
    fi
}

################################################################################
# Help                                                                         #
################################################################################
help()
{
    echo "This script is used to manage feature or hotfix creation for development purpose."
    echo
    echo "It will create a branch correctly named on local, on your own remote and on J2S remote as well."
    echo
    echo "Syntax: jgit [feature|hotfix] feature_name"
    echo "options:"
    echo "-h    Print this Help."
    echo
}


####################################
#
#         RUNNING script
#
####################################

while getopts ':hs:' option; do
  case "$option" in
    h) help
       exit 1
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done

if [[ $1 == "feature" ]] || [[ $1 == "hotfix" ]]; then
    if [[ -z $2 ]]; then
        echo "Please set a $1 name as second argument"
        exit 0;
    fi
    feature_name=$2
    branch=$1-$feature_name

    create;
elif [[ $1 == "help" ]]; then
    help
    exit 1;
else
    echo "argument $1 note supported"
    exit 0
fi
