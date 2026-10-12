#!/bin/bash

###############################################
###############################################
#      Rejeu de commits : cherry-pick, pause, reprise
###############################################
###############################################
#
# jgit n'a qu'une façon de rejouer des commits : le cherry-pick, un par un, dans
# l'ordre. Le rebase d'une feature et la reconstruction d'une démo passent tous
# les deux par ici, et se comportent donc de la même façon face à un conflit.
#
# La conduite face à un conflit se choisit avec --on-conflict :
#
#   ask    défaut en interactif. jgit attend que le développeur ait résolu et
#          commité dans un autre terminal, puis continue.
#   abort  défaut sans interaction (--no-interaction, --json). Tout est annulé,
#          rien n'a été poussé. C'est la conduite de Jenkins.
#   pause  jgit s'arrête (code 3) en laissant le cherry-pick en cours, et
#          enregistre où il en est. Un humain ou une IA résout les fichiers,
#          les marque résolus (git add), puis `jgit <scope> continue` reprend
#          exactement là où l'opération s'était arrêtée. `jgit <scope> abort`
#          annule tout.
#
# Une seule opération peut être en pause dans un dépôt : elle occupe l'espace de
# travail. Tant qu'elle l'est, toute commande qui modifie quelque chose refuse
# (code 5) et rappelle les deux issues.
#
# Bonus : les cherry-picks tournent avec git rerere. Un conflit déjà résolu sur
# ce poste voit sa résolution réappliquée dans les fichiers ; il ne reste qu'à
# vérifier et à la valider. Rien ne dépend de ce cache, qui reste local.

JGIT_ON_CONFLICT="${JGIT_ON_CONFLICT:-}"

# Rejeu discret (démos) : la sortie de git est tue, seul le constat de conflit
# reste. jgit en fait de toute façon son propre résumé.
REPLAY_QUIET="${REPLAY_QUIET:-false}"

# Conduite effective face à un conflit. « ask » sans personne pour répondre
# reviendrait à valider un conflit tout seul : il devient « abort ».
jgit_conflict_mode() {
  local mode="$JGIT_ON_CONFLICT"

  if [[ -z "$mode" ]]; then
    if [[ $JGIT_NO_INTERACTION == true ]]; then
      mode="abort"
    else
      mode="ask"
    fi
  fi

  if [[ "$mode" == "ask" && $JGIT_NO_INTERACTION == true ]]; then
    mode="abort"
  fi

  printf '%s' "$mode"
}

###############################################
#            État d'une opération en pause
###############################################
#
# Fichier clé=valeur dans le dossier .git du dépôt : il suit le dépôt, ne se
# commite jamais et n'est visible d'aucun autre poste. Seules des variables
# préfixées OP_ y sont écrites et relues.

jgit_state_file() {
  printf '%s/jgit/operation.state' "$(git rev-parse --absolute-git-dir 2>/dev/null)"
}

jgit_state_exists() {
  [[ -f "$(jgit_state_file)" ]]
}

# Enregistre les variables nommées (toutes en OP_*).
jgit_state_save() {
  local file name
  file=$(jgit_state_file)

  mkdir -p "$(dirname "$file")" || return 1
  {
    printf 'format=1\n'
    for name in "$@"; do
      printf '%s=%s\n' "$name" "${!name}"
    done
  } > "$file.tmp" && mv "$file.tmp" "$file"
}

# Relit l'état enregistré dans les variables OP_*.
jgit_state_load() {
  local file line key value
  file=$(jgit_state_file)

  [[ -f "$file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^OP_[A-Za-z0-9_]+$ ]] || continue
    printf -v "$key" '%s' "$value"
  done < "$file"
}

jgit_state_clear() {
  rm -f "$(jgit_state_file)"
}

# Refuse toute commande qui modifierait quelque chose pendant qu'une opération
# attend la résolution d'un conflit : elle occupe l'espace de travail, et la
# moindre bascule de branche la détruirait.
refuse_if_operation_paused() {
  jgit_state_exists || return 0
  jgit_state_load

  jgit_error_set operation_in_progress \
    "Une opération jgit attend la résolution d'un conflit : $OP_label." \
    "$OP_continue_command   (ou, pour tout annuler : $OP_abort_command)"

  printf "${C_RED}Une opération jgit attend la résolution d'un conflit : %s.${C_RESET}\n" "$OP_label" >&2
  printf "Elle occupe l'espace de travail : aucune autre commande ne peut tourner avant qu'elle soit terminée.\n" >&2
  printf "\nRésolvez le conflit puis reprenez :\n  %s\n" "$OP_continue_command" >&2
  printf "\n…ou annulez-la :\n  %s\n" "$OP_abort_command" >&2

  # Pas de exit_safe : il tenterait de changer de branche au milieu du conflit.
  exit "$JGIT_EXIT_PAUSED"
}

###############################################
#            jgit util status
###############################################

# Dit si une opération attend la résolution d'un conflit, et où elle en est :
# ce qu'il faut à quelqu'un (ou à une IA, ou à l'interface) qui arrive au milieu.
util_status_cmd() {
  local commit="" first context="" subject=""
  local current
  current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if ! jgit_state_exists; then
    printf "Aucune opération jgit en pause.\n"
    json_emit "$(json_object \
      "$(json_kv_str schema "jgit.status/1")" \
      "$(json_kv_bool ok true)" \
      "$(json_kv_str command "util status")" \
      "$(json_kv_str_or_null current_branch "$current")" \
      "$(json_kv_null operation_in_progress)")"
    return 0
  fi

  jgit_state_load

  if [[ "$OP_operation" == demo_* ]]; then
    first="${OP_plan%% *}"
    first="${first#pick:}"
    commit="${first%%:*}"
    context=$(json_object \
      "$(json_kv_str demo "$OP_name")" \
      "$(json_kv_str_or_null ticket "$([[ "$OP_current_ticket" != "-" ]] && printf '%s' "$OP_current_ticket")")")
  else
    commit="${OP_pending%% *}"
  fi
  REPLAY_CONFLICT_COMMIT="$commit"
  REPLAY_CONFLICT_LINES=$(replay_conflict_lines)
  [[ -n "$commit" ]] && subject=$(git log -n 1 --format=%s "$commit" 2>/dev/null)

  printf "${C_YELLOW}Une opération attend la résolution d'un conflit : %s.${C_RESET}\n" "$OP_label"
  printf "Commit en cause : %s « %s » (branche %s)\n" "$(git rev-parse --short "$commit" 2>/dev/null)" "$subject" "$OP_branch"
  if [[ -n "$REPLAY_CONFLICT_LINES" ]]; then
    replay_print_conflict_files "$REPLAY_CONFLICT_LINES" 2>&1
  else
    printf "Plus aucun fichier en conflit : il reste à reprendre.\n"
  fi
  printf "\nReprendre : %s\nAnnuler   : %s\n" "$OP_continue_command" "$OP_abort_command"

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.status/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "util status")" \
    "$(json_kv_str_or_null current_branch "$current")" \
    "$(json_kv operation_in_progress "$(json_object \
        "$(json_kv_str operation "$OP_operation")" \
        "$(json_kv_str target "$OP_target")" \
        "$(json_kv_str label "$OP_label")" \
        "$(json_kv_str branch "$OP_branch")" \
        "$(json_kv commit "$(json_object \
            "$(json_kv_str_or_null sha "$commit")" \
            "$(json_kv_str_or_null subject "$subject")")")" \
        "$(json_kv conflicted_files "$(replay_conflict_files_json "$REPLAY_CONFLICT_LINES")")" \
        "$(json_kv progress "$(json_object \
            "$(json_kv_num done "$OP_done")" \
            "$(json_kv_num total "$OP_total")")")" \
        "$(json_kv commands "$(json_object \
            "$(json_kv_str continue "$OP_continue_command")" \
            "$(json_kv_str abort "$OP_abort_command")")")" \
        ${context:+"$(json_kv context "$context")"})")")"
}

###############################################
#            Fichiers en conflit
###############################################

# Lignes « <XY> <chemin> » des fichiers en conflit, XY étant le code de
# `git status --porcelain`.
replay_conflict_lines() {
  local line path

  git -c core.quotePath=false status --porcelain=v1 2>/dev/null | while IFS= read -r line; do
    case "${line:0:2}" in
      UU|AA|DD|AU|UA|DU|UD)
        path="${line:3}"
        # Un chemin avec espaces arrive entre guillemets.
        if [[ "$path" == \"*\" ]]; then
          path="${path#\"}"
          path="${path%\"}"
        fi
        printf '%s %s\n' "${line:0:2}" "$path"
        ;;
    esac
  done
}

# Lignes « MK <chemin> » des fichiers marqués résolus mais qui contiennent
# encore des marqueurs de conflit.
replay_conflict_marker_lines() {
  git -c core.quotePath=false diff --cached --check 2>/dev/null \
    | sed -n 's/^\(.*\):[0-9][0-9]*: leftover conflict marker$/\1/p' \
    | sort -u \
    | while IFS= read -r path; do
        printf 'MK %s\n' "$path"
      done
}

replay_conflict_kind() {
  case "$1" in
    MK) printf 'conflict_markers' ;;
    UU) printf 'both_modified' ;;
    AA) printf 'both_added' ;;
    DD) printf 'both_deleted' ;;
    AU) printf 'added_by_us' ;;
    UA) printf 'added_by_them' ;;
    DU) printf 'deleted_by_us' ;;
    UD) printf 'deleted_by_them' ;;
    *)  printf 'unknown' ;;
  esac
}

replay_conflict_kind_label() {
  case "$1" in
    MK) printf 'marqueurs de conflit restés dans le fichier' ;;
    UU) printf 'modifié des deux côtés' ;;
    AA) printf 'ajouté des deux côtés' ;;
    DD) printf 'supprimé des deux côtés' ;;
    AU|UA) printf "ajouté d'un seul côté" ;;
    DU) printf "supprimé de notre côté, modifié de l'autre" ;;
    UD) printf "modifié de notre côté, supprimé de l'autre" ;;
    *)  printf 'conflit' ;;
  esac
}

# Tableau JSON des fichiers en conflit, à partir des lignes de
# replay_conflict_lines passées en premier argument.
replay_conflict_files_json() {
  local lines="$1"
  local items=()
  local line code path

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    code="${line:0:2}"
    path="${line:3}"
    items[${#items[@]}]=$(json_object \
      "$(json_kv_str path "$path")" \
      "$(json_kv_str kind "$(replay_conflict_kind "$code")")")
  done <<< "$lines"

  json_array ${items[@]+"${items[@]}"}
}

replay_print_conflict_files() {
  local lines="$1"
  local line

  [[ -n "$lines" ]] || return 0
  printf "Fichiers en conflit :\n" >&2
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf "  - %s (%s)\n" "${line:3}" "$(replay_conflict_kind_label "${line:0:2}")" >&2
  done <<< "$lines"
}

###############################################
#            Cherry-pick
###############################################

# Commit en conflit et fichiers concernés, renseignés par cherry_pick.
REPLAY_CONFLICT_COMMIT=""
REPLAY_CONFLICT_LINES=""
# Commits restant à rejouer, celui en conflit compris, quand cherry_pick_commits
# s'arrête en pause.
REPLAY_PENDING=()
REPLAY_HEAD_BEFORE=""

# Rejoue un commit sur la branche courante, s'il n'y est pas déjà.
#
# Codes de retour :
#   0  appliqué, ou déjà présent
#   1  conflit, et le développeur a refusé de le résoudre (annulé)
#   2  conflit, abandonné sans interaction (--on-conflict abort)
#   3  conflit laissé en cours (--on-conflict pause) : à l'appelant d'enregistrer
#      l'état et de rendre la main
#
# Un commit qui devient vide parce que son contenu est déjà là est conservé
# vide (--keep-redundant-commits) : il garde ainsi sa trace — auteur, date,
# sujet — dans l'historique, au lieu d'interrompre le rejeu pour rien.
cherry_pick() {
    local commit=$1

    # Vérifier si le commit est déjà dans l'historique de la branche courante
    if git merge-base --is-ancestor "$commit" HEAD; then
      echo "Commit $commit déjà appliqué, passage au suivant..."
      return 0
    fi

    if [[ $REPLAY_QUIET == true ]]; then
      if git -c rerere.enabled=true cherry-pick "$commit" --allow-empty --keep-redundant-commits >/dev/null 2>&1; then
        return 0
      fi
    else
      echo "Cherry-picking commit: $commit"
      if git -c rerere.enabled=true cherry-pick "$commit" --allow-empty --keep-redundant-commits; then
        return 0
      fi
    fi

    # Le cherry-pick a échoué : un conflit doit être résolu.
    REPLAY_CONFLICT_COMMIT="$commit"
    REPLAY_CONFLICT_LINES=$(replay_conflict_lines)

    echo ""
    printf "%sErreur lors du cherry-pick du commit %s. Conflit détecté.%s\n" \
      "$(jgit_tput setaf 1)" "$commit" "$(jgit_tput sgr0)"

    case "$(jgit_conflict_mode)" in
      pause)
        return 3
        ;;
      abort)
        # Un conflit réclame une intervention : il est hors de question de le
        # « valider » tout seul.
        if [[ $JGIT_NO_INTERACTION == true ]]; then
          printf "%sLe mode --no-interaction ne permet pas de résoudre un conflit.%s\n" \
            "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"
          printf "%sRelancez la même commande sans --no-interaction pour traiter ce conflit à la main,%s\n" \
            "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"
          printf "%sou avec --on-conflict pause pour le résoudre puis reprendre.%s\n" \
            "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"
        else
          printf "%s--on-conflict abort : l'opération est abandonnée au premier conflit.%s\n" \
            "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"
        fi
        git cherry-pick --abort >/dev/null 2>&1
        return 2
        ;;
    esac

    printf "%sMerci de ne rien faire ici tant que le conflit n'est pas résolu et commité%s\n" \
      "$(jgit_tput setaf 1)" "$(jgit_tput sgr0)"

    # Demander confirmation à l'utilisateur
    if ! confirm_action "Avez vous résolu et commité la résolution de conflit ?" "y"; then
        echo "Opération annulée."
        git cherry-pick --abort >/dev/null 2>&1
        return 1
    fi

    # Le développeur a commité sans rerere : on enregistre sa résolution pour la
    # prochaine fois.
    git -c rerere.enabled=true rerere >/dev/null 2>&1

    return 0
}

# Rejoue chaque commit du tableau, dans l'ordre. Renvoie le code de cherry_pick
# dès qu'un commit n'a pas pu aboutir ; à charge de l'appelant de restaurer
# l'état local (codes 1 et 2) ou d'enregistrer la pause (code 3, avec
# REPLAY_PENDING et REPLAY_HEAD_BEFORE renseignés).
cherry_pick_commits() {
  local commits=("$@")
  local head_before status
  local index=0

  REPLAY_PENDING=()
  REPLAY_HEAD_BEFORE=""

  for commit in "${commits[@]}"; do
    head_before=$(git rev-parse HEAD)

    cherry_pick "$commit"
    status=$?

    if [[ $status -eq 3 ]]; then
      REPLAY_PENDING=("${commits[@]:$index}")
      REPLAY_HEAD_BEFORE="$head_before"
      return 3
    fi

    if [[ $status -ne 0 ]]; then
      return $status
    fi

    replay_restamp_if_init "$head_before"
    index=$((index + 1))
  done

  return 0
}

# Un commit d'init rejoué porte encore l'origine d'avant le rebase. On la
# remplace au moment où on le repose, seul instant où il est en tête.
# Le garde-fou sur HEAD évite de toucher au commit de résolution de conflit
# du développeur, ou à un commit déjà présent que cherry_pick a sauté.
replay_restamp_if_init() {
  local head_before="$1"
  local subject

  if [[ -n "$JGIT_RESTAMP_BRANCH" && "$(git rev-parse HEAD)" != "$head_before" ]]; then
    subject=$(git log -n 1 --format=%s HEAD)
    if [[ "$subject" == *"$suffix_init_commit"* ]]; then
      restamp_based_on_head "$JGIT_RESTAMP_BRANCH" "$JGIT_RESTAMP_BASED_ON"
    fi
  fi
}

# Termine le cherry-pick laissé en pause, une fois le conflit résolu.
#
#   replay_finish_paused_pick <head_avant> <commit>
#
# Codes de retour :
#   0   le commit est appliqué (ou a été volontairement ignoré)
#   10  des fichiers sont encore en conflit
#   11  des marqueurs de conflit ont été marqués résolus tels quels
#   12  git a refusé de terminer le cherry-pick
replay_finish_paused_pick() {
  local head_before="$1"
  local commit="$2"

  REPLAY_CONFLICT_COMMIT="$commit"
  REPLAY_CONFLICT_LINES=""

  if git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
    REPLAY_CONFLICT_LINES=$(replay_conflict_lines)
    if [[ -n "$REPLAY_CONFLICT_LINES" ]]; then
      return 10
    fi

    if git diff --cached --check 2>/dev/null | grep -q "leftover conflict marker"; then
      return 11
    fi

    if ! GIT_EDITOR=true git -c rerere.enabled=true cherry-pick --continue; then
      # La résolution a rendu le commit vide : on le garde vide, avec son
      # auteur et son message d'origine, pour qu'il reste reconnaissable.
      if git diff --cached --quiet 2>/dev/null; then
        git -c rerere.enabled=true commit --allow-empty --no-verify --quiet -C "$commit" || return 12
      else
        return 12
      fi
    fi
  elif [[ "$(git rev-parse HEAD)" == "$head_before" ]]; then
    printf "%sAucun commit pour %s : il a été ignoré (git cherry-pick --skip).%s\n" \
      "$C_YELLOW" "$commit" "$C_RESET" >&2
  fi

  replay_restamp_if_init "$head_before"
  return 0
}

###############################################
#            Rapport de conflit
###############################################

# Document jgit.conflict/1.
#
#   replay_conflict_document <paused:true|false> <code> <message> <branche>
#                            <commande continue> <commande abort> <fait> <total>
#                            [fragment JSON de contexte]
replay_conflict_document() {
  local paused="$1"
  local code="$2"
  local message="$3"
  local branch="$4"
  local continue_command="$5"
  local abort_command="$6"
  local done_count="$7"
  local total="$8"
  local context="${9:-}"
  local commit="$REPLAY_CONFLICT_COMMIT"
  local subject="" commands="null" hint=""

  if [[ -n "$commit" ]]; then
    subject=$(git log -n 1 --format=%s "$commit" 2>/dev/null)
  fi

  if [[ $paused == true ]]; then
    commands=$(json_object \
      "$(json_kv_str continue "$continue_command")" \
      "$(json_kv_str abort "$abort_command")")
    hint="$continue_command"
  fi

  json_object \
    "$(json_kv_str schema "jgit.conflict/1")" \
    "$(json_kv_bool ok false)" \
    "$(json_kv_str_or_null command "$JGIT_COMMAND")" \
    "$(json_kv_str operation "$OP_operation")" \
    "$(json_kv_str target "$OP_target")" \
    "$(json_kv_bool paused "$paused")" \
    "$(json_kv error "$(json_object \
        "$(json_kv_str code "$code")" \
        "$(json_kv_num exit_code "$JGIT_EXIT_CONFLICT")" \
        "$(json_kv_str message "$message")" \
        "$(json_kv_str_or_null hint "$hint")")")" \
    "$(json_kv_str_or_null branch "$branch")" \
    "$(json_kv commit "$(json_object \
        "$(json_kv_str_or_null sha "$commit")" \
        "$(json_kv_str_or_null subject "$subject")")")" \
    "$(json_kv conflicted_files "$(replay_conflict_files_json "$REPLAY_CONFLICT_LINES")")" \
    "$(json_kv progress "$(json_object \
        "$(json_kv_num done "$done_count")" \
        "$(json_kv_num total "$total")")")" \
    "$(json_kv commands "$commands")" \
    ${context:+"$(json_kv context "$context")"}
}

# Rend la main sur un conflit en pause : l'état est déjà enregistré, le
# cherry-pick reste en cours. Pas de exit_safe : il changerait de branche et
# restituerait le stash au milieu du conflit.
#
#   replay_pause_exit <code> <message> [contexte JSON]
replay_pause_exit() {
  local code="$1"
  local message="$2"
  local context="${3:-}"
  local short subject

  short=$(git rev-parse --short "$REPLAY_CONFLICT_COMMIT" 2>/dev/null)
  subject=$(git log -n 1 --format=%s "$REPLAY_CONFLICT_COMMIT" 2>/dev/null)

  printf "\n${C_RED}%s${C_RESET}\n" "$message" >&2
  printf "Commit en cause : %s « %s » (branche %s)\n" "$short" "$subject" "$OP_branch" >&2
  replay_print_conflict_files "$REPLAY_CONFLICT_LINES"
  printf "\nL'opération est en pause : rien n'a été poussé.\n" >&2
  printf "Résolvez les conflits dans les fichiers, marquez-les résolus (git add <fichier>), puis :\n" >&2
  printf "  %s\n" "$OP_continue_command" >&2
  printf "Pour tout annuler :\n" >&2
  printf "  %s\n" "$OP_abort_command" >&2

  json_emit "$(replay_conflict_document true "$code" "$message" "$OP_branch" \
    "$OP_continue_command" "$OP_abort_command" "$OP_done" "$OP_total" "$context")"

  exit "$JGIT_EXIT_CONFLICT"
}

# Document d'un conflit abandonné (--on-conflict abort), avant exit_safe.
replay_report_aborted_conflict() {
  local message="$1"
  local context="${2:-}"

  jgit_error_set conflict "$message"
  json_emit "$(replay_conflict_document false conflict "$message" "" "" "" \
    "$OP_done" "$OP_total" "$context")"
}
