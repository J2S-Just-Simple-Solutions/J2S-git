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

    # Récupérer le dernier commit avec le pattern jgit de démarrage de feature
    last_init_commit=$(get_last_commit_with_pattern "$prefix_init_commit $feature_type")
    if [ -z "$last_init_commit" ]; then
        echo "Aucun commit trouvé avec le pattern jgit"
        exit_safe 1
    fi

    # Lister les commits depuis le dernier commit d'init (dans l'ordre du plus ancien au plus récent)
    local commits=($(list_commits_since "$last_init_commit"))

    #############################################################################
    # Cette partie permet de gérer le cas où la PR avait déjà été validée et mergée
    # puis réouverte par la suite, en effet dans ce cas là il y a déjà des commits 
    # présents sur la branche PR qui ne doivent pas être oubliés
    ##############################################################################
    
    branches_have_same_code "$branch" "$branch_PR"

    # Vérifier le résultat et afficher un message personnalisé
    if [[ $? -eq 0 ]]; then
        printf "\033[1;31mLe code sur la branche \033[1;32m%s\033[1;31m est parfaitement identique à celui sur la branche \033[1;32m%s\033[1;31m .\033[0m\n" "$branch" "$branch_PR" 
        printf "Cette PRs a-t-elle déjà été cloturée ? Faut-il faire un restart ?\n"
        printf "Ce rebase est bloqué pour éviter de fusiller des branches de PR après avoir mergée la PR.\n"
        printf "Si vous êtes sur une feature toute neuve, poussez votre premier commit avant de rebase ou supprimez puis recréez.\n"

        exit_safe 1
    fi
    
    git checkout $branch_PR --quiet
    
    # Récupérer la liste des commits en avance sur branch_PR
    local commits_in_advance_on_PR=($(git rev-list "$reference_branch..$branch_PR" | tail -r))

    # Parcourir les commits de la branche feature et vérifier qu'ils ne sont pas pris en doublon dans la branche PR.
    for item in "${commits[@]}"; do
        if [[ " ${commits_in_advance_on_PR[@]} " =~ " $item " ]]; then
            common_elements+=("$item")
        fi
    done

    # On ne peut pas automatiser un rebase s'il y a un commit de fusion, on refuse l'action
    for commit in "${commits_in_advance_on_PR[@]}"; do
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

    if [[ ${#commits_in_advance_on_PR[@]} -gt 0 ]]; then
        # On est dans le cas d'une PR qui déjà été mergée puis réouverte, on affiche la liste complète pour bien la valider visuellement.
        printf "%sLes commits suivants sont présents sur la branche %s%s%s actuelle mais pas sur la branche %s%s%s. Il seront repris sur la future branche %s%s%s%s\n" \
        "$(tput setaf 2)"  \
        "$(tput setaf 1)" "$branch_PR" "$(tput setaf 2)" \
        "$(tput setaf 1)" "$reference_branch" "$(tput setaf 2)" \
        "$(tput setaf 1)" "$branch_PR" "$(tput setaf 2)" \
        "$(tput sgr0)"
        printf "Liste des commits repris :\n"
        for commit in "${commits_in_advance_on_PR[@]}"; do
            get_commit_info "$commit"
        done
    fi

    # Afficher une erreur si des éléments communs sont trouvés
    if [[ ${#common_elements[@]} -gt 0 ]]; then
        printf "\033[1;31mErreur : Les commits suivants existent sur %s et %s, ce n'est pas normal :\033[0m\n" $branch $branch_PR
        printf "Liste des commits communs :\n"
        for commit in "${common_elements[@]}"; do
            get_commit_info "$commit"
        done

        # On doit gérer un cas un peu tordu car le commit d'init n'étant plus créé au même moment depuis la version 1.15, cette vérification peut etre un faux positif
        # Le code ci dessous devra etre décommenté une fois qu'il n'y aura plus de vieille feature.
        # printf "\033[1;31mIl n'est pas possible de rebase une feature dont la PR a été cloturée. Peut-être faut-il la restart avant ?\033[0m\n"
        # exit_safe 1

        # DEBUT DE Partie à supprimer une fois qu'il n'y aura plus de vieille feature.
        printf "\nCe cas peut se poser pour les features créées avant la v1.15 de jgit.\n"
        printf "\nDans ce cas : vous devez voir uniquement le commit d'init dans la \"Liste des commits communs\" et dans la \"Liste des commits repris\".\n"
        printf "Attention en continuant ce process tous les commits existants dans la \"Liste des commits repris\"  seront perdus !!!!!!\n"

        # Demander confirmation à l'utilisateur
        read -p "Voulez-vous continuer ? (y/n) " user_input
        if [[ "$user_input" != "y" ]]; then
            printf "\033[1;31mIl n'est pas possible de rebase une feature dont la PR a été cloturée. Peut-être faut-il la restart avant ?\033[0m\n"
            exit_safe 1
        fi

        commits_in_advance_on_PR=()
        # FIN DE Partie à supprimer une fois qu'il n'y aura plus de vieille feature.
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
    cherry_pick_commits "${commits_in_advance_on_PR[@]}"

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
