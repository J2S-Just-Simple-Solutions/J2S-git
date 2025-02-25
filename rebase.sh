#!/bin/bash
source "$(dirname "$0")/functions.sh"

feature_rebase() {
    local feature_type=$1
    local feature_name=$2
    local BASED_ON=$3
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch
    local branch_rebase="jgit_rebase_"$branch
    local branch_PR_rebase="jgit_rebase_"$branch_PR

    current_date=`date '+%s'`

    git fetch $j2s_remote --quiet

    branch_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch})
    branch_PR_in_remote=$(git ls-remote --heads ${j2s_remote} ${branch_PR})
    branch_in_local=$( git branch --list ${branch} )
    branch_PR_in_local=$( git branch --list ${branch_PR} )

    if [[ -n "$BASED_ON" ]]; then
        reference_branch="$BASED_ON"
    else
        reference_branch=$(get_reference_branch "$feature_type")
    fi

    # Vérifier si la branche référence existe
    if ! git rev-parse --verify "$reference_branch" >/dev/null 2>&1; then
        echo "Erreur : La branche référence '$reference_branch' n'existe pas."
        exit_safe 1
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

    git checkout $branch

    # Récupérer le dernier commit avec le pattern jgit
    last_init_commit=$(get_last_commit_with_pattern)
    if [ -z "$last_init_commit" ]; then
        echo "Aucun commit trouvé avec le pattern jgit"
        exit_safe 1
    fi

    # Lister les commits depuis le dernier commit d'init (dans l'ordre du plus ancien au plus récent)
    local commits=($(list_commits_since "$last_init_commit"))

    printf "%sjgit va reprendre, dans l'ordre, tous les commits ci-dessous qui existe dans la branche locale %s%s%s\n" "$(tput setaf 2)" "$(tput setaf 1)" "$branch" "$(tput sgr0)"
    
    for commit in "${commits[@]}"; do
        get_commit_info "$commit"
    done

    printf "%sEn se basant sur la branche de référence distante %s%s%s\n" \
    "$(tput setaf 2)" "$(tput setaf 1)" "$reference_branch" "$(tput sgr0)"
    
    # Demander confirmation à l'utilisateur
    read -p "Souhaitez-vous continuer ? (y/n) " user_input
    if [[ "$user_input" != "y" ]]; then
        echo "Opération annulée."
        exit_safe 1
    fi

    # On met à jour la branche de référence par rapport au remote pour être bien à jour
    echo "Checkout and reset $reference_branch branch"
    git checkout $reference_branch --quiet
    git pull $j2s_remote $reference_branch --quiet

    # rebase de la branche PR par application du commit d'init en cherry pick
    checkout_or_create_branch $branch_PR_rebase
    cherry_pick "$last_init_commit"

    # rebase de la branche principal par application de tous les commits en cherry pick
    checkout_or_create_branch $branch_rebase
    cherry_pick_commits "${commits[@]:1}" # On exclut le commit d'init qui a déjà été cherry-pick au dessus.  

    # On vient écraser les branches historiques par les branches que l'on vient de rebase
    git checkout $reference_branch
    rename_branch $branch_PR_rebase $branch_PR
    rename_branch $branch_rebase $branch
    
    # On propose à l'utlisateur de vérifier son arbre GIT avant de pusher en force sur le remote.
    git checkout $branch
    git_history_with_merges

    read -p "Confirmez-vous que le rebase s'est bien passé, les branches vont être push --force ? (y/n) " user_input
    if [[ "$user_input" != "y" ]]; then
        echo "Opération annulée."
        exit_safe 0
    fi

    # on push force les nouvelles branches fraichement rebasée.
    git checkout $branch_PR
    git push --force --set-upstream origin "$branch_PR"

    git checkout $branch
    git push --force --set-upstream origin "$branch"

    git checkout $branch
    clean_branches

    printf "%sRebase terminé avec succès%s\n" "$(tput setaf 2)" "$(tput sgr0)"
}
