####################################
#
#         LOCAL PARAMETERS
# Update this section to fit your local
#
####################################

j2s_remote="origin"
reference_branch="develop"

####################################
#
#        MANDATORY PARAMETERS
# This section should be the same
#         for all developers
#
####################################
prefix_PR="__PR__"
prefix_init_commit="[jgit INIT COMMIT]"
suffix_init_commit=""

####################################
#
#         GLOBAL VERIFICATIONS
#
####################################
remotes=$( git remote -v )

if [[ $remotes != *$j2s_remote* ]]; then
  echo "Please configure J2S remote as "$j2s_remote
  exit 0
fi

diff=$( git diff )

stash=false;
if [[ -n $diff ]]; then
    echo "You have uncommited modifications."
    read -p "Do you want to stash and unstash changes at the end of process ? [y/n] " yn
    echo
    if [[ ! $yn =~ ^[Yy]$ ]]; then
        exit 0
    fi
    git stash save "[jGIT]"
    echo "ici1"
    stash=true;
fi

####################################
#
#         Functions
#
####################################

create_all_branches() {
    echo "Checkout and reset $reference_branch branch"
    git checkout $reference_branch --quiet
    git fetch $j2s_remote --quiet
    git reset --hard $reference_branch --quiet
    echo "Create pull request branch $branch_PR branch"
    git checkout -B $branch_PR --quiet
    git push $j2s_remote $branch_PR --quiet
    echo "Create working branch $branch branch"
    git checkout -B $branch --quiet
    git commit --allow-empty -m "$prefix_init_commit $branch $suffix_init_commit" --quiet
    git push --set-upstream $j2s_remote $branch --quiet
    git branch -D $branch_PR --quiet
    echo "Create pull request"
    gh pr create --title $feature_name --body "https://justsimplesolutions.atlassian.net/browse/"$feature_name --base=$branch_PR --head=$branch --label "NFR"
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
        create_all_branches
    else
        echo "On est dans la Matrix"
    fi

    if $stash; then
        git stash pop
    fi
}

################################################################################
# Help                                                                         #
################################################################################
help()
{
    echo "This script is used to manage feature or hotfix creation for development purpose."
    echo
    echo "It will create a branch correctly named on local and on J2S remote."
    echo "It will create all needed branches to create a clean PR on Github."
    echo "The PR will be created automatically by github client cli."
    echo
    echo "For now, only new feature or hotfix creation is supported."
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
    branch_PR=$prefix_PR$branch

    create;
elif [[ $1 == "help" ]]; then
    help
    exit 1;
else
    echo "argument $1 note supported"
    exit 0
fi
