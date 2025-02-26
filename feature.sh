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

        printf "%sJGit va créer la branche %s%s%s%s et sa PR associée qui se basera sur la branche %s%s%s\n" \
        "$(tput setaf 2)" "$(tput setaf 1)" "$branch" "$(tput sgr0)"  "$(tput setaf 2)" "$(tput setaf 1)" "$reference_branch" "$(tput sgr0)"
        # Demander confirmation à l'utilisateur
        read -p "Souhaitez-vous continuer ? (y/n) " user_input
        if [[ "$user_input" != "y" ]]; then
            echo "Opération annulée."
            exit_safe 1
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


feature_restart() {
    local feature_type=$1
    local feature_name=$2
    local BASED_ON=$3
    local branch=$1/$feature_name
    local branch_PR=$prefix_PR$branch

    # Vérifier si la branche référence existe
    if ! git rev-parse --verify "$branch_PR" >/dev/null 2>&1 && ! git ls-remote --heads origin "$branch_PR" >/dev/null 2>&1; then
        echo "Erreur : La branche de PR '$branch_PR' n'existe pas."
        exit_safe 1
    fi

    # On remet les branches à jour en local.
    update_or_checkout_branch $branch_PR
    update_or_checkout_branch $branch

    branches_have_same_code "$branch" "$branch_PR"

    # Vérifier le résultat et afficher un message personnalisé
    if [[ $? -ne 0 ]]; then
        echo "🚨 ATTENTION : Le code de '$branch' et '$branch_PR' est différent !"
        printf "\033[1;31mLe restart ne peut se faire que sur deux branches identiques d'un point de vue code\033[0m\n"

        exit_safe 0
    else
        echo "✅ Les deux branches contiennent exactement le même code."
    fi


    #####################################################
    # On supprime la branche de travail pour la recréer
    #####################################################
    git checkout $branch_PR --quiet
    
    # Suppression locale de la branche, avec un arrêt en cas d'échec
    git branch -d "$branch"
    if [ $? -ne 0 ]; then
        echo "Erreur : La branche '$branch' n'a pas pu être supprimée en local. Elle n'est peut-être pas fusionnée."
        exit 1
    fi
  
    # Suppression de la branche sur le remote
    git push origin --delete "$branch"
    if [ $? -ne 0 ]; then
        echo "Erreur : La branche '$branch' n'a pas pu être supprimée sur le remote."
        exit 1
    fi

    echo "Create working branch $branch"
    git checkout -b $branch --quiet
    git commit --allow-empty -m "$prefix_init_commit $branch $suffix_init_commit" --quiet
    git push --set-upstream $j2s_remote $branch --quiet
    git branch -D $branch_PR --quiet
    echo "Create pull request"
    gh pr create --title $feature_name --body "https://justsimplesolutions.atlassian.net/browse/"$feature_name --base=$branch_PR --head=$branch --label "NFR"

}
