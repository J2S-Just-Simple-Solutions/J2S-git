#!/bin/bash

###############################################
###############################################
#            Fonctions Bash
###############################################
###############################################

# Valeurs par défaut pour les options globales lorsque le script est
# exécuté directement (les variables sont normalement définies dans jgit.sh).
if [[ -z "${JGIT_NO_INTERACTION+x}" ]]; then
  JGIT_NO_INTERACTION=false
fi

if [[ -z "${JGIT_NO_OPEN+x}" ]]; then
  JGIT_NO_OPEN=false
fi

if [[ -z "${JGIT_BASED_ON_OVERRIDE+x}" ]]; then
  JGIT_BASED_ON_OVERRIDE=""
fi

if [[ -z "${JGIT_SQUASH+x}" ]]; then
  JGIT_SQUASH=false
fi

if [[ -z "${JGIT_SQUASH_THRESHOLD+x}" ]]; then
  JGIT_SQUASH_THRESHOLD=8
fi

declare -a JGIT_FROM_SOURCES

###############################################
#            Helpers génériques
###############################################

confirm_action() {
  local prompt="$1"
  local default_response=${2:-"y"}

  # En mode non interactif on applique la réponse par défaut de la question,
  # qui n'est pas forcément "oui".
  if [[ $JGIT_NO_INTERACTION == true ]]; then
    echo "[no-interaction] $prompt -> $default_response"
    if [[ "$default_response" == "y" ]]; then
      return 0
    fi
    return 1
  fi

  # La réponse par défaut (celle appliquée si l'utilisateur valide sans rien saisir)
  # est signalée par la majuscule dans le suffixe.
  local suffix="(y/n)"
  if [[ "$default_response" == "n" ]]; then
    suffix="(y/N)"
  fi

  local user_input
  read -p "$prompt $suffix " user_input
  echo

  if [[ -z "$user_input" ]]; then
    user_input="$default_response"
  fi

  if [[ "$user_input" == "y" ]]; then
    return 0
  fi

  return 1
}

# Résout un nom de branche/réf en une référence git exploitable.
resolve_git_ref() {
  local ref="$1"

  if [[ -z "$ref" ]]; then
    return 1
  fi

  if git show-ref --verify --quiet "refs/heads/$ref"; then
    echo "$ref"
    return 0
  fi

  if git show-ref --verify --quiet "refs/remotes/$ref"; then
    echo "$ref"
    return 0
  fi

  if git show-ref --verify --quiet "$ref"; then
    echo "$ref"
    return 0
  fi

  return 1
}

# fonction à appeler systématiquement permet de remettre les données stashée au départ en cas d'arrêt du script.
exit_safe() {
    local exit_code=${1:-0}

    if [[ $exit_code -ne 0 ]]; then
        echo "checkout on $current_branch"
        checkout_if_exists "$current_branch"
    fi

    if [[ $stash == true ]]; then
        git stash pop
    fi

    if [[ $exit_code -ne 0 ]]; then
        echo "/!\ Script finished in error! Be careful about your branch management on local."
    fi

    exit $exit_code
}

###############################################
###############################################
#            Manipulations GIT
###############################################
###############################################

# Stash all modifications before running any modification
verify_stash() {
    if [[ $(git status --porcelain) ]]; then
        echo "You have uncommited modifications."
        if ! confirm_action "Do you want to stash and unstash changes at the end of process ?" "y"; then
            exit_safe 1
        fi
        git stash save "[jGIT]"
        stash=true
    fi
}

# Renvoie la branche de référence et vérifie son existence.
# La paramètre --based-on sera pris en priorité.
# Les paramètre du fichier .jgit/conf_local.sh seront pris en 2nd
# Sinon le script prendra la première branche qui existe parmis les fallback_branches
#
# Si la branche de référence n'existe pas une erreur est lancée.
get_reference_branch() {
    local feature_type=${1:-feature}
    local fallback_branches=("develop" "master" "main")

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
  local pattern="$1"

  # Échapper les caractères spéciaux comme [ ] et ( )
  local escaped_pattern
  escaped_pattern=$(echo "$pattern" | sed 's/\[/\\[/g; s/\]/\\]/g; s/(/\\(/g; s/)/\\)/g')

  # Chercher le commit correspondant avec le pattern modifié
  git log --grep="^$escaped_pattern\?" -n 1 --pretty=format:"%H"
}

# Fonction pour lister tous les commits depuis celui trouvé (incluant ce commit)
list_commits_since() {
  local start_commit=$1
  # Retourner la liste des commits depuis start_commit (y compris lui-même)
  git log --reverse --pretty=format:"%H" "$start_commit^..HEAD"
}

###############################################
#            Squash des commits
###############################################

# Renvoie l'index (base 0) du dernier commit d'init jgit (commit vide) trouvé dans la
# liste de commits fournie (ordonnée du plus ancien au plus récent).
# Renvoie -1 si aucun commit d'init n'est présent dans la liste.
find_last_init_commit_index() {
  local commits=("$@")
  local index=-1
  local i

  for i in "${!commits[@]}"; do
    local subject
    subject=$(git log -n 1 --pretty=format:"%s" "${commits[$i]}" 2>/dev/null)
    if [[ "$subject" == *"$suffix_init_commit"* ]]; then
      index=$i
    fi
  done

  echo "$index"
}

# Squash en un seul commit tous les commits de la branche courante postérieurs à
# $base_commit. Le message est demandé à l'utilisateur, le message de $first_commit
# (le premier commit squashé) servant de valeur par défaut.
squash_commits_after() {
  local base_commit="$1"
  local first_commit="$2"

  if [[ -z "$base_commit" || -z "$first_commit" ]]; then
    printf "\033[1;31mErreur : squash impossible, commit de base ou premier commit manquant.\033[0m\n" >&2
    return 1
  fi

  local default_message
  default_message=$(git log -n 1 --pretty=format:"%s" "$first_commit" 2>/dev/null)

  local message=""
  if [[ $JGIT_NO_INTERACTION == true ]]; then
    echo "[no-interaction] Message du commit squashé : $default_message"
  else
    printf "%sMessage du commit squashé (Entrée pour conserver « %s ») :%s\n" \
      "$(tput setaf 2)" "$default_message" "$(tput sgr0)"
    read -r -p "> " message
  fi

  if [[ -z "$message" ]]; then
    message="$default_message"
  fi

  # reset --soft : on conserve l'intégralité du code, seul l'historique est réécrit.
  if ! git reset --soft "$base_commit" --quiet; then
    printf "\033[1;31mErreur : impossible de repositionner la branche sur %s.\033[0m\n" "$base_commit" >&2
    return 1
  fi

  if ! git commit --allow-empty -m "$message" --quiet; then
    printf "\033[1;31mErreur : le squash des commits a échoué.\033[0m\n" >&2
    return 1
  fi

  printf "%sCommits squashés dans un unique commit : %s%s\n" "$(tput setaf 2)" "$message" "$(tput sgr0)"
  return 0
}

# Fonction pour effectuer un cherry-pick sur chaque commit du tableau
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
        if ! confirm_action "Avez vous résolu et commité la résolution de conflit ?" "y"; then
            echo "Opération annulée."
            git cherry-pick --abort
            exit_safe 1
        fi
    fi
}

# Permet d'afficher le git log bien présenté depuis le dernier noeud en commun avec la $reference_branch et avec les couleurs et l'arbres des commits
git_history_with_merges() {
  local feature_branch="${1:-HEAD}"     # Branche à afficher (par défaut HEAD)
  local reference_branch="${2}"         # Branche de référence (optionnelle)

  printf "\033[1;31mHistorique A VERIFIER de la branche '%s'%s :\033[0m\n" "$feature_branch" "$( [[ -n "$reference_branch" ]] && printf " depuis '%s' (A lire de bas en haut)" "$reference_branch" )"

  if [[ -n "$reference_branch" ]]; then
    git log --oneline --graph --decorate --abbrev-commit --boundary \
      --pretty=format:'%C(yellow)%h%C(reset) - %C(cyan)%d%C(reset) %s %C(blue)(%cr) %C(reset)%C(green)<%an>%C(reset)' \
      "$feature_branch" "^$reference_branch"
  else
    git log --oneline --graph --decorate --abbrev-commit \
      --pretty=format:'%C(yellow)%h%C(reset) - %C(cyan)%d%C(reset) %s %C(blue)(%cr) %C(reset)%C(green)<%an>%C(reset)' \
      "$feature_branch"
  fi

  printf "\nVous pouvez afficher un arbre plus détaillé, si besoin, en copiant collant la commande ci-dessous dans un autre terminal\n"
  printf "git log --oneline --graph --decorate --all --abbrev-commit --pretty=format:'%%C(yellow)%%h%%C(reset) - %%C(cyan)%%d%%C(reset) %%s %%C(blue)(%%cr) %%C(reset)%%C(green)<%%an>%%C(reset)' %s\n\n\n" "$feature_branch"
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

  if [[ -z "$branch" ]]; then
    printf "\033[1;31mErreur : Aucun nom de branche fourni.\033[0m\n" >&2
    return 1
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # La branche existe en local
      git checkout "$branch" --quiet
      git pull --ff-only "$j2s_remote" "$branch" --quiet

  elif git ls-remote --exit-code --heads "$j2s_remote" "$branch" > /dev/null; then
      # La branche existe sur le remote mais pas en local
      git fetch "$j2s_remote" "$branch:$branch" --quiet
      git checkout "$branch" --quiet
  else
    echo "Bascule vers '$branch' (Création depuis la branche courante)"
    git checkout -b "$branch"
  fi
}

# Si la branche existe on checkout dessus et on la met à jour, si elle n'existe pas on lance une erreur.
checkout_if_exists() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    printf "\033[1;31mErreur : Aucun nom de branche fourni.\033[0m\n" >&2
    return 1
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
      # La branche existe en local
      git checkout "$branch" --quiet
      git pull --ff-only "$j2s_remote" "$branch" --quiet

  elif git ls-remote --exit-code --heads "$j2s_remote" "$branch" > /dev/null; then
      # La branche existe sur le remote mais pas en local
      git fetch "$j2s_remote" "$branch:$branch" --quiet
      git checkout "$branch" --quiet
  else
    echo "La branche n'existe pas"
    exit_safe 1
  fi
}

# Script de nettoyage qui va nettoyer toutes les branches utiles à jgit mais pas au développeur.
clean_branches() {
  # Récupérer toutes les branches locales correspondant aux préfixes
  local branches_to_delete
  branches_to_delete=$(git branch | grep -E "^\s*(jgit_rebase_|__PR__|jgit_verify_rebase)")

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

util_verify_rebase() {
  local target_branch="$1"
  shift || true
  local sources=("$@")

  if [[ -z "$target_branch" ]]; then
    echo "Erreur : veuillez préciser la branche cible avec --into." >&2
    echo "false"
    return 1
  fi

  if [[ ${#sources[@]} -ne 1 ]]; then
    echo "Erreur : veuillez fournir exactement une branche source via --from." >&2
    echo "false"
    return 1
  fi

  if [[ -n $(git status --porcelain) ]]; then
    echo "Erreur : l'espace de travail contient des modifications. Nettoyez-le avant de lancer la vérification." >&2
    echo "false"
    return 1
  fi

  local source_branch="${sources[0]}"
  local source_ref
  local target_ref

  source_ref=$(resolve_git_ref "$source_branch") || {
    echo "Erreur : la branche source '$source_branch' est introuvable." >&2
    echo "false"
    return 1
  }

  target_ref=$(resolve_git_ref "$target_branch") || {
    echo "Erreur : la branche cible '$target_branch' est introuvable." >&2
    echo "false"
    return 1
  }

  if [[ "$source_ref" == "$target_ref" ]]; then
    echo "true"
    return 0
  fi

  local start_branch
  start_branch=$(git rev-parse --abbrev-ref HEAD)

  local sanitized_source sanitized_target
  sanitized_source=$(echo "$source_branch" | sed 's/[^A-Za-z0-9._-]/_/g')
  sanitized_target=$(echo "$target_branch" | sed 's/[^A-Za-z0-9._-]/_/g')
  local temp_branch="jgit_verify_rebase_${sanitized_source}_onto_${sanitized_target}_$$"

  if git show-ref --verify --quiet "refs/heads/$temp_branch"; then
    git branch -D "$temp_branch" >/dev/null 2>&1 || {
      echo "Erreur : impossible de nettoyer la branche temporaire existante '$temp_branch'." >&2
      echo "false"
      return 1
    }
  fi

  if ! git branch "$temp_branch" "$source_ref" >/dev/null 2>&1; then
    echo "Erreur : impossible de créer la branche temporaire '$temp_branch'." >&2
    echo "false"
    return 1
  fi

  if ! git checkout --quiet "$temp_branch"; then
    git branch -D "$temp_branch" >/dev/null 2>&1 || true
    echo "Erreur : impossible de basculer sur la branche temporaire." >&2
    echo "false"
    return 1
  fi

  local rebase_ok=true
  if ! git rebase --quiet "$target_ref"; then
    rebase_ok=false
    git rebase --abort >/dev/null 2>&1 || true
  fi

  git checkout --quiet "$start_branch" >/dev/null 2>&1 || true
  git branch -D "$temp_branch" >/dev/null 2>&1 || true

  if [[ "$rebase_ok" == true ]]; then
    echo "true"
    return 0
  else
    echo "false"
    return 1
  fi
}

branches_have_same_code() {
  local branch1="$1"
  local branch2="$2"
  local tree1 tree2

  # Vérifier que les branches existent
  if ! git rev-parse --verify "$branch1" >/dev/null 2>&1 || ! git rev-parse --verify "$branch2" >/dev/null 2>&1; then
    echo "❌ L'une des branches n'existe pas."
    return 1
  fi

  # Récupérer les arbres des branches
  tree1=$(git rev-parse "$branch1^{tree}")
  tree2=$(git rev-parse "$branch2^{tree}")

  # Comparer les arbres
  if [[ "$tree1" == "$tree2" ]]; then
    return 0
  else
    return 1
  fi
}

 is_merge_commit() {
    local commit_hash="$1"
    local parent_count=$(git rev-list --parents -n 1 "$commit_hash" | awk '{print NF-1}')
    
    if [[ "$parent_count" -gt 1 ]]; then
        return 0  # C'est un commit de fusion
    else
        return 1  # Ce n'est pas un commit de fusion
    fi
}

is_fast_forward() {
    local base_branch="$1"
    local target_branch="$2"

    # Vérifier que les branches existent
    if ! git rev-parse --verify "$base_branch" >/dev/null 2>&1 || ! git rev-parse --verify "$target_branch" >/dev/null 2>&1; then
        printf "\033[1;31mErreur : Une des branches n'existe pas.\033[0m\n" >&2
        return 2  # Code d'erreur spécifique
    fi

    # Vérifier si target_branch est strictement en avance sur base_branch
    local ahead_behind
    ahead_behind=$(git rev-list --left-right --count "$base_branch...$target_branch")

    local ahead_count behind_count
    ahead_count=$(echo "$ahead_behind" | awk '{print $2}')
    behind_count=$(echo "$ahead_behind" | awk '{print $1}')

    if [[ "$behind_count" -eq 0 && "$ahead_count" -gt 0 ]]; then
        return 0  # Vrai (fast-forward possible)
    else
        return 1  # Faux
    fi
}
