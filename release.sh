#!/bin/bash
source "$(dirname "$0")/functions.sh"

####################################
#            RELEASE
####################################

release_start() {
    if [[ $(git status --porcelain) ]]; then
        echo "/!\ Local changes, cannot start release"
        exit_safe 1;
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

        exit_safe 1
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
        git merge --no-ff ${branch} -m "$prefix_commit Merge feature branch : $branch"
    fi

    if [[ ! -z ${existed_in_remote} && existed=0 ]]; then
        echo "Remote branch exists, use it..."
        existed=1
        git merge --no-ff $j2s_remote/${branch} -m "$prefix_commit Merge feature branch : $branch"
    fi

    if [[ $existed == 0 ]]; then
        echo "/!\ Feature branch was not found!"

        exit_safe 1
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

        exit_safe 1;
    fi

    if [[ $branch =~ $regex_branch ]]; then
        major="${BASH_REMATCH[1]}"
        feature="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
    else
        echo "Release branch seems to have a wrong format..."

        exit_safe 1
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
