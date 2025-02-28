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

    git branch -D "$branch_rebase" --quiet 2>/dev/null
    git branch -D $branch_PR_rebase --quiet 2>/dev/null
    checkout_if_exists "$branch"
    checkout_if_exists "$branch_PR"

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
        echo "$branch exists in remote but not in local, checkout from remote"
        git checkout -b $branch $j2s_remote/$branch --quiet
    fi

    if [[ -z ${branch_PR_in_local} ]]; then
        echo "$branch_PR exists in remote but not in local, checkout from remote"
        git checkout -b $branch_PR $j2s_remote/$branch_PR --quiet
    fi

    git checkout $branch --quiet

    git checkout $branch --quiet
    # Lister les commits sur la branche feature en avance de la branche PR (dans l'ordre du plus ancien au plus récent)
    local commits=($(git rev-list "$branch_PR..$branch" | tail -r))

    git checkout $branch_PR --quiet
    # Récupérer le dernier commit avec le pattern jgit de démarrage de feature
    last_init_commit=$(get_last_commit_with_pattern "$prefix_init_commit $feature_type")
    if [ -z "$last_init_commit" ]; then
        echo "Aucun commit trouvé avec le pattern jgit"
        exit_safe 1
    fi

    # Récupérer la liste des commits sur la branch_PR depuis le dernier commit d'init
    local commits_on_PR=($(list_commits_since "$last_init_commit"))
    local commits_in_advance_on_PR=($(git rev-list "$reference_branch..$branch_PR" | tail -r))

    # On vérifie si la PR n'est pas fermée.
    if is_fast_forward "$branch_PR" "$branch"; then
        echo "La branche $branch est un fast-forward de $branch_PR."
    else
        printf "\033[1;31mLa branche %s n'est PAS un fast-forward de %s.\033[0m\n" "$branch" "$branch_PR"
        echo "Cela peut se produire si vous avez déjà cloturé la PR."
        echo "Ce cas n'est pas encore géré par JGIT. Il va falloir rebase $branch_PR à la mano :) ou la restart"
        exit_safe 1
    fi
    #############################################################################
    # Cette partie permet de gérer le cas où la PR avait déjà été validée et mergée
    # puis réouverte par la suite, en effet dans ce cas là il y a déjà des commits 
    # présents sur la branche PR qui ne doivent pas être oubliés
    ##############################################################################
    
    git checkout $branch_PR --quiet

    # On ne peut pas automatiser un rebase s'il y a un commit de fusion, on refuse l'action
    for commit in "${commits_on_PR[@]}"; do
        if is_merge_commit "$commit"; then
            printf "\033[1;31mLe commit \033[1;32m%s\033[1;31m est un commit de fusion. On ne peut pas rebase automatiquement un commit de fusion.\033[0m\n" "$commit"  
            printf "Il ne faut pas mélanger rebase et merge, la prochaine fois merci de ne faire que des rebases ;). Pensez à toujours squash and merge vos PRs"

            exit_safe 1
        fi
    done

    for commit in "${commits[@]}"; do
        if is_merge_commit "$commit"; then
            printf "\033[1;31mLe commit \033[1;32m%s\033[1;31m est un commit de fusion. On ne peut pas rebase automatiquement un commit de fusion.\033[0m\n" "$commit"  
            printf "Il ne faut pas mélanger rebase et merge, la prochaine fois merci de ne faire que des rebases ;). Pensez à toujours squash and merge vos PRs"

            exit_safe 1
        fi
    done

    if [[ ${#commits_on_PR[@]} -gt 1 ]]; then
        # On est dans le cas d'une PR qui déjà été mergée puis réouverte, on affiche la liste complète pour bien la valider visuellement.
        printf "%sLes commits suivants sont présents sur la branche %s%s%s actuelle mais pas sur la branche %s%s%s. Il seront repris sur la future branche %s%s%s%s\n" \
        "$(tput setaf 2)"  \
        "$(tput setaf 1)" "$branch_PR" "$(tput setaf 2)" \
        "$(tput setaf 1)" "$reference_branch" "$(tput setaf 2)" \
        "$(tput setaf 1)" "$branch_PR" "$(tput setaf 2)" \
        "$(tput sgr0)"
        printf "Liste des commits repris :\n"
        for commit in "${commits_on_PR[@]}"; do
            get_commit_info "$commit"
        done
    fi
   
    ###################################
    # Gestion du rebase en cherrypick
    ###################################

    git checkout $branch --quiet
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

    # rebase de la branche PR par application des commits déjà présents sur l'ancienne branche PR en cherry pick
    echo "Starting cherry picking on $branch_PR_rebase branch"
    checkout_or_create_branch $branch_PR_rebase
    cherry_pick_commits "${commits_on_PR[@]}"

    # rebase de la branche principal par application de tous les commits en cherry pick
    echo "Starting cherry picking on $branch_PR_rebase branch"
    checkout_or_create_branch $branch_rebase
    cherry_pick_commits "${commits[@]}"

    # On vient écraser les branches historiques par les branches que l'on vient de rebase
    git checkout $reference_branch
    rename_branch $branch_PR_rebase $branch_PR
    rename_branch $branch_rebase $branch
    
    # On propose à l'utlisateur de vérifier son arbre GIT avant de pusher en force sur le remote.
    git checkout $branch
    git_history_with_merges "$branch" "$reference_branch"

    read -p "Confirmez-vous que le rebase s'est bien passé, les branches vont être push --force ? (y/n) " user_input
    if [[ "$user_input" != "y" ]]; then
        echo "les branches locales ne sont plus correctes, elles vont etre supprimées en local."
        git checkout $reference_branch --quiet
        git branch -D $branch
        git branch -D $branch_PR
        checkout_if_exists  $branch
        echo "Pensez à re-pull vos branches depuis Github."
        exit_safe 1
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
