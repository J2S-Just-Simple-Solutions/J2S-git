#!/bin/bash
source "$(dirname "$0")/functions.sh"

####################################
#            RELEASE
####################################

normalize_release_branch_name() {
    local identifier="$1"
    if [[ -z "$identifier" ]]; then
        echo ""
        return 0
    fi
    if [[ "$identifier" == release/* ]]; then
        echo "$identifier"
    else
        echo "release/$identifier"
    fi
}

checkout_release_branch() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        printf "\033[1;31mErreur : aucune branche de release fournie.\033[0m\n"
        exit_safe 1
    fi

    # switch_branch refuse lui-même une branche inexistante, avec le même
    # message, et garantit qu'on travaille sur la version du serveur.
    switch_branch "$branch"

    current_branch="$branch"
}

resolve_release_source_branch() {
    local source="$1"
    if [[ -z "$source" ]]; then
        echo ""
        return 0
    fi

    if [[ "$source" == __PR__* ]]; then
        echo "$source"
    else
        echo "$prefix_PR$source"
    fi
}

release_start() {
    local requested_version="$1"
    local future_tag=""
    local prod_branch

    if ! prod_branch=$(get_reference_branch "hotfix"); then
        exit_safe 1
    fi

    if [[ $(git status --porcelain) ]]; then
        echo "/!\\ Local changes, cannot start release"
        exit_safe 1
    fi

    switch_branch "$prod_branch"

    if [[ -n "$requested_version" ]]; then
        future_tag="$requested_version"
    else
        local current_tag
        current_tag=$(git tag -l --sort=-creatordate | head -n 1)
        echo "Current tag: ${current_tag}"

        local major=0
        local feature=0
        local minor=0
        local regex='([0-9]+)\.([0-9]+)\.([0-9]+)'

        if [[ $current_tag =~ $regex ]]; then
            major="${BASH_REMATCH[1]}"
            feature="${BASH_REMATCH[2]}"
            minor="${BASH_REMATCH[3]}"
        else
            echo "A tag must already exists (x.x.x format)"
            exit_safe 1
        fi

        feature=$((feature + 1))
        future_tag="${major}.${feature}.${minor}"
    fi

    local branch
    branch=$(normalize_release_branch_name "$future_tag")
    local existed_in_remote
    existed_in_remote=$(git ls-remote --heads "$j2s_remote" "$branch")

    echo "Searching a branch naming: ${branch}"

    if [[ -n ${existed_in_remote} ]]; then
        echo "Remote branch exists, use it..."
        switch_branch "$branch"
    else
        echo "Release does not exists, create it..."
        git reset --hard "$j2s_remote/$prod_branch"
        switch_branch "$branch" create
        git commit --allow-empty -m "$prefix_init_commit release ${branch}. $suffix_init_commit"
        git push "$j2s_remote" "$branch"
    fi

    current_branch="$branch"
    echo "$branch"
}

release_merge_single() {
    local release_branch="$1"
    local source_branch="$2"

    local resolved_branch
    resolved_branch=$(resolve_release_source_branch "$source_branch")
    if [[ -z "$resolved_branch" ]]; then
        printf "\033[1;31mAucune branche source fournie.\033[0m\n"
        exit_safe 1
    fi

    local existed_in_local
    existed_in_local=$(git branch --list "$resolved_branch")
    local existed_in_remote
    existed_in_remote=$(git ls-remote --heads "$j2s_remote" "$resolved_branch")
    local merge_source=""

    if [[ -n "$existed_in_local" ]]; then
        echo "Feature branch exists on local machine, use it..."
        merge_source="$resolved_branch"
    elif [[ -n "$existed_in_remote" ]]; then
        echo "Remote branch exists, use it..."
        merge_source="$j2s_remote/$resolved_branch"
    else
        printf "\033[1;31m/!\\ Feature branch '%s' was not found!\033[0m\n" "$resolved_branch"
        exit_safe 1
    fi

    local last_commit_subject
    last_commit_subject=$(git log -1 --pretty=%s "$merge_source")
    if [[ "$last_commit_subject" == "$prefix_init_commit $source_branch $suffix_init_commit" ]]; then
        printf "\033[1;31m/!\\ La branche '%s' ne contient que le commit d'initialisation. Merci de valider et merger la PR avant d'intégrer dans la release.\033[0m\n" "$resolved_branch"
        exit_safe 1
    fi

    switch_branch "$release_branch"
    git merge --no-ff "$merge_source" -m "$prefix_commit Release merge feature branch : $resolved_branch"
}

release_merge() {
    local requested_version="$1"
    local explicit_into="$2"
    shift 2 || true
    local sources=("$@")

    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "Aucune branche source à fusionner." >&2
        exit_safe 1
    fi

    # Les références __PR__ doivent être à jour avant le contrôle « la branche
    # ne contient que son commit d'initialisation » : sans cela une PR mergée
    # est vue comme non mergée.
    jgit_fetch_once || exit_safe 1

    local release_branch
    if [[ -n "$explicit_into" ]]; then
        release_branch=$(normalize_release_branch_name "$explicit_into")
        checkout_release_branch "$release_branch"
    else
        release_start "$requested_version"
        release_branch=$(git rev-parse --abbrev-ref HEAD)
    fi

    if [[ -z "$release_branch" ]]; then
        release_branch=$(git rev-parse --abbrev-ref HEAD)
    fi

    for source in "${sources[@]}"; do
        release_merge_single "$release_branch" "$source"
    done

    git push "$j2s_remote" "$release_branch"
}

release_finish() {
    local requested_target="$1"
    local branch="$requested_target"
    local prod_branch

    if ! prod_branch=$(get_reference_branch "hotfix"); then
        exit_safe 1
    fi

    if [[ -n "$requested_target" ]]; then
        branch=$(normalize_release_branch_name "$requested_target")
        checkout_release_branch "$branch"
    else
        branch=$(git rev-parse --abbrev-ref HEAD)
        local regex_branch='release/([0-9]+)\.([0-9]+)\.([0-9]+)'
        if [[ ! $branch =~ $regex_branch ]]; then
            release_start
            branch=$(git rev-parse --abbrev-ref HEAD)
        fi
    fi

    local regex_tag='([0-9]+)\.([0-9]+)\.([0-9]+)'
    local regex_branch='release/'$regex_tag

    if [[ $branch =~ $regex_branch ]]; then
        echo "Already in release branch"
        local future_feature="${BASH_REMATCH[2]}"

        local current_tag
        current_tag=$(git tag -l --sort=-creatordate | head -n 1)
        local current_feature=0
        if [[ $current_tag =~ $regex_tag ]]; then
            current_feature="${BASH_REMATCH[2]}"
        fi

        if [[ $future_feature -le $current_feature ]]; then
            echo "/!\\ Local release does not have the right tag, switching to new branch"
            release_start
            branch=$(git rev-parse --abbrev-ref HEAD)
        fi
    else
        echo "Switch to release branch"
        release_start
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi

    echo "Release: ${branch}"
    local last_commit_message
    last_commit_message=$(git log -1 --pretty=%B)

    if [[ $last_commit_message == "$prefix_init_commit release ${branch}. $suffix_init_commit" ]]; then
        echo "It seems that the release is empty..."
        exit_safe 1
    fi

    if [[ $branch =~ $regex_branch ]]; then
        local major="${BASH_REMATCH[1]}"
        local feature="${BASH_REMATCH[2]}"
        local minor="${BASH_REMATCH[3]}"
        local future_tag="${major}.${feature}.${minor}"
        echo "Future tag: ${future_tag}"
        switch_branch "$prod_branch"
        # La branche de release va être supprimée : sans cela, exit_safe
        # tenterait de revenir sur une branche qui n'existe plus.
        current_branch="$prod_branch"
        git reset --hard "$j2s_remote/$prod_branch"
        echo "Merging release ${branch} in $prod_branch branch..."
        git merge --no-ff "${branch}" -m "Merge release branch : ${branch}"
        echo "Create new tag ${future_tag}"
        git tag "${future_tag}"
        git push "$j2s_remote" "$prod_branch"
        echo "Delete local branch ${branch}"
        git branch -D "${branch}"
        echo "Delete remote branch ${branch}"
        git push -d "$j2s_remote" "${branch}"
        git push "$j2s_remote" tag "${future_tag}"
        # Le merge sur $prod_branch et le tag sont déjà poussés : seule la
        # release GitHub manque, le message doit le dire sans laisser croire
        # qu'il faut rejouer la release entière.
        if ! gh release create "${future_tag}" --generate-notes; then
            printf "\033[1;31mLa release GitHub %s n'a pas pu être créée.\033[0m\n" "${future_tag}" >&2
            printf "Le merge sur %s et le tag %s sont poussés : il ne reste que la release GitHub.\n" "$prod_branch" "${future_tag}" >&2
            printf "Relancez « gh release create %s --generate-notes ».\n" "${future_tag}" >&2
            exit_safe 1
        fi
    else
        echo "Release branch seems to have a wrong format..."
        exit_safe 1
    fi
}
