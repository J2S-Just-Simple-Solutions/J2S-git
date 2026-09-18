#!/bin/bash
source "$(dirname "$0")/functions.sh"

feature_start() {
    local feature_type=$1
    local feature_name=$2
    local BASED_ON=$3
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch

    branch_in_local=$( git branch --list ${branch} )
    branch_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch})

    jgit_fetch_once || exit_safe 1

    if [[ -n ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Exists in remote and local"
        echo "Use local branch"
        switch_branch "$branch"
    elif [[ -z ${branch_in_local} ]] && [[ -n ${branch_in_remote} ]]; then
        echo "Exists in remote but not in local"
        echo "Use remote branch"
        switch_branch "$branch"
    elif [[ -n ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
        echo "Exists in local and not in remote"
        echo "Is this feature already merged ?"
    elif [[ -z ${branch_in_local} ]] && [[ -z ${branch_in_remote} ]]; then
        local base_provenance="reference"
        if [[ -n "$BASED_ON" ]]; then
            reference_branch="$BASED_ON"
            base_provenance="option"
        elif ! reference_branch=$(get_reference_branch "$feature_type"); then
            exit_safe 1
        fi

        # Une saisie et une valeur par défaut se contrôlent au même endroit :
        # c'est ce qui garantit qu'elles échouent de la même façon.
        if ! ensure_base_branch "$reference_branch" "$base_provenance" "$feature_type" \
             "jgit $feature_type start $feature_name"; then
            exit_safe 1
        fi

        printf "%sJGit va créer la branche %s%s%s%s et sa PR associée qui se basera sur la branche %s%s%s\n" \
        "$(tput setaf 2)" "$(tput setaf 1)" "$branch" "$(tput sgr0)"  "$(tput setaf 2)" "$(tput setaf 1)" "$reference_branch" "$(tput sgr0)"
        # Demander confirmation à l'utilisateur
        if ! confirm_action "Souhaitez-vous continuer ?" "y"; then
            echo "Opération annulée."
            exit_safe 1
        fi

        echo "Checkout and reset $reference_branch branch"
        switch_branch "$reference_branch"
        echo "Create pull request branch $branch_PR branch"
        switch_branch "$branch_PR" create
        commit_init_with_based_on "$prefix_init_commit $branch $suffix_init_commit" "$branch_PR" "$reference_branch" --quiet
        git push $j2s_remote $branch_PR --quiet
        echo "Create working branch $branch branch"
        switch_branch "$branch" create
        commit_init_with_based_on "$prefix_commit commit for automatic PR creation - this commit will be deleted by squash and merge - START $branch $suffix_init_commit" "$branch" "$reference_branch" --quiet
        git push --set-upstream $j2s_remote $branch --quiet
        current_branch="$branch"
        git branch -D $branch_PR --quiet
        if [[ $JGIT_NO_OPEN == true ]]; then
            echo "Skipping pull request creation (--no-open)."
        else
            echo "Create pull request"
            if ! gh pr create --title "$feature_name" --body "https://justsimplesolutions.atlassian.net/browse/$feature_name" --base=$branch_PR --head=$branch --label "NFR"; then
                report_pr_creation_failure "$branch" "$branch_PR"
                exit_safe 1
            fi
        fi
    else
        echo "On est dans la Matrix"
    fi

    exit_safe 0
}

feature_restart() {
    local feature_type=$1
    local feature_name=$2
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch

    # Vérifier si la branche référence existe
    if ! git rev-parse --verify "$branch_PR" >/dev/null 2>&1 \
       && ! git ls-remote --exit-code --heads "$j2s_remote" "$branch_PR" >/dev/null 2>&1; then
        echo "Erreur : La branche de PR '$branch_PR' n'existe pas."
        exit_safe 1
    fi

    # On remet les branches à jour en local. La branche de PR existe forcément
    # (garde-fou ci-dessus) ; la branche de travail peut avoir été supprimée.
    switch_branch "$branch_PR"
    switch_branch "$branch" create

    branches_have_same_code "$branch" "$branch_PR"

    # Vérifier le résultat et afficher un message personnalisé
    if [[ $? -ne 0 ]]; then
        echo "🚨 ATTENTION : Le code de '$branch' et '$branch_PR' est différent !"
        printf "\033[1;31mLe restart ne peut se faire que sur deux branches identiques d'un point de vue code\033[0m\n"

        exit_safe 1
    else
        echo "✅ Les deux branches contiennent exactement le même code."
    fi


    #####################################################
    # On supprime la branche de travail pour la recréer
    #####################################################
    switch_branch "$branch_PR"

    # Suppression locale de la branche - on ignore l'erreur si elle n'existe déjà pas
    git branch -d "$branch" 2>/dev/null
  
    # Suppression de la branche sur le remote - on ignore l'erreur si elle n'existe déjà pas
    git push "$j2s_remote" --delete "$branch" 2>/dev/null

    # Un restart ne choisit pas de base : il reprend celle que la branche de PR
    # porte déjà. Une branche d'avant ce mécanisme n'en a pas, et on ne lui en
    # invente pas une — elle reste une ancienne branche, ce que dit check_rebase.
    local recorded_base
    recorded_base=$(read_based_on "$branch_PR" "$branch_PR") || recorded_base=""

    echo "Create working branch $branch"
    switch_branch "$branch" create
    commit_init_with_based_on "$prefix_commit commit for automatic PR creation - this commit will be deleted by squash and merge - RESTART $branch $suffix_init_commit" "$branch" "$recorded_base" --quiet
    git push --set-upstream $j2s_remote $branch --quiet
    current_branch="$branch"
    git branch -D $branch_PR --quiet
    if [[ $JGIT_NO_OPEN == true ]]; then
        echo "Skipping pull request creation (--no-open)."
    else
        echo "Create pull request"
        if ! gh pr create --title "$feature_name - RESTART" --body "https://justsimplesolutions.atlassian.net/browse/$feature_name" --base=$branch_PR --head=$branch --label "NFR"; then
            report_pr_creation_failure "$branch" "$branch_PR"
            exit_safe 1
        fi
    fi
}
