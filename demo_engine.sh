#!/bin/bash

###############################################
###############################################
#      Démos : fabrication (create, add, drop, refresh, rebase)
###############################################
###############################################
#
# Toutes les commandes qui modifient une démo suivent le même chemin :
#
#   1. lire la démo sur le serveur et décider d'un PLAN ;
#   2. dérouler le plan sur une branche temporaire jgit_demo_<nom>, avec le
#      moteur de rejeu commun (replay.sh) — mêmes conflits, même pause, même
#      reprise que le rebase d'une feature ;
#   3. publier d'un seul push, et seulement si la démo n'a pas bougé sur le
#      serveur depuis la lecture (--force-with-lease sur la version lue).
#
# Le plan est une suite d'instructions, enregistrée telle quelle si un conflit
# met l'opération en pause :
#
#   init:<base>          pose le commit d'init de la démo
#   pick:<sha>:<ticket>  cherry-picke un commit (ticket « - » : commit hors ticket)
#   marker:<ticket>      pose le repère qui clôt le segment du ticket
#
# Une démo inchangée n'est jamais republiée : un déploiement qui surveille la
# branche ne se relance pas pour rien.

DEMO_WORK_PREFIX="jgit_demo_"

# Variables d'une opération sur une démo, enregistrées si elle se met en pause.
DEMO_OP_STATE=(OP_operation OP_target OP_label OP_continue_command OP_abort_command
    OP_name OP_branch OP_base OP_old_sha OP_lease OP_plan OP_head_before
    OP_done OP_total OP_segment_count OP_current_ticket OP_return_branch
    OP_on_conflict OP_added OP_updated OP_dropped OP_warnings OP_start)

###############################################
#            Préparation
###############################################

# Charge la démo cible d'une commande qui la modifie, et refuse ce qui ne se
# modifie pas : archive, ancien format, démo illisible.
#   demo_load_for_update <saisie> <commande>
demo_load_for_update() {
  local input="$1"
  local command="$2"

  demo_require_target "$input" "$command"

  case "$DEMO_KIND" in
    archived)
      jgit_fail archived "$JGIT_EXIT_REFUSED" \
        "La démo $DEMO_BRANCH est archivée : elle est en lecture seule." \
        "Pour la reprendre : jgit demo unarchive $DEMO_BRANCH"
      ;;
    legacy)
      jgit_fail legacy_format "$JGIT_EXIT_REFUSED" \
        "La démo $DEMO_BRANCH est à l'ancien format : elle est en lecture seule." \
        "Pour la convertir au format actuel : jgit demo migrate $DEMO_NAME"
      ;;
  esac

  if ! demo_load "$DEMO_BRANCH"; then
    jgit_fail not_a_demo "$JGIT_EXIT_REFUSED" \
      "La branche $DEMO_BRANCH n'a pas de commit d'initialisation de démo : jgit ne sait pas la lire."
  fi
}

# Vérifie un ticket demandé par --from : format, et présence sur le serveur.
demo_check_ticket_source() {
  local ticket="$1"

  if [[ "$ticket" != feature/* && "$ticket" != hotfix/* ]] || [[ "$ticket" == */ ]]; then
    jgit_fail bad_ticket_format "$JGIT_EXIT_REFUSED" \
      "« $ticket » n'est pas un ticket : le format attendu est feature/<ticket> ou hotfix/<ticket>." \
      "Les tickets disponibles : jgit demo candidates"
  fi

  if ! demo_remote_exists "$ticket"; then
    jgit_fail ticket_not_found "$JGIT_EXIT_REFUSED" \
      "La branche $ticket n'existe pas sur $j2s_remote." \
      "Les tickets disponibles : jgit demo candidates"
  fi
}

# Index d'un ticket dans DEMO_TICKETS, ou code 1.
demo_ticket_index() {
  local ticket="$1"
  local i

  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    if [[ "${DEMO_TICKETS[$i]}" == "$ticket" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

# Vrai si la liste (séparée par des espaces) contient le mot.
demo_list_has() {
  local list=" $1 "
  [[ "$list" == *" $2 "* ]]
}

demo_list_add() {
  if [[ -z "$1" ]]; then
    printf '%s' "$2"
  else
    printf '%s %s' "$1" "$2"
  fi
}

# Instructions qui rejouent un segment de la démo lue, tel qu'il est.
demo_plan_replay_segment() {
  local index="$1"
  local ticket="${DEMO_SEG_TICKET[$index]}"
  local sha plan=""

  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    plan=$(demo_list_add "$plan" "pick:$sha:$ticket")
  done <<< "${DEMO_SEG_SHAS[$index]}"
  plan=$(demo_list_add "$plan" "marker:$ticket")
  printf '%s' "$plan"
}

# Instructions qui posent un ticket depuis sa branche : tous ses commits utiles,
# ou seulement ceux dont l'empreinte manque à la démo (« suite »).
#   demo_plan_fresh_segment <ticket> <base> [only_missing]
demo_plan_fresh_segment() {
  local ticket="$1"
  local base="$2"
  local only_missing="${3:-false}"
  local demo_fps="" sha email date subject fp plan=""

  if [[ "$only_missing" == true ]]; then
    demo_fps=$(demo_fingerprints_in_demo "$ticket")
  fi

  while IFS=$'\037' read -r sha email date subject; do
    [[ -n "$sha" ]] || continue
    if [[ "$only_missing" == true ]]; then
      fp="$email"$'\037'"$date"$'\037'"$subject"
      printf '%s\n' "$demo_fps" | grep -Fxq -- "$fp" && continue
    fi
    plan=$(demo_list_add "$plan" "pick:$sha:$ticket")
  done < <(demo_ticket_log "$ticket" "$base" '%H%x1f%ae%x1f%at%x1f%s')

  plan=$(demo_list_add "$plan" "marker:$ticket")
  printf '%s' "$plan"
}

# Instructions qui rejouent les commits hors ticket, à la fin.
demo_plan_foreign() {
  local sha plan=""

  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    plan=$(demo_list_add "$plan" "pick:$sha:-")
  done <<< "$DEMO_FOREIGN_SHAS"
  printf '%s' "$plan"
}

# Les commits de fusion poussés à la main ne se rejouent pas commit par commit.
demo_foreign_merges() {
  local sha

  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    if [[ $(git rev-list --parents -n 1 "$sha" | wc -w) -gt 2 ]]; then
      printf '%s\n' "$sha"
    fi
  done <<< "$DEMO_FOREIGN_SHAS"
}

demo_count_picks() {
  local count=0 instr

  for instr in $1; do
    [[ "$instr" == pick:* ]] && count=$((count + 1))
  done
  printf '%s' "$count"
}

# Démarre l'opération : variables OP_* communes.
#   demo_op_begin <operation> <libellé>
demo_op_begin() {
  OP_operation="demo_$1"
  OP_target="$DEMO_PREFIX$DEMO_NAME"
  OP_name="$DEMO_NAME"
  OP_label="$2"
  OP_continue_command="jgit demo continue $DEMO_NAME"
  OP_abort_command="jgit demo abort $DEMO_NAME"
  OP_branch="$DEMO_WORK_PREFIX$DEMO_NAME"
  OP_head_before=""
  OP_done=0
  OP_total=0
  OP_segment_count=0
  OP_current_ticket=""
  # Tête détachée (agent de CI) : on reviendra sur le commit lui-même.
  if [[ "$current_branch" == "HEAD" ]]; then
    current_branch=$(git rev-parse HEAD)
  fi
  OP_return_branch="$current_branch"
  OP_on_conflict=$(jgit_conflict_mode)
  REPLAY_QUIET=true
  OP_added=""
  OP_updated=""
  OP_dropped=""
  OP_warnings=""
  OP_start=""
}

###############################################
#            Exécution du plan
###############################################

demo_commit_init() {
  local branch="$1"
  local base="$2"

  git commit --allow-empty --no-verify --quiet -m "$(demo_init_subject "$branch")" \
    -m "$trailer_branch: $branch
$trailer_based_on: $base
$trailer_demo_format: 2"
}

demo_commit_marker() {
  local ticket="$1"
  local count="$2"

  git commit --allow-empty --no-verify --quiet -m "$(demo_marker_subject "$ticket")" \
    -m "$trailer_demo_ticket: $ticket
$trailer_demo_commits: $count"
}

# Crée la branche temporaire au point de départ et s'y place.
demo_build_start() {
  local start="$1"

  git branch -D "$OP_branch" --quiet >/dev/null 2>&1
  if ! git branch "$OP_branch" "$start" >/dev/null 2>&1; then
    jgit_fail git_failed "$JGIT_EXIT_ERROR" "Impossible de créer la branche temporaire $OP_branch."
  fi
  switch_branch "$OP_branch" nosync
}

# Déroule les instructions restantes (OP_plan).
demo_execute_plan() {
  local instr rest sha ticket head_before status

  while [[ -n "$OP_plan" ]]; do
    instr="${OP_plan%% *}"
    if [[ "$OP_plan" == *" "* ]]; then
      rest="${OP_plan#* }"
    else
      rest=""
    fi

    case "$instr" in
      init:*)
        demo_commit_init "$OP_target" "${instr#init:}" || demo_build_failed "le commit d'initialisation n'a pas pu être créé"
        ;;
      marker:*)
        demo_commit_marker "${instr#marker:}" "$OP_segment_count" || demo_build_failed "le repère de ${instr#marker:} n'a pas pu être créé"
        printf "  %s✔%s %s\n" "$C_GREEN" "$C_RESET" "${instr#marker:}"
        OP_segment_count=0
        ;;
      pick:*)
        sha="${instr#pick:}"
        ticket="${sha#*:}"
        sha="${sha%%:*}"
        OP_current_ticket="$ticket"
        head_before=$(git rev-parse HEAD)

        cherry_pick "$sha"
        status=$?

        case $status in
          0)
            [[ "$(git rev-parse HEAD)" != "$head_before" ]] && OP_segment_count=$((OP_segment_count + 1))
            OP_done=$((OP_done + 1))
            ;;
          3)
            OP_head_before="$head_before"
            jgit_state_save "${DEMO_OP_STATE[@]}"
            replay_pause_exit conflict "Conflit pendant $OP_label, sur le ticket $(demo_ticket_label "$ticket")." \
              "$(demo_conflict_context)"
            ;;
          *)
            demo_build_abort
            if [[ $status -eq 2 ]]; then
              replay_report_aborted_conflict \
                "Conflit pendant $OP_label, sur le ticket $(demo_ticket_label "$ticket") : rien n'a été modifié." \
                "$(demo_conflict_context)"
              exit_safe "$JGIT_EXIT_CONFLICT"
            fi
            jgit_error_set cancelled "Opération annulée à votre demande : rien n'a été modifié."
            exit_safe 1
            ;;
        esac
        ;;
    esac

    OP_plan="$rest"
  done
}

demo_ticket_label() {
  if [[ "$1" == "-" ]]; then
    printf 'des commits ajoutés à la main'
  else
    printf '%s' "$1"
  fi
}

demo_conflict_context() {
  json_object \
    "$(json_kv_str demo "$OP_name")" \
    "$(json_kv_str_or_null ticket "$([[ "$OP_current_ticket" != "-" ]] && printf '%s' "$OP_current_ticket")")"
}

# Abandonne la fabrication : rien n'a été poussé, on revient où l'on était.
demo_build_abort() {
  git cherry-pick --abort >/dev/null 2>&1
  switch_branch "$OP_return_branch" discard
  git branch -D "$OP_branch" --quiet >/dev/null 2>&1
  jgit_state_clear
  current_branch="$OP_return_branch"
}

demo_build_failed() {
  demo_build_abort
  jgit_fail git_failed "$JGIT_EXIT_ERROR" "La fabrication de la démo a échoué : $1. Rien n'a été poussé."
}

###############################################
#            Publication
###############################################

# Publie la branche temporaire comme nouvelle version de la démo, si personne
# ne l'a modifiée sur le serveur depuis la lecture.
demo_publish() {
  local new_sha target="$OP_target"
  local local_ref="refs/heads/$target"
  local local_stale=false

  new_sha=$(git rev-parse HEAD)

  if ! git push --quiet --force-with-lease="refs/heads/$target:$OP_lease" \
         "$j2s_remote" "$OP_branch:refs/heads/$target" 2>/dev/null; then
    demo_build_abort
    if demo_remote_moved "$target" "$OP_lease"; then
      jgit_fail lease_rejected "$JGIT_EXIT_LEASE" \
        "La démo $target a été modifiée sur le serveur pendant l'opération : rien n'a été écrasé, rien n'a été poussé." \
        "Relancez la commande : elle repartira de la version actuelle."
    fi
    jgit_fail push_failed "$JGIT_EXIT_ERROR" \
      "La publication de la démo $target a échoué : rien n'a été poussé." \
      "Vérifiez votre accès au serveur puis relancez."
  fi

  git update-ref "refs/remotes/$j2s_remote/$target" "$new_sha" 2>/dev/null

  # Revenir où l'on était, sans emporter la branche temporaire.
  switch_branch "$OP_return_branch" recover
  current_branch="$OP_return_branch"

  # Une copie locale de la démo suit la nouvelle version, sauf si elle porte
  # des commits que le serveur n'avait pas : jgit ne décide pas de leur sort.
  if git show-ref --verify --quiet "$local_ref"; then
    if [[ -z "$OP_lease" || "$(git rev-parse "$local_ref")" == "$OP_lease" ]]; then
      if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$target" ]]; then
        git reset --hard --quiet "$new_sha"
      else
        git branch -f "$target" "$new_sha" >/dev/null 2>&1
      fi
    else
      local_stale=true
      OP_warnings=$(demo_list_add "$OP_warnings" "local_branch_stale:-")
      printf "%s⚠ Votre branche locale %s porte des commits absents du serveur : elle n'a pas été mise à jour.%s\n" \
        "$C_YELLOW" "$target" "$C_RESET" >&2
    fi
  fi

  git branch -D "$OP_branch" --quiet >/dev/null 2>&1
  jgit_state_clear

  printf "%sDémo %s publiée.%s\n" "$C_GREEN" "$target" "$C_RESET"
  demo_emit_result true true "$new_sha"
}

demo_remote_moved() {
  local target="$1"
  local expected="$2"
  local actual

  git fetch --quiet "$j2s_remote" "+refs/heads/$target:refs/remotes/$j2s_remote/$target" 2>/dev/null
  actual=$(git rev-parse -q --verify "refs/remotes/$j2s_remote/$target")
  [[ "$actual" != "$expected" ]]
}

# Document jgit.demo.result/1.
#   demo_emit_result <changed> <pushed> <new_sha> [dry_run]
demo_emit_result() {
  local changed="$1"
  local pushed="$2"
  local new_sha="$3"
  local dry_run="${4:-false}"
  local dropped_items=() warning_items=() item reason ticket

  for item in $OP_dropped; do
    ticket="${item%:*}"
    reason="${item##*:}"
    dropped_items[${#dropped_items[@]}]=$(json_object \
      "$(json_kv_str ticket "$ticket")" "$(json_kv_str reason "$reason")")
  done
  for item in $OP_warnings; do
    reason="${item%%:*}"
    ticket="${item#*:}"
    warning_items[${#warning_items[@]}]=$(json_object \
      "$(json_kv_str code "$reason")" \
      "$(json_kv_str_or_null ticket "$([[ "$ticket" != "-" ]] && printf '%s' "$ticket")")")
  done

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.result/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str_or_null command "$JGIT_COMMAND")" \
    "$(json_kv_str operation "${OP_operation#demo_}")" \
    "$(json_kv_str demo "$OP_name")" \
    "$(json_kv_str branch "$OP_target")" \
    "$(json_kv_bool changed "$changed")" \
    "$(json_kv_bool pushed "$pushed")" \
    "$(json_kv_bool dry_run "$dry_run")" \
    "$(json_kv_str_or_null base "$OP_base")" \
    "$(json_kv_str_or_null old_sha "$OP_old_sha")" \
    "$(json_kv_str_or_null new_sha "$new_sha")" \
    "$(json_kv added "$(json_str_array $OP_added)")" \
    "$(json_kv updated "$(json_str_array $OP_updated)")" \
    "$(json_kv dropped "$(json_array ${dropped_items[@]+"${dropped_items[@]}"})")" \
    "$(json_kv warnings "$(json_array ${warning_items[@]+"${warning_items[@]}"})")")"
}

# Résumé du plan pour l'humain, avant confirmation ou en --dry-run.
demo_print_plan() {
  local item

  for item in $OP_added; do
    printf "  %s+%s %s\n" "$C_GREEN" "$C_RESET" "$item"
  done
  for item in $OP_updated; do
    printf "  %s↻%s %s\n" "$C_YELLOW" "$C_RESET" "$item"
  done
  for item in $OP_dropped; do
    printf "  %s-%s %s (%s)\n" "$C_RED" "$C_RESET" "${item%:*}" "$(demo_drop_reason_label "${item##*:}")"
  done
}

demo_drop_reason_label() {
  case "$1" in
    requested) printf 'retiré à votre demande' ;;
    delivered) printf 'déjà livré dans %s' "$OP_base" ;;
    missing)   printf 'branche supprimée du serveur' ;;
    foreign)   printf 'commit ajouté à la main' ;;
    *)         printf '%s' "$1" ;;
  esac
}

# Rien à faire : on le dit, sans rien pousser.
demo_nothing_to_do() {
  local message="$1"

  printf "%s%s%s\n" "$C_GREEN" "$message" "$C_RESET"
  demo_emit_result false false "$OP_old_sha"
  exit_safe 0
}

# Déroule le plan préparé, puis publie. --dry-run s'arrête avant.
#   demo_run <point de départ> <question de confirmation>
demo_run() {
  local start="$1"
  local question="$2"

  OP_start="$start"
  OP_total=$(demo_count_picks "$OP_plan")

  demo_print_plan

  if [[ $JGIT_DRY_RUN == true ]]; then
    printf "\n%s--dry-run : rien n'a été modifié.%s\n" "$C_DIM" "$C_RESET"
    demo_emit_result true false "" true
    exit_safe 0
  fi

  if [[ -n "$question" ]] && ! confirm_action "$question" "y"; then
    echo "Opération annulée."
    jgit_error_set cancelled "Opération annulée : rien n'a été modifié."
    exit_safe 1
  fi

  demo_build_start "$start"
  demo_execute_plan
  demo_publish
}

###############################################
#            jgit demo create
###############################################

demo_create_cmd() {
  local name="$1"
  local based_on="$2"
  shift 2
  local tickets=("$@")
  local base provenance="reference" ticket

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  if [[ -z "$name" ]]; then
    jgit_fail usage "$JGIT_EXIT_ERROR" "Donnez un nom à la démo : jgit demo create <nom>."
  fi
  if ! demo_name_is_valid "$name"; then
    jgit_fail invalid_name "$JGIT_EXIT_REFUSED" \
      "« $name » n'est pas un nom de démo valide." \
      "Un nom de démo commence par une lettre ou un chiffre, puis lettres, chiffres, « . », « _ » ou « - » (60 caractères au plus)."
  fi
  if git show-ref --verify --quiet "refs/remotes/$j2s_remote/demo" \
     || git show-ref --verify --quiet "refs/heads/demo"; then
    jgit_fail invalid_name "$JGIT_EXIT_REFUSED" \
      "Une branche nommée « demo » existe : git ne peut pas créer de branches demo/<nom> à côté d'elle." \
      "Renommez ou supprimez la branche demo."
  fi
  if demo_remote_exists "$DEMO_PREFIX$name"; then
    jgit_fail already_exists "$JGIT_EXIT_REFUSED" \
      "La démo $DEMO_PREFIX$name existe déjà." \
      "Son contenu : jgit demo show $name — pour y ajouter des tickets : jgit demo add $name --from <ticket>"
  fi

  if [[ -n "$based_on" ]]; then
    base="$based_on"
    provenance="option"
  elif ! base=$(get_reference_branch feature); then
    exit_safe 1
  fi
  if ! ensure_base_branch "$base" "$provenance" "feature" "jgit demo create $name"; then
    jgit_error_set base_not_found "La branche de base $base n'existe pas." "jgit demo create $name --based-on <branche>"
    exit_safe "$JGIT_EXIT_REFUSED"
  fi
  if ! demo_remote_exists "$base"; then
    jgit_fail base_not_published "$JGIT_EXIT_REFUSED" \
      "La branche $base n'existe pas sur $j2s_remote : une démo part toujours de la version du serveur." \
      "git push $j2s_remote $base"
  fi

  for ticket in ${tickets[@]+"${tickets[@]}"}; do
    demo_check_ticket_source "$ticket"
  done

  DEMO_NAME="$name"
  DEMO_TICKETS=()
  DEMO_SEG_TICKET=()
  demo_op_begin create "la création de la démo $DEMO_PREFIX$name"
  OP_base="$base"
  OP_old_sha=""
  OP_lease=""
  OP_plan="init:$base"

  for ticket in ${tickets[@]+"${tickets[@]}"}; do
    demo_list_has "$OP_added" "$ticket" && continue
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_fresh_segment "$ticket" "$base")")
    OP_added=$(demo_list_add "$OP_added" "$ticket")
  done

  printf "%sJGit va créer la démo %s%s%s%s basée sur %s%s%s\n" \
    "$C_GREEN" "$C_RED" "$DEMO_PREFIX$name" "$C_RESET" "$C_GREEN" "$C_RED" "$base" "$C_RESET"
  demo_run "$(demo_remote_ref "$base")" "Souhaitez-vous continuer ?"
}

###############################################
#            jgit demo add
###############################################

demo_add_cmd() {
  local target="$1"
  shift
  local tickets=("$@")
  local ticket index

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_load_for_update "$target" "demo add"

  demo_op_begin add "l'ajout de tickets à la démo $DEMO_BRANCH"
  OP_base="$DEMO_BASE"
  OP_old_sha="$DEMO_TIP"
  OP_lease="$DEMO_TIP"
  OP_plan=""

  for ticket in "${tickets[@]}"; do
    demo_check_ticket_source "$ticket"
    if index=$(demo_ticket_index "$ticket"); then
      case "${DEMO_T_STATUS[$index]}" in
        up_to_date)
          printf "%s est déjà à jour dans la démo.\n" "$ticket"
          ;;
        ahead)
          demo_list_has "$OP_updated" "$ticket" && continue
          OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_fresh_segment "$ticket" "$DEMO_BASE" true)")
          OP_updated=$(demo_list_add "$OP_updated" "$ticket")
          ;;
        diverged)
          jgit_fail ticket_diverged "$JGIT_EXIT_REFUSED" \
            "$ticket a été réécrit depuis son ajout à la démo (squash, commit modifié) : ses commits ne s'ajoutent plus à la suite." \
            "Pour le reprendre en entier : jgit demo refresh $DEMO_NAME --from $ticket"
          ;;
      esac
      continue
    fi

    if demo_ticket_is_delivered "$ticket"; then
      jgit_fail ticket_delivered "$JGIT_EXIT_REFUSED" \
        "$ticket est déjà livré dans $DEMO_BASE : son code est déjà dans la démo." \
        "Si la démo est en retard sur $DEMO_BASE : jgit demo rebase $DEMO_NAME"
    fi
    demo_list_has "$OP_added" "$ticket" && continue
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_fresh_segment "$ticket" "$DEMO_BASE")")
    OP_added=$(demo_list_add "$OP_added" "$ticket")
  done

  if [[ -z "$OP_plan" ]]; then
    demo_nothing_to_do "La démo $DEMO_BRANCH contient déjà ces tickets à jour : rien n'a été modifié."
  fi

  # Ajouter à la suite ne réécrit rien : pas de question.
  demo_run "$DEMO_TIP" ""
}

###############################################
#            jgit demo drop / refresh
###############################################

# Reconstruit la démo à partir du premier segment concerné : ce qui précède
# est gardé tel quel, ce qui suit est rejoué depuis la démo elle-même — les
# résolutions de conflit déjà faites sont donc réutilisées.
#
#   demo_rebuild_from_segments <mode drop|refresh> <tickets…>
#
# Renseigne OP_plan et DEMO_REBUILD_START (le point de départ). Pas de
# substitution de commande : OP_plan serait perdu avec le sous-shell.
demo_rebuild_from_segments() {
  local mode="$1"
  shift
  local tickets=" $* "
  local i first=-1 start ticket refreshed=""

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    if [[ "$tickets" == *" ${DEMO_SEG_TICKET[$i]} "* ]]; then
      first=$i
      break
    fi
  done

  if [[ $first -le 0 ]]; then
    start="$DEMO_INIT"
    first=0
  else
    start="${DEMO_SEG_MARKER[$((first - 1))]}"
  fi

  OP_plan=""
  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    [[ $i -ge $first ]] || continue
    ticket="${DEMO_SEG_TICKET[$i]}"
    if [[ "$tickets" == *" $ticket "* ]]; then
      if [[ "$mode" == "refresh" ]] && ! demo_list_has "$refreshed" "$ticket"; then
        OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_fresh_segment "$ticket" "$DEMO_BASE")")
        refreshed=$(demo_list_add "$refreshed" "$ticket")
      fi
      continue
    fi
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_replay_segment "$i")")
  done
  OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_foreign)")

  DEMO_REBUILD_START="$start"
}

demo_refuse_foreign_merges() {
  local merges
  merges=$(demo_foreign_merges)
  [[ -n "$merges" ]] || return 0

  jgit_fail foreign_merge "$JGIT_EXIT_REFUSED" \
    "La démo $DEMO_BRANCH contient un commit de fusion ajouté à la main : il ne se rejoue pas commit par commit." \
    "Reportez son contenu dans un ticket, puis relancez avec --drop-foreign pour l'écarter."
}

demo_drop_cmd() {
  local target="$1"
  shift
  local tickets=("$@")
  local ticket start

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_load_for_update "$target" "demo drop"

  for ticket in "${tickets[@]}"; do
    if ! demo_ticket_index "$ticket" >/dev/null; then
      jgit_fail ticket_not_in_demo "$JGIT_EXIT_REFUSED" \
        "$ticket n'est pas dans la démo $DEMO_BRANCH : il n'y a rien à retirer." \
        "Son contenu : jgit demo show $DEMO_NAME"
    fi
  done
  if [[ $JGIT_DROP_FOREIGN != true ]]; then
    demo_refuse_foreign_merges
  fi

  demo_op_begin drop "le retrait de tickets de la démo $DEMO_BRANCH"
  OP_base="$DEMO_BASE"
  OP_old_sha="$DEMO_TIP"
  OP_lease="$DEMO_TIP"
  for ticket in "${tickets[@]}"; do
    demo_list_has "$OP_dropped" "$ticket:requested" && continue
    OP_dropped=$(demo_list_add "$OP_dropped" "$ticket:requested")
  done

  demo_rebuild_from_segments drop "${tickets[@]}"
  start="$DEMO_REBUILD_START"
  if [[ $JGIT_DROP_FOREIGN == true ]]; then
    demo_strip_foreign_from_plan
  fi

  printf "%sJGit va reconstruire la démo %s sans :%s\n" "$C_GREEN" "$DEMO_BRANCH" "$C_RESET"
  demo_run "$start" "Souhaitez-vous continuer ?"
}

demo_refresh_cmd() {
  local target="$1"
  shift
  local tickets=("$@")
  local ticket index start to_refresh=()

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_load_for_update "$target" "demo refresh"

  demo_op_begin refresh "la reprise de tickets de la démo $DEMO_BRANCH"
  OP_base="$DEMO_BASE"
  OP_old_sha="$DEMO_TIP"
  OP_lease="$DEMO_TIP"

  for ticket in "${tickets[@]}"; do
    demo_check_ticket_source "$ticket"
    if ! index=$(demo_ticket_index "$ticket"); then
      jgit_fail ticket_not_in_demo "$JGIT_EXIT_REFUSED" \
        "$ticket n'est pas dans la démo $DEMO_BRANCH." \
        "Pour l'ajouter : jgit demo add $DEMO_NAME --from $ticket"
    fi
    if [[ "${DEMO_T_STATUS[$index]}" == "up_to_date" ]]; then
      printf "%s est déjà à jour dans la démo.\n" "$ticket"
      continue
    fi
    demo_list_has "$OP_updated" "$ticket" && continue
    OP_updated=$(demo_list_add "$OP_updated" "$ticket")
    to_refresh[${#to_refresh[@]}]="$ticket"
  done

  if [[ ${#to_refresh[@]} -eq 0 ]]; then
    demo_nothing_to_do "Ces tickets sont déjà à jour dans la démo $DEMO_BRANCH : rien n'a été modifié."
  fi
  if [[ $JGIT_DROP_FOREIGN != true ]]; then
    demo_refuse_foreign_merges
  fi

  demo_rebuild_from_segments refresh "${to_refresh[@]}"
  start="$DEMO_REBUILD_START"
  if [[ $JGIT_DROP_FOREIGN == true ]]; then
    demo_strip_foreign_from_plan
  fi

  printf "%sJGit va reprendre ces tickets depuis leur branche, à leur place dans la démo %s :%s\n" \
    "$C_GREEN" "$DEMO_BRANCH" "$C_RESET"
  demo_run "$start" "Souhaitez-vous continuer ?"
}

# --drop-foreign : les commits hors ticket ne sont pas rejoués.
demo_strip_foreign_from_plan() {
  local instr plan=""

  for instr in $OP_plan; do
    [[ "$instr" == pick:*:- ]] && continue
    plan=$(demo_list_add "$plan" "$instr")
  done
  OP_plan="$plan"

  if [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]]; then
    OP_dropped=$(demo_list_add "$OP_dropped" "-:foreign")
  fi
}

###############################################
#            jgit demo rebase
###############################################

# Reconstruit la démo sur la version actuelle de sa base (ou d'une autre, avec
# --based-on). Les tickets livrés dans la base et ceux dont la branche a
# disparu sont retirés, sauf --keep-delivered / --keep-missing.
demo_rebase_cmd() {
  local target="$1"
  local based_on="$2"
  local base provenance="record" i ticket kept=0 base_ref

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_load_for_update "$target" "demo rebase"

  if [[ -n "$based_on" ]]; then
    base="$based_on"
    provenance="option"
  else
    base="$DEMO_BASE"
  fi
  if ! ensure_base_branch "$base" "$provenance" "feature" "jgit demo rebase $DEMO_NAME" "$DEMO_BRANCH"; then
    jgit_error_set base_not_found "La branche de base $base n'existe pas." "jgit demo rebase $DEMO_NAME --based-on <branche>"
    exit_safe "$JGIT_EXIT_REFUSED"
  fi
  if ! demo_remote_exists "$base"; then
    jgit_fail base_not_published "$JGIT_EXIT_REFUSED" \
      "La branche $base n'existe pas sur $j2s_remote : une démo part toujours de la version du serveur." \
      "git push $j2s_remote $base"
  fi
  if [[ $JGIT_DROP_FOREIGN != true ]]; then
    demo_refuse_foreign_merges
  fi

  # Le nouveau point de départ : livraisons de la nouvelle base.
  if [[ "$base" != "$DEMO_BASE" ]]; then
    DEMO_DELIVERED_BASE=""
    demo_delivered_cache_load "$base"
  fi

  demo_op_begin rebase "le rebase de la démo $DEMO_BRANCH sur $base"
  OP_base="$base"
  OP_old_sha="$DEMO_TIP"
  OP_lease="$DEMO_TIP"
  OP_plan="init:$base"

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    ticket="${DEMO_SEG_TICKET[$i]}"
    if [[ $JGIT_KEEP_DELIVERED != true ]] && demo_ticket_is_delivered "$ticket"; then
      demo_list_has "$OP_dropped" "$ticket:delivered" || OP_dropped=$(demo_list_add "$OP_dropped" "$ticket:delivered")
      continue
    fi
    if [[ $JGIT_KEEP_MISSING != true ]] && ! demo_remote_exists "$ticket"; then
      demo_list_has "$OP_dropped" "$ticket:missing" || OP_dropped=$(demo_list_add "$OP_dropped" "$ticket:missing")
      continue
    fi
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_replay_segment "$i")")
    kept=$((kept + 1))
  done

  if [[ $JGIT_DROP_FOREIGN == true ]]; then
    [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]] && OP_dropped=$(demo_list_add "$OP_dropped" "-:foreign")
  else
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_foreign)")
    if [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]]; then
      OP_warnings=$(demo_list_add "$OP_warnings" "foreign_commits_kept:-")
      printf "%s⚠ %s commit(s) ajouté(s) à la main sont rejoués à la fin de la démo.%s\n" \
        "$C_YELLOW" "$DEMO_FOREIGN_COUNT" "$C_RESET"
    fi
  fi
  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    if [[ "${DEMO_T_PENDING[$i]}" == true ]]; then
      OP_warnings=$(demo_list_add "$OP_warnings" "delivered_with_pending_work:${DEMO_TICKETS[$i]}")
    fi
  done

  base_ref=$(demo_remote_ref "$base")
  if [[ "$base" == "$DEMO_BASE" && "$(git rev-parse "$base_ref")" == "$(git rev-parse "$DEMO_INIT^")" \
        && -z "$OP_dropped" ]]; then
    demo_nothing_to_do "La démo $DEMO_BRANCH est déjà à jour sur $base : rien n'a été modifié."
  fi

  printf "%sJGit va reconstruire la démo %s sur la version actuelle de %s%s\n" \
    "$C_GREEN" "$DEMO_BRANCH" "$base" "$C_RESET"
  demo_run "$base_ref" "Souhaitez-vous continuer ?"
}

###############################################
#            jgit demo continue / abort
###############################################

demo_load_paused() {
  local input="$1"

  if ! jgit_state_exists; then
    jgit_fail no_operation_in_progress "$JGIT_EXIT_REFUSED" \
      "Aucune opération jgit n'est en pause dans ce dépôt : il n'y a rien à reprendre ni à annuler."
  fi

  jgit_state_load

  if [[ "$OP_operation" != demo_* ]] || [[ -n "$input" && "$input" != "$OP_name" && "$input" != "$OP_target" ]]; then
    jgit_fail operation_mismatch "$JGIT_EXIT_REFUSED" \
      "L'opération en pause n'est pas celle-ci : c'est $OP_label." \
      "$OP_continue_command   (ou : $OP_abort_command)"
  fi

  local head_branch
  head_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$head_branch" != "$OP_branch" ]]; then
    jgit_fail state_mismatch "$JGIT_EXIT_REFUSED" \
      "L'opération en pause travaille sur la branche $OP_branch, mais l'espace de travail est sur $head_branch." \
      "Revenez sur $OP_branch (git switch $OP_branch) puis relancez."
  fi

  current_branch="$OP_return_branch"
  REPLAY_QUIET=true
  if [[ -z "$JGIT_ON_CONFLICT" ]]; then
    JGIT_ON_CONFLICT="$OP_on_conflict"
  fi
}

demo_continue_cmd() {
  local input="$1"
  local instr sha status

  demo_load_paused "$input"
  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  instr="${OP_plan%% *}"
  sha="${instr#pick:}"
  sha="${sha%%:*}"
  JGIT_RESTAMP_BRANCH=""

  replay_finish_paused_pick "$OP_head_before" "$sha"
  status=$?

  case $status in
    10) replay_pause_exit unresolved_files \
          "Des fichiers sont encore en conflit : résolvez-les et marquez-les résolus (git add) avant de reprendre." \
          "$(demo_conflict_context)" ;;
    11) REPLAY_CONFLICT_LINES=$(replay_conflict_marker_lines)
        replay_pause_exit conflict_markers_left \
          "Des marqueurs de conflit (<<<<<<<, =======, >>>>>>>) sont restés dans des fichiers marqués résolus." \
          "$(demo_conflict_context)" ;;
    12) replay_pause_exit conflict \
          "git n'a pas pu terminer le cherry-pick : vérifiez l'état du dépôt (git status) avant de reprendre." \
          "$(demo_conflict_context)" ;;
  esac

  [[ "$(git rev-parse HEAD)" != "$OP_head_before" ]] && OP_segment_count=$((OP_segment_count + 1))
  OP_done=$((OP_done + 1))
  if [[ "$OP_plan" == *" "* ]]; then
    OP_plan="${OP_plan#* }"
  else
    OP_plan=""
  fi

  printf "%sConflit résolu, la démo reprend.%s\n" "$C_GREEN" "$C_RESET"
  demo_execute_plan
  demo_publish
}

demo_abort_cmd() {
  local input="$1"

  demo_load_paused "$input"
  demo_build_abort
  printf "%sL'opération sur la démo %s a été annulée : rien n'a été poussé.%s\n" "$C_GREEN" "$OP_target" "$C_RESET"
}
