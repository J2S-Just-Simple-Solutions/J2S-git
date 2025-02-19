#!/bin/bash
source "$(dirname "$0")/functions.sh"

feature_start() {
    local feature_type=$1
    local feature_name=$2
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch

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
        git checkout $reference_branch --quiet
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