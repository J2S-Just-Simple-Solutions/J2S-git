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

    jgit_fetch_once || exit_safe 1

    if ! prod_branch=$(get_reference_branch "hotfix"); then
        exit_safe 1
    fi

    refuse_if_worktree_dirty "Une release" || exit_safe 1

    switch_branch "$prod_branch"

    # La release part de la version serveur de la production. Des commits locaux
    # non publiés ne sont ni écrasés ni rangés d'office : on s'arrête et on dit
    # quoi faire.
    refuse_if_branch_ahead "$prod_branch" "Une release" || exit_safe 1

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

    # C'est la version du serveur qui fait foi. La branche __PR__ porte le code
    # validé par la revue : une copie locale peut dater d'avant le squash-merge
    # de la PR, et on livrerait alors du code qui n'a jamais été validé.
    local merge_source=""

    if git show-ref --verify --quiet "refs/remotes/$j2s_remote/$resolved_branch"; then
        echo "Remote branch exists, use it..."
        merge_source="$j2s_remote/$resolved_branch"
    else
        printf "\033[1;31m/!\\ Feature branch '%s' was not found!\033[0m\n" "$resolved_branch"
        exit_safe 1
    fi

    # Le commit d'initialisation est posé sous le nom de la branche de travail,
    # pas sous celui de la branche de PR. Comparer à ce que l'utilisateur a
    # tapé laissait passer « --from __PR__feature/X », qui ne correspondait
    # jamais : le garde-fou ne se déclenchait que sur « --from feature/X ».
    local work_branch="${resolved_branch#$prefix_PR}"
    local last_commit_subject
    last_commit_subject=$(git log -1 --pretty=%s "$merge_source")
    if [[ "$last_commit_subject" == "$prefix_init_commit $work_branch $suffix_init_commit" ]]; then
        printf "\033[1;31m/!\\ La branche '%s' ne contient que le commit d'initialisation. Merci de valider et merger la PR avant d'intégrer dans la release.\033[0m\n" "$resolved_branch"
        exit_safe 1
    fi

    switch_branch "$release_branch"
    # Un merge en conflit laisse le dépôt à mi-chemin : sans contrôle du code de
    # retour, les sources suivantes échouaient à leur tour et la release était
    # tout de même poussée, amputée de tout ce qui suit. On s'arrête net.
    if ! git merge --no-ff "$merge_source" -m "$prefix_commit Release merge feature branch : $resolved_branch"; then
        git merge --abort >/dev/null 2>&1
        printf "\033[1;31mConflit lors de l'intégration de %s dans %s.\033[0m\n" "$resolved_branch" "$release_branch" >&2
        printf "Le merge a été annulé : la release n'a pas été poussée et rien n'est perdu.\n" >&2
        printf "Résolvez le conflit à la main (« git merge --no-ff %s »), puis relancez jgit pour les sources restantes.\n" "$merge_source" >&2
        exit_safe 1
    fi
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

    jgit_fetch_once || exit_safe 1

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
        # La production doit être alignée sur le serveur avant d'y fusionner la
        # release : sans cela jgit publierait, avec le merge, des commits que le
        # développeur n'a pas choisi de pousser.
        refuse_if_branch_ahead "$prod_branch" "Une release" || exit_safe 1
        echo "Merging release ${branch} in $prod_branch branch..."
        if ! git merge --no-ff "${branch}" -m "Merge release branch : ${branch}"; then
            git merge --abort >/dev/null 2>&1
            printf "\033[1;31mConflit lors de la fusion de %s dans %s.\033[0m\n" "$branch" "$prod_branch" >&2
            printf "Aucun tag n'a été posé, rien n'a été poussé et la branche de release est intacte.\n" >&2
            printf "Résolvez le conflit à la main puis relancez « jgit release finish --into %s ».\n" "$branch" >&2
            exit_safe 1
        fi
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
