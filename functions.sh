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

# Signale l'usage d'une syntaxe dépréciée sans interrompre la commande : elle
# continue de fonctionner, le temps que les habitudes et les scripts de chacun
# rattrapent la nouvelle forme.
warn_deprecated_syntax() {
  local old_form="$1"
  local new_form="$2"

  printf "%s[déprécié] « %s » : utilisez désormais « %s ».%s\n" \
    "$(tput setaf 3)" "$old_form" "$new_form" "$(tput sgr0)" >&2
  printf "%sL'ancienne forme fonctionne encore mais sera retirée dans une prochaine version.%s\n" \
    "$(tput setaf 3)" "$(tput sgr0)" >&2
}

# Vrai si la valeur est un numéro de version de release (x.y.z), que le préfixe
# release/ soit présent ou non. Sert à distinguer, en position de cible,
# une version d'un nom de branche.
is_release_version() {
  local value="${1#release/}"

  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

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
        # Mode recover : on est déjà dans un chemin d'erreur, il ne doit ni
        # synchroniser, ni échouer, ni rappeler exit_safe.
        switch_branch "$current_branch" recover
    fi

    if [[ $stash == true ]]; then
        git stash pop
    fi

    if [[ $exit_code -ne 0 ]]; then
        echo "/!\ Script finished in error! Be careful about your branch management on local."
    fi

    exit $exit_code
}

# Les branches sont déjà poussées quand gh échoue : le message doit dire ce
# qu'il reste à rejouer à la main, pas laisser croire qu'il faut tout refaire.
report_pr_creation_failure() {
    local branch="$1"
    local branch_PR="$2"

    printf "\033[1;31mLa pull request n'a pas pu être créée sur GitHub.\033[0m\n" >&2
    printf "Les branches %s et %s sont bien poussées : il ne reste que la PR à ouvrir.\n" "$branch" "$branch_PR" >&2
    printf "Relancez « gh pr create --base=%s --head=%s » ou ouvrez-la depuis GitHub.\n" "$branch_PR" "$branch" >&2
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
# Si aucune branche de référence n'existe, la fonction renvoie 1 et écrit son
# message sur stderr : l'appelant doit contrôler le code de retour.
get_reference_branch() {
    local feature_type=${1:-feature}
    local fallback_branches=("develop" "master" "main")

    # branch_exists regarde en local ET sur le serveur. Chercher seulement en
    # local ferait basculer tout clone frais sur le repli : develop n'y est pas
    # encore une branche locale, et une feature serait partie de main.
    if [ "$feature_type" == "hotfix" ] && branch_exists "$branch_prod"; then
        echo "$branch_prod"
        return 0  # Succès
    elif [ "$feature_type" == "feature" ] && branch_exists "$branch_preprod"; then
        echo "$branch_preprod"
        return 0  # Succès
    fi

    # Le repli ne concerne que les projets qui n'ont pas la branche attendue.
    for branch in "${fallback_branches[@]}"; do
        if branch_exists "$branch"; then
        echo "$branch"
        return 0  # Succès
        fi
    done

    # La fonction est appelée en substitution de commande : un exit_safe ne
    # quitterait que le sous-shell et le message partirait sur stdout, donc
    # serait lu comme un nom de branche. On passe par stderr + code de retour.
    printf "\033[1;31mErreur : aucune branche de référence valide trouvée.\033[0m\n" >&2
    return 1
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
# Renvoie 1 dès qu'un cherry-pick n'a pas pu aboutir, à charge de l'appelant
# de restaurer l'état local.
cherry_pick_commits() {
  local commits=("$@")

  for commit in "${commits[@]}"; do
    if ! cherry_pick "$commit"; then
      return 1
    fi
  done

  return 0
}

# Fonction pour effectuer un cherry-pick sur le hash passé en argument si celui n'existe pas déjà.
# Renvoie 0 si le commit a bien été appliqué, 1 si le cherry-pick a été abandonné.
cherry_pick() {
    local commit=$1

    # Vérifier si le commit est déjà dans l'historique de la branche courante
    if git merge-base --is-ancestor "$commit" HEAD; then
      echo "Commit $commit déjà appliqué, passage au suivant..."
      return 0
    fi

    echo "Cherry-picking commit: $commit"
    if git cherry-pick "$commit" --allow-empty; then
      return 0
    fi

    # Le cherry-pick a échoué : un conflit doit être résolu.
    echo ""
    printf "%sErreur lors du cherry-pick du commit %s. Conflit détecté.%s\n" \
      "$(tput setaf 1)" "$commit" "$(tput sgr0)"

    # Un conflit réclame une intervention humaine : il est hors de question de
    # le "valider" tout seul en mode non interactif.
    if [[ $JGIT_NO_INTERACTION == true ]]; then
      printf "%sLe mode --no-interaction ne permet pas de résoudre un conflit.%s\n" \
        "$(tput setaf 1)" "$(tput sgr0)"
      printf "%sRelancez la même commande sans --no-interaction pour traiter ce conflit à la main.%s\n" \
        "$(tput setaf 1)" "$(tput sgr0)"
      git cherry-pick --abort >/dev/null 2>&1
      return 1
    fi

    printf "%sMerci de ne rien faire ici tant que le conflit n'est pas résolu et commité%s\n" \
      "$(tput setaf 1)" "$(tput sgr0)"

    # Demander confirmation à l'utilisateur
    if ! confirm_action "Avez vous résolu et commité la résolution de conflit ?" "y"; then
        echo "Opération annulée."
        git cherry-pick --abort >/dev/null 2>&1
        return 1
    fi

    return 0
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

###############################################
###############################################
#      Changement de branche : point unique
###############################################
###############################################

# jgit travaille toujours sur la version serveur des branches. Deux fonctions
# seulement le garantissent : jgit_fetch_once rapatrie les références, et
# switch_branch est le seul endroit du dépôt qui appelle `git checkout`.

# Un seul fetch par exécution : toutes les synchronisations qui suivent se font
# sur les références déjà rapatriées, sans nouvel aller-retour réseau.
JGIT_FETCH_DONE=false

jgit_fetch_once() {
  if [[ $JGIT_FETCH_DONE == true ]]; then
    return 0
  fi

  # --prune : une branche supprimée sur le serveur doit disparaître du miroir
  # local, sinon jgit continue de la croire disponible.
  if ! git fetch "$j2s_remote" --prune --quiet; then
    printf "\033[1;31mImpossible de contacter %s.\033[0m\n" "$j2s_remote" >&2
    printf "jgit travaille toujours sur les dernières versions du serveur : vérifiez votre connexion.\n" >&2
    return 1
  fi

  JGIT_FETCH_DONE=true
}

# Remet la branche courante au niveau de son homologue distante, en fast-forward
# strict. Suppose que l'on est déjà positionné dessus et que le fetch a eu lieu.
#
#   pas d'homologue distante -> rien à faire (branches temporaires jgit_*)
#   en retard                -> mise à jour
#   en avance                -> acceptée telle quelle, rien n'est poussé
#   divergence               -> échec, sans rien modifier
#
# Le cas « en avance » est celui d'une branche de travail sur laquelle on vient
# de commiter : c'est normal, jgit ne pousse jamais à la place du développeur.
sync_branch_with_remote() {
  local branch="$1"
  local remote_ref="$j2s_remote/$branch"

  if ! git show-ref --verify --quiet "refs/remotes/$remote_ref"; then
    return 0
  fi

  local counts behind ahead
  if ! counts=$(git rev-list --left-right --count "$remote_ref...$branch"); then
    printf "\033[1;31mImpossible de comparer %s à %s.\033[0m\n" "$branch" "$remote_ref" >&2
    return 1
  fi
  behind=$(awk '{print $1}' <<< "$counts")
  ahead=$(awk '{print $2}' <<< "$counts")

  if [[ $behind -gt 0 && $ahead -gt 0 ]]; then
    printf "\033[1;31mLa branche %s a divergé de %s.\033[0m\n" "$branch" "$remote_ref" >&2
    printf "%s commit(s) uniquement en local, %s commit(s) uniquement sur le serveur.\n" "$ahead" "$behind" >&2
    printf "jgit ne choisit pas à votre place : réconciliez la branche (rebase ou merge) puis relancez.\n" >&2
    return 1
  fi

  if [[ $behind -gt 0 ]]; then
    if ! git merge --ff-only "$remote_ref" --quiet; then
      printf "\033[1;31mLa mise à jour de %s depuis %s a échoué.\033[0m\n" "$branch" "$remote_ref" >&2
      return 1
    fi
    printf "%s mise à jour depuis %s (%s commit(s)).\n" "$branch" "$remote_ref" "$behind"
    return 0
  fi

  if [[ $ahead -gt 0 ]]; then
    printf "%s a %s commit(s) d'avance sur %s, non poussé(s).\n" "$branch" "$ahead" "$remote_ref"
  fi

  return 0
}

# Vrai si la branche existe, en local ou sur le remote. S'appuie sur les mêmes
# références que switch_branch, pour qu'un contrôle préalable et la bascule qui
# suit ne puissent jamais être en désaccord.
branch_exists() {
  local branch="$1"

  [[ -n "$branch" ]] || return 1
  git show-ref --verify --quiet "refs/heads/$branch" && return 0
  git show-ref --verify --quiet "refs/remotes/$j2s_remote/$branch"
}

# Unique point d'entrée pour changer de branche : aucun autre `git checkout` ne
# doit exister dans le dépôt. Toute branche sur laquelle on va travailler est
# donc remise au niveau du serveur au moment où on y bascule.
#
#   switch_branch <branche> [mode]
#
#   sync     (défaut) la branche doit exister en local ou sur le remote ; elle est
#                     synchronisée ; toute anomalie arrête la commande
#   create            comme sync, mais crée la branche depuis la branche courante
#                     si elle n'existe nulle part
#   try               comme sync, mais renvoie 1 au lieu d'arrêter la commande
#   nosync            bascule sans synchroniser, mais échoue si le checkout rate.
#                     Réservé aux branches que jgit vient délibérément de
#                     réécrire et s'apprête à pousser en force : après un rebase,
#                     la divergence avec le serveur est le résultat attendu, pas
#                     une anomalie.
#   recover           chemin de récupération : ni fetch, ni synchronisation, ni
#                     échec — utilisé par exit_safe, qui traite déjà une erreur
#   discard           comme recover, mais force le checkout en abandonnant l'état
#                     de l'arbre de travail (annulation d'un rebase en conflit)
switch_branch() {
  local branch="$1"
  local mode="${2:-sync}"

  case "$mode" in
    recover)
      [[ -n "$branch" ]] && git checkout "$branch" --quiet 2>/dev/null
      return 0
      ;;
    discard)
      [[ -n "$branch" ]] && git checkout -f "$branch" --quiet 2>/dev/null
      return 0
      ;;
  esac

  local fatal=true
  [[ "$mode" == "try" ]] && fatal=false

  if [[ -z "$branch" ]]; then
    printf "\033[1;31mErreur : Aucun nom de branche fourni.\033[0m\n" >&2
    [[ $fatal == true ]] && exit_safe 1
    return 1
  fi

  if [[ "$mode" != "nosync" ]] && ! jgit_fetch_once; then
    [[ $fatal == true ]] && exit_safe 1
    return 1
  fi

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git checkout "$branch" --quiet; then
      printf "\033[1;31mImpossible de basculer sur %s.\033[0m\n" "$branch" >&2
      [[ $fatal == true ]] && exit_safe 1
      return 1
    fi
    if [[ "$mode" != "nosync" ]] && ! sync_branch_with_remote "$branch"; then
      [[ $fatal == true ]] && exit_safe 1
      return 1
    fi
  elif git show-ref --verify --quiet "refs/remotes/$j2s_remote/$branch"; then
    if ! git checkout -b "$branch" "$j2s_remote/$branch" --quiet; then
      printf "\033[1;31mImpossible de créer %s depuis %s/%s.\033[0m\n" "$branch" "$j2s_remote" "$branch" >&2
      [[ $fatal == true ]] && exit_safe 1
      return 1
    fi
  elif [[ "$mode" == "create" ]]; then
    echo "Bascule vers '$branch' (Création depuis la branche courante)"
    if ! git checkout -b "$branch" --quiet; then
      printf "\033[1;31mImpossible de créer la branche %s.\033[0m\n" "$branch" >&2
      [[ $fatal == true ]] && exit_safe 1
      return 1
    fi
  else
    printf "\033[1;31mLa branche %s n'existe pas (ni en local ni sur %s).\033[0m\n" "$branch" "$j2s_remote" >&2
    [[ $fatal == true ]] && exit_safe 1
    return 1
  fi

  return 0
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

  if ! jgit_fetch_once; then
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

  if ! switch_branch "$temp_branch" try; then
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

  switch_branch "$start_branch" recover
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
