#!/bin/bash
source "$(dirname "$0")/functions.sh"

DemoBranchPrefix="demo_"

get_demo_branch_name() {
    local suffix="$1"
    echo "${DemoBranchPrefix}${suffix}"
}

is_demo_branch() {
    local branch="$1"
    [[ "$branch" == ${DemoBranchPrefix}* ]]
}

demo_start() {
    local requested_name="$1"
    local based_on="$2"
    local _unused_into="$3"
    local current_local_branch=$(git rev-parse --abbrev-ref HEAD)

    local base_branch
    if [[ -n "$based_on" ]]; then
        base_branch="$based_on"
    else
        base_branch=$(get_reference_branch)
    fi

    if [[ -z "$base_branch" ]]; then
        echo "Impossible de déterminer la branche de référence pour la démo."
        exit_safe 1
    fi

    if [[ -z "$requested_name" ]]; then
        requested_name="$base_branch"
    fi

    local demo_branch
    demo_branch=$(get_demo_branch_name "$requested_name")

    git fetch "$j2s_remote" --quiet

    local remote_exists
    remote_exists=$(git ls-remote --heads "$j2s_remote" "$demo_branch")

    if [[ -n "$remote_exists" ]]; then
        if git show-ref --verify --quiet "refs/heads/$demo_branch"; then
            git checkout "$demo_branch" --quiet
            if ! git pull --ff-only "$j2s_remote" "$demo_branch"; then
                printf "\033[1;31mLa branche locale %s est en conflit avec %s/%s\033[0m\n" "$demo_branch" "$j2s_remote" "$demo_branch"
                printf "Veuillez résoudre manuellement la divergence avant de relancer la commande.\n"
                exit_safe 1
            fi
        else
            git checkout -b "$demo_branch" "$j2s_remote/$demo_branch" --quiet
            git pull --ff-only "$j2s_remote" "$demo_branch" --quiet
        fi
        current_branch="$demo_branch"
        printf "Branche %s prête pour la démo.\n" "$demo_branch"
        exit_safe 0
    fi

    if git show-ref --verify --quiet "refs/heads/$demo_branch"; then
        printf "\033[1;31mLa branche %s existe en local mais pas sur %s.\033[0m\n" "$demo_branch" "$j2s_remote"
        printf "Veuillez la publier manuellement ou la supprimer avant de relancer la commande.\n"
        exit_safe 1
    fi

    if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
        if git ls-remote --heads "$j2s_remote" "$base_branch" >/dev/null 2>&1; then
            git fetch "$j2s_remote" "$base_branch:$base_branch" --quiet
        else
            printf "\033[1;31mLa branche de référence %s est introuvable en local ou sur %s.\033[0m\n" "$base_branch" "$j2s_remote"
            exit_safe 1
        fi
    fi

    printf "%sJGit va créer la branche de démo %s%s%s%s qui se basera sur la branche %s%s%s\n" \
    "$(tput setaf 2)" "$(tput setaf 1)" "$demo_branch" "$(tput sgr0)"  "$(tput setaf 2)" "$(tput setaf 1)" "$base_branch" "$(tput sgr0)"
    # Demander confirmation à l'utilisateur
    if ! confirm_action "Souhaitez-vous continuer ?" "y"; then
        echo "Opération annulée."
        exit_safe 1
    fi

    checkout_if_exists "$base_branch"
    git checkout -b "$demo_branch" --quiet
    git commit --allow-empty -m "$prefix_init_commit demo $demo_branch $suffix_init_commit" --quiet
    git push --set-upstream "$j2s_remote" "$demo_branch" --quiet

    current_branch="$demo_branch"
    printf "Branche %s créée depuis %s et publiée avec succès.\n" "$demo_branch" "$base_branch"
    exit_safe 0
}

resolve_demo_source_branch() {
    local source="$1"
    if [[ "$source" == feature/* || "$source" == hotfix/* ]]; then
        echo "$source"
    else
        printf "\033[1;31mLe format attendu est feature/<ticket> ou hotfix/<ticket>.\033[0m\n"
        exit_safe 1
    fi
}

demo_merge_branch() {
    local source_branch
    source_branch=$(resolve_demo_source_branch "$1")
    local demo_branch="$2"

    local source_remote="$j2s_remote/$source_branch"

    if ! is_demo_branch "$demo_branch"; then
        printf "\033[1;31mCette commande doit être exécutée sur une branche demo_* (branche actuelle : %s).\033[0m\n" "$demo_branch"
        exit_safe 1
    fi

    git fetch "$j2s_remote" --quiet

    if ! git ls-remote --exit-code --heads "$j2s_remote" "$source_branch" >/dev/null 2>&1; then
        printf "\033[1;31mLa branche %s n'existe pas sur %s.\033[0m\n" "$source_branch" "$j2s_remote"
        exit_safe 1
    fi

    git checkout "$demo_branch" --quiet

    if ! git pull --ff-only "$j2s_remote" "$demo_branch"; then
        printf "\033[1;31mImpossible de mettre à jour %s depuis %s/%s.\033[0m\n" "$demo_branch" "$j2s_remote" "$demo_branch"
        printf "Veuillez résoudre la divergence puis relancer la commande.\n"
        exit_safe 1
    fi

    if git merge-base --is-ancestor "$source_remote" HEAD; then
        printf "La branche %s est déjà présente dans %s.\n" "$source_branch" "$demo_branch"
        return 0
    fi

    local branch_type="${source_branch%%/*}"
    local marker_message="$prefix_commit DEMO merge $branch_type $source_branch $suffix_init_commit"

    if git log --pretty=format:"%s" | grep -Fq "$marker_message"; then
        printf "Un marqueur pour %s existe déjà.\n" "$source_branch"
    else
        git commit --allow-empty -m "$marker_message" --quiet
    fi

    if ! git rebase "$source_remote"; then
        printf "\033[1;31mRebase interrompu pour %s. Résolvez les conflits puis terminez le rebase manuellement.\033[0m\n" "$source_branch"
        printf "Utilisez 'git rebase --continue' après résolution ou 'git rebase --abort' pour annuler.\n"
        exit_safe 1
    fi

    git push --force-with-lease "$j2s_remote" "$demo_branch"
    printf "Branche %s rebasée avec succès dans %s.\n" "$source_branch" "$demo_branch"
}

demo_merge() {
    local target_branch="$1"
    shift || true
    local sources=("$@")

    if [[ -z "$target_branch" ]]; then
        target_branch=$(git rev-parse --abbrev-ref HEAD)
    else
        if [[ "$target_branch" != ${DemoBranchPrefix}* ]]; then
            target_branch=$(get_demo_branch_name "$target_branch")
        fi
        checkout_if_exists "$target_branch"
    fi

    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "Veuillez préciser au moins une source avec --from." >&2
        exit_safe 1
    fi

    for source in "${sources[@]}"; do
        demo_merge_branch "$source" "$target_branch"
    done
}

demo_list() {
    local demo_branch=$(git rev-parse --abbrev-ref HEAD)

    if ! is_demo_branch "$demo_branch"; then
        printf "\033[1;31mCette commande doit être exécutée depuis une branche demo_*.\033[0m\n"
        exit_safe 1
    fi

    git fetch "$j2s_remote" --quiet
    git pull --ff-only "$j2s_remote" "$demo_branch" >/dev/null 2>&1

    local init_commit
    init_commit=$(get_last_commit_with_pattern "$prefix_init_commit demo $demo_branch")

    if [[ -z "$init_commit" ]]; then
        printf "\033[1;31mImpossible de trouver le commit d'initialisation de la démo.\033[0m\n"
        exit_safe 1
    fi

    local entries=()
    local log_output
    log_output=$(git log --reverse --pretty=format:"%H%-_-_-%s" "$init_commit^..HEAD")

    while IFS=$'-_-_-' read -r commit_hash commit_subject; do
        read -r first_word second_word branch_type branch_name _ <<< "$commit_subject"
        if [[ "$second_word" == "DEMO" && -n "$branch_type" && -n "$branch_name" ]]; then
            entries+=("$branch_type:$branch_name")
        fi
    done <<< "$log_output"

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf "Aucune branche mergée détectée pour %s.\n" "$demo_branch"
        exit_safe 0
    fi

    local color_title=$(tput bold; tput setaf 6)
    local color_feature=$(tput setaf 2)
    local color_marker=$(tput setaf 4)
    local color_reset=$(tput sgr0)

    printf "%sBranches mergées dans %s :%s\n" "$color_title" "$demo_branch" "$color_reset"
    for entry in "${entries[@]}"; do
        local branch_type=${entry%%:*}
        local branch_name=${entry#*:}
        local short_name=${branch_name#${branch_type}/}
        printf "  %s-%s %s (%s%s%s)\n" "$color_feature" "$color_reset" "$short_name" "$color_marker" "$branch_name" "$color_reset"
    done
    printf "\n%sCommandes release suggérées :%s\n" "$color_title" "$color_reset"
    for entry in "${entries[@]}"; do
        local branch_name=${entry#*:}
        printf "jgit release merge --from %s\n" "$branch_name"
    done
    printf "\n"

    exit_safe 0
}

demo_remove() {
    local demo_branch=$(git rev-parse --abbrev-ref HEAD)

    if ! is_demo_branch "$demo_branch"; then
        printf "\033[1;31mCette commande doit être exécutée depuis une branche demo_*.\033[0m\n"
        exit_safe 1
    fi

    git fetch "$j2s_remote" --quiet

    local reference_branch
    reference_branch=$(get_reference_branch "feature")

    local color_title=$(tput bold; tput setaf 6)
    local color_branch=$(tput bold; tput setaf 1)
    local color_text=$(tput setaf 2)
    local color_reset=$(tput sgr0)

    printf "%sSuppression de la branche de démo %s%s%s%s\n" \
        "$color_title" "$color_branch" "$demo_branch" "$color_title" "$color_reset"
    printf "%sElle sera retirée du remote %s%s%s et supprimée en local.%s\n" \
        "$color_text" "$color_branch" "$j2s_remote" "$color_text" "$color_reset"

    if ! confirm_action "Confirmez-vous la suppression ?" "y"; then
        echo "Opération annulée."
        exit_safe 1
    fi

    checkout_if_exists "$reference_branch"

    if git ls-remote --exit-code --heads "$j2s_remote" "$demo_branch" >/dev/null 2>&1; then
        if ! git push "$j2s_remote" --delete "$demo_branch"; then
            printf "\033[1;31mImpossible de supprimer %s sur %s.\033[0m\n" "$demo_branch" "$j2s_remote"
            exit_safe 1
        fi
    else
        printf "%sAucune branche distante %s%s%s trouvée.%s\n" \
            "$color_text" "$color_branch" "$demo_branch" "$color_text" "$color_reset"
    fi

    if git show-ref --verify --quiet "refs/heads/$demo_branch"; then
        git branch -D "$demo_branch"
    fi

    current_branch="$reference_branch"
    printf "%sBranche de démo supprimée avec succès.%s\n" "$color_text" "$color_reset"
    exit_safe 0
}
