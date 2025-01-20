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
    feature_type=$1
    feature_name=$2
    branch=$1/$feature_name
    branch_PR=$prefix_PR$branch

    branch_in_local=$( git branch --list ${branch} )
    branch_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch})

    git fetch $j2s_remote --quiet

    if [[ -n ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Exists in remote and local"
        echo "Use local branch"
        git checkout $branch
        git pull
    elif [[ -z ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Exists in remote but not in local"
        echo "Use remote branch"
        git checkout -b $branch $j2s_remote/$branch
    elif [[ -n ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
        echo "Exists in local and not in remote"
        echo "Is this feature already merged ?"
    elif [[ -z ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
        if [[ $feature_type == "hotfix" ]]; then
            reference_branch=$branch_prod;
        else
            reference_branch=$branch_preprod
        fi

        echo "Checkout and reset $reference_branch branch"
<<<<<<< HEAD
        git checkout $reference_branch --quiet
=======
        git checkout -B $reference_branch --quiet
>>>>>>> origin/__PR__feature/demo
        echo "Create pull request branch $branch_PR branch"
        git checkout -b $branch_PR --quiet
        git push $j2s_remote $branch_PR --quiet
        echo "Create working branch $branch branch"
        git checkout -b $branch --quiet
        git commit --allow-empty -m "$prefix_init_commit $branch $suffix_init_commit" --quiet
        git push --set-upstream $j2s_remote $branch --quiet
        git branch -D $branch_PR --quiet
        echo "Create pull request"
        gh pr create --title $feature_name --body "https://justsimplesolutions.atlassian.net/browse/"$feature_name --base=$branch_PR --head=$branch --label "NFR"
    else
        echo "On est dans la Matrix"
    fi

    exit_safe 1
}

feature_rebase() {
    feature_type=$1
    feature_name=$2
    branch=$1/$feature_name
    branch_PR=$prefix_PR$branch

    current_date=`date '+%s'`

    git fetch $j2s_remote --quiet

    branch_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch})
    branch_PR_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch_PR})
    branch_in_local=$( git branch --list ${branch} )
    branch_PR_in_local=$( git branch --list ${branch_PR} )

    if [[ $feature_type == "hotfix" ]]; then
        reference_branch=$branch_prod;
    else
        reference_branch=$branch_preprod
    fi

    if [[ -z ${branch_in_remote} ]]; then
        echo "Something get wrong, $branch doesn't exist on remote"
        exit_safe 0
    elif [[ -z ${branch_PR_in_remote} ]] ; then
        echo "Something get wrong, the branch $branch_PR doesn't exist on remote"
        exit_safe 0
    fi

    if [[ -z ${branch_in_local} ]]; then
        echo "$branch exists in remote but not in local"
        echo "Use remote branch"
        git checkout -b $branch $j2s_remote/$branch
    fi


    if [[ -z ${branch_PR_in_local} ]]; then
        echo "$branch_PR exists in remote but not in local"
        echo "Use remote branch"
        git checkout -b $branch_PR $j2s_remote/$branch_PR
    fi

    echo "Checkout and reset $reference_branch branch"
    git checkout $reference_branch --quiet
    git pull $j2s_remote $reference_branch --quiet
    echo "Rebase $branch_PR"
    git checkout $branch_PR
    git reset --hard $branch_PR --quiet
    git checkout -B "save_"$current_date"_"$branch_PR --quiet
    git checkout $branch_PR
    git rebase $reference_branch $branch_PR
    git push --force
    echo "Rebase $branch"
    git checkout $branch
    git reset --hard $branch --quiet
    git checkout -B "save_"$current_date"_"$branch --quiet
    git checkout $branch
    git rebase $branch_PR $branch
    git push --force
    echo "Clean up"
    git branch -D $branch_PR
    echo "Rebase finished successfully"
}

####################################
#            RELEASE
####################################

release_start() {
    if [[ $(git status --porcelain) ]]; then
        echo "/!\ Local changes, cannot start release"
        exit_safe 0;
    fi

    git checkout $branch_prod
    git fetch $j2s_remote
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
    existed_in_remote=$(git ls-remote --heads $j2s_remote ${branch})

    echo "Searching a branch naming: ${branch}"

    if [[ ! -z ${existed_in_remote} ]]; then
        if [[ ! -z ${existed_in_local} ]]; then
            echo "Release ${branch} local branch exists, deletion..."
            git branch -D ${branch}
        fi
        echo "Remote branch exists, use it..."
        git checkout --track $j2s_remote/${branch}
    
        return 1;
    fi

    echo "Release does not exists, create it..."
    git reset --hard $j2s_remote/$branch_prod
    git checkout -b ${branch}
    git commit --allow-empty -m "$prefix_init_commit release ${branch}. $suffix_init_commit"
    git push $j2s_remote ${branch}
}

release_merge() {
    release_start
    branch=$branch_PR;
    existed_in_local=$(git branch --list ${branch})
    existed_in_remote=$(git ls-remote --heads $j2s_remote ${branch})
    release_branch=$(git rev-parse --abbrev-ref HEAD)
    existed=0

    echo "Searching a branch naming: ${branch}"

    if [[ ! -z ${existed_in_local} ]]; then
        echo "Feature branch exists on local machine, use it..."
        existed=1
        git merge --no-ff ${branch} -m "$prefix_commit Merge feature branch : $branch $suffix_init_commit"
    fi

    if [[ ! -z ${existed_in_remote} && existed=0 ]]; then
        echo "Remote branch exists, use it..."
        existed=1
        git merge --no-ff $j2s_remote/${branch} -m "$prefix_commit Merge feature branch : $branch $suffix_init_commit"
    fi

    if [[ $existed == 0 ]]; then
        echo "/!\ Feature branch was not found!"

        exit_safe 0
    fi

   git push $j2s_remote ${release_branch}
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
        release_start
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    else
    echo "Switch to release branch"
    release_start
    branch=$(git rev-parse --abbrev-ref HEAD)
    fi

    echo "Release: ${branch}"
    last_commit_message=$(git log -1 --pretty=%B)

    if [[ $last_commit_message == "$prefix_init_commit release ${branch}. $suffix_init_commit" ]]; then
        echo "It seems that the release is empty..."

        exit_safe 0;
    fi

    if [[ $branch =~ $regex_branch ]]; then
        major="${BASH_REMATCH[1]}"
        feature="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
    else
        echo "Release branch seems to have a wrong format..."

        exit_safe 0
    fi

    future_tag="${major}.${feature}.${minor}"
    echo "Future tag: ${future_tag}"
    git checkout $branch_prod
    git fetch $j2s_remote
    git reset --hard $j2s_remote/$branch_prod
    echo "Merging release ${branch} in $branch_prod branch..."
    git merge --no-ff ${branch} -m "Merge release branch : ${branch}"
    echo "Create new tag ${future_tag}"
    git tag ${future_tag}
    git push $j2s_remote $branch_prod
    echo "Delete local branch ${branch}"
    git branch -D ${branch}
    echo "Delete remote branch ${branch}"
    git push -d $j2s_remote ${branch}
    git push $j2s_remote tag ${future_tag}

    gh release create ${future_tag} --generate-notes
}


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
    git stash push -m "[jGIT]" -u
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
