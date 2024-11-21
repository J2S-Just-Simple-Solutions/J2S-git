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
prefix_commit="[jgit]"
prefix_init_commit="$prefix_commit INIT"
suffix_init_commit=""
stash=false;

####################################
#
#         Functions
#
####################################

exit_safe() {
    if $stash; then
        git stash pop
    fi

    if [[ $1 == 0 ]]; then
        echo "/!\ Script finished in error! Be careful about your branch management on local."

        exit $1
    fi

    exit $1
}

feature_start() {
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
    else
        echo "On est dans la Matrix"
    fi

    if $stash; then
        git stash pop
    fi
}

release_start() {
    if [[ $(git status --porcelain) ]]; then
        echo "/!\ Local changes, cannot start release"
        exit_safe 0;
    fi

    git checkout $reference_branch
    git fetch origin
    current_tag=$(git tag -l --sort=-creatordate | head -n 1)
    echo "Current tag: ${current_tag}"
    major=0
    feature=0
    minor=0

    regex="([0-9]+).([0-9]+).([0-9]+)"
    if [[ $current_tag =~ $regex ]]; then
        major="${BASH_REMATCH[1]}"
        feature="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
    else
        echo "A tag must already exists (x.x.x format)"

        exit_safe 0
    fi
    feature=$(echo $feature + 1 | bc)
    future_tag="${major}.${feature}.${minor}"

    branch=release/${future_tag};
    existed_in_local=$(git branch --list ${branch})
    existed_in_remote=$(git ls-remote --heads origin ${branch})

    echo "Searching a branch naming: ${branch}"

    if [[ ! -z ${existed_in_remote} ]]; then
        if [[ ! -z ${existed_in_local} ]]; then
            echo "Release ${branch} local branch exists, deletion..."
            git branch -D ${branch}
        fi
        echo "Remote branch exists, use it..."
        git checkout --track origin/${branch}
    
        return 1;
    fi

    echo "Release does not exists, create it..."
    git reset --hard origin/$reference_branch
    git checkout -b ${branch}
    git commit --allow-empty -m "$prefix_init_commit release ${branch}. $suffix_init_commit"
    git push origin ${branch}
}

release_merge() {
    release_start
    branch=$branch_PR;
    existed_in_local=$(git branch --list ${branch})
    existed_in_remote=$(git ls-remote --heads origin ${branch})
    release_branch=$(git rev-parse --abbrev-ref HEAD)
    existed=0

    echo "Searching a branch naming: ${branch}"

    if [[ ! -z ${existed_in_local} ]]; then
        echo "Feature branch exists on local machine, use it..."
        existed=1
        git merge --no-ff ${branch} -m "$prefix_commit Merge feature branch : $branch"
    fi

    if [[ ! -z ${existed_in_remote} && existed=0 ]]; then
        echo "Remote branch exists, use it..."
        existed=1
        git merge --no-ff origin/${branch} -m "$prefix_commit Merge feature branch : $branch"
    fi

    if [[ $existed == 0 ]]; then
        echo "/!\ Feature branch was not found!"

        exit 0
    fi

   git push origin ${release_branch}
}

release_finish() {
    branch=$(git rev-parse --abbrev-ref HEAD)
    regex_tag="([0-9]+).([0-9]+).([0-9]+)"
    regex_branch="release/${regex_tag}"

    if [[ $branch =~ $regex_branch ]]; then
    echo "Already in release branch"
    future_feature="${BASH_REMATCH[2]}"

    current_tag=$(git tag -l --sort=-creatordate | head -n 1)
    [[ $current_tag =~ $regex_tag ]] && current_feature="${BASH_REMATCH[2]}"

    if [[ $future_feature > $current_feature ]]; then
        echo "Use current local release ${branch}"
    else
        echo "/!\ Local release does not have the right tag, switching to new branch"
        swkflow_start_release
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    else
    echo "Switch to release branch"
    swkflow_start_release
    branch=$(git rev-parse --abbrev-ref HEAD)
    fi

    echo "Release: ${branch}"
    last_commit_message=$(git log -1 --pretty=%B)

    if [[ $last_commit_message == "[swk] Init release ${branch}. [skip ci]" ]]; then
        echo "It seems that the release is empty..."

        exit 0;
    fi

    if [[ $branch =~ $regex_branch ]]; then
    major="${BASH_REMATCH[1]}"
    feature="${BASH_REMATCH[2]}"
    minor="${BASH_REMATCH[3]}"
    else
    echo "Release branch seems to have a wrong format..."

    exit 0
    fi

    future_tag="${major}.${feature}.${minor}"
    echo "Future tag: ${future_tag}"
    git checkout $reference_branch
    git fetch origin
    git reset --hard origin/$reference_branch
    echo "Merging release ${branch} in $reference_branch branch..."
    git merge --no-ff ${branch} -m "Merge release branch : ${branch}"
    echo "Create new tag ${future_tag}"
    git tag ${future_tag}
    git push origin $reference_branch
    echo "Delete local branch ${branch}"
    git branch -D ${branch}
    echo "Delete remote branch ${branch}"
    git push -d origin ${branch}
    git push origin tag ${future_tag}
}

####################################
#
#         GLOBAL VERIFICATIONS
#
####################################
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

################################################################################
# Help                                                                         #
################################################################################
help()
{
    echo "This script is used to manage feature or hotfix creation for development purpose."
    echo
    echo "It will create branches correctly named on local and on J2S remote."
    echo "It will create all needed branches to create a clean PR on Github."
    echo "The PR will be created automatically by github client cli."

    echo
    echo "For now, only new feature or hotfix creation is supported."
    echo
    echo "Syntax: jgit [feature|hotfix] start <feature_name>"
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

if [[ $1 == "feature" ]] || [[ $1 == "hotfix" ]]; then
    if [[ -z $3 ]]; then
        echo "Please set a $1 name as third argument"
        exit_safe 0;
    fi
    feature_name=$3
    branch=$1-$feature_name
    branch_PR=$prefix_PR$branch
    
    if [[ -z $2 ]]; then
        help
    fi
    if [[ $2 == "start" ]]; then
        feature_start;
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
