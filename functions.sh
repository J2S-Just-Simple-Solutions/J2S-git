#!/bin/bash

# Stash all modifications before running any modification
verify_stash() {
    if [[ $(git status --porcelain) ]]; then
        echo "You have uncommited modifications."
        read -p "Do you want to stash and unstash changes at the end of process ? [y/n] " yn
        echo
        if [[ ! $yn =~ ^[Yy]$ ]]; then
            exit_safe 0
        fi
        git stash save "[jGIT]"
        stash=true;
    fi
}

# fonction à appeler systématiquement permet de remettre les données stashée au départ en cas d'arrêt du script.
exit_safe() {
    if $stash; then
        git stash pop
    fi

    if [[ $1 == 0 ]]; then
        echo "/!\ Script finished in error! Be careful about your branch management on local."

        exit $1
    fi

    exit $1
}

# Renvoie la branche de référence et vérifie son existence.
# La paramètre --based-on sera pris en priorité.
# Les paramètre du fichier .jgit/conf_local.sh seront pris en 2nd
# Sinon le script prendra la première branche qui existe parmis les fallback_branches
#
#Si la branche de référence n'existe pas une erreur est lancée.
get_reference_branch() {
    local feature_type=$1
    local fallback_branches=("develop2" "master2" "develop" "master" "main")

    if [ -z "$feature_type" ]; then
        echo "Erreur: Aucun feature_type fourni."
        exit_safe 0
    fi

    # Vérifier la branche en fonction du type de feature
    if [ "$feature_type" == "hotfix" ] && git rev-parse --verify "$branch_prod" >/dev/null 2>&1; then
        echo "$branch_prod"
        return 0  # Succès
    elif [ "$feature_type" == "feature" ] && git rev-parse --verify "$branch_preprod" >/dev/null 2>&1; then
        echo "$branch_preprod"
        return 0  # Succès
    fi

    # Vérifier la première branche existante parmi la liste de fallback
    for branch in "${fallback_branches[@]}"; do
        if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        echo "$branch"
        return 0  # Succès
        fi
    done

    echo "Erreur: Aucune branche valide trouvée."
    exit_safe 1
}

# Fonction pour récupérer le dernier commit contenant le pattern de commit d'init jgit.
get_last_commit_with_pattern() {
  git log --grep="\[jgit\]" -n 1 --pretty=format:"%H"
}

# Fonction pour lister tous les commits depuis celui trouvé (incluant ce commit)
list_commits_since() {
  local start_commit=$1
  # Retourner la liste des commits depuis start_commit (y compris lui-même)
  git log --reverse --pretty=format:"%H" "$start_commit^..HEAD"
}

# Fonction pour effectuer un cherry-pick sur chaque commit du tableau
cherry_pick_commits() {
  local commits=("$@")

  for commit in "${commits[@]}"; do
    cherry_pick "$commit"
  done
}

# Fonction pour effectuer un cherry-pick sur le hash passé en argument si celui n'existe pas déjà.
cherry_pick() {
    local commit=$1
    
    # Vérifier si le commit est déjà dans l'historique de la branche courante
    if git merge-base --is-ancestor "$commit" HEAD; then
      echo "Commit $commit déjà appliqué, passage au suivant..."
      continue
    fi

    echo "Cherry-picking commit: $commit"
    git cherry-pick "$commit" --allow-empty
    
    # Vérifier si le cherry-pick a échoué (en cas de conflit)
    if [ $? -ne 0 ]; then
      echo ""
      printf "%sErreur lors du cherry-pick du commit %s. Conflit détecté.%s\n" \
        "$(tput setaf 1)" "$commit" "$(tput sgr0)"
      printf "%sMerci de ne rien faire ici tant que le conflit n'est pas résolu et commité%s\n" \
        "$(tput setaf 1)" "$(tput sgr0)"
    
        # Demander confirmation à l'utilisateur
        read -p "Avez vous résolu et commité la résolution de conflit ? (y/n) " user_input
        if [[ "$user_input" != "y" ]]; then
            echo "Opération annulée."
            git cherry-pick --abort
            exit_safe 0
        fi
    fi
}

# Permet d'afficher le git log bien présenté avec les couleurs et l'arbres des commits
git_history_with_merges() {
  local branch="${1:-HEAD}"  # Si aucun argument n'est fourni, utilise HEAD (branche actuelle)

  echo "Historique de la branche '$branch' avec les merges :"
  git log --oneline --graph --decorate --all --abbrev-commit --pretty=format:'%C(yellow)%h%C(reset) - %C(cyan)%d%C(reset) %s %C(blue)(%cr) %C(reset)%C(green)<%an>%C(reset)' "$branch"
}

# Permt d'afficher un commit sur une ligne avec son hash et son nom
get_commit_info() {
  local commit_hash=$1
  if [ -z "$commit_hash" ]; then
    echo "Erreur: Aucun hash de commit fourni."
    return 1
  fi

  # Récupérer le hash et le message du commit
  local commit_info
  commit_info=$(git log -n 1 --pretty=format:"%H %s" "$commit_hash" 2>/dev/null)

  if [ -z "$commit_info" ]; then
    echo "Erreur: Commit non trouvé."
    return 1
  fi

  echo "$commit_info"
}

# Permet de renommer une branche. La branche destination sera supprimée si elle existe déjà en locale.
# Cette fonction ne travaille qu'en local et ne touche pas au remote.
rename_branch() {
  local source_branch="$1"
  local destination_branch="$2"

  # Vérifier si les deux branches sont fournies
  if [[ -z "$source_branch" || -z "$destination_branch" ]]; then
    echo "Erreur : Veuillez fournir une branche source et une branche destination."
    return 1
  fi

  # Vérifier si la branche source existe
  if ! git rev-parse --verify "$source_branch" >/dev/null 2>&1; then
    echo "Erreur : La branche source '$source_branch' n'existe pas."
    return 1
  fi

  # Supprimer la branche destination si elle existe
  if git rev-parse --verify "$destination_branch" >/dev/null 2>&1; then
    echo "Suppression de la branche '$destination_branch'..."
    git branch -D "$destination_branch"
  fi

  # Renommer la branche source en destination
  echo "Renommage de '$source_branch' en '$destination_branch'..."
  git branch -m "$source_branch" "$destination_branch"
}

# Si la branche n'existe pas elle est créé si elle existe on checkout dessus.
checkout_or_create_branch() {
  local branch="$1"

  # Vérifier si la branche existe
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "Bascule vers '$branch' (Changement vers cette branche)"
    git checkout "$branch"
  else
    echo "Bascule vers '$branch' (Création depuis la branche courante)"
    git checkout -b "$branch"
  fi
}

# Script de nettoyage qui va nettoyer toutes les branches utiles à jgit mais pas au développeur.
clean_branches() {
  # Récupérer toutes les branches locales correspondant aux préfixes
  local branches_to_delete
  branches_to_delete=$(git branch | grep -E "^\s*(jgit_rebase_|__PR__)")

  # Vérifier si des branches correspondent
  if [[ -z "$branches_to_delete" ]]; then
    echo "Aucune branche locale à nettoyer"
    return 0
  fi

  # Supprimer chaque branche trouvée
  echo "Suppression des branches locales suivantes :"
  echo "$branches_to_delete"
  
  while read -r branch; do
    branch=$(echo "$branch" | xargs)  # Supprimer les espaces éventuels
    git branch -D "$branch"
  done <<< "$branches_to_delete"

  echo "Suppression terminée."
}
