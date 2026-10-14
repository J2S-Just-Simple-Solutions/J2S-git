#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"
source "$(dirname "${BASH_SOURCE[0]}")/demo_model.sh"
source "$(dirname "${BASH_SOURCE[0]}")/demo_engine.sh"
source "$(dirname "${BASH_SOURCE[0]}")/demo_lifecycle.sh"

###############################################
###############################################
#      Démos : les commandes
###############################################
###############################################
#
# Le modèle (ce qu'est une démo, comment on la lit) est dans demo_model.sh.
# Ici : ce que voit l'utilisateur, et le document --json correspondant.

###############################################
#            Fragments communs
###############################################

# Libellé humain et icône d'un état de ticket.
demo_status_label() {
  local status="$1"
  local delivered="$2"
  local missing_count="$3"
  local base="$4"

  if [[ "$delivered" == true ]]; then
    printf '%s✔ livré dans %s%s' "$C_GREEN" "$base" "$C_RESET"
    return
  fi

  case "$status" in
    up_to_date) printf '%s✔ à jour%s' "$C_GREEN" "$C_RESET" ;;
    ahead)
      if [[ "$missing_count" == "1" ]]; then
        printf '%s↻ 1 commit pas encore dans la démo%s' "$C_YELLOW" "$C_RESET"
      else
        printf '%s↻ %s commits pas encore dans la démo%s' "$C_YELLOW" "$missing_count" "$C_RESET"
      fi
      ;;
    diverged) printf '%s≠ le ticket a été réécrit depuis (squash, commit modifié)%s' "$C_YELLOW" "$C_RESET" ;;
    missing)  printf '%s✖ branche supprimée du serveur%s' "$C_RED" "$C_RESET" ;;
    *)        printf '? état inconnu (ancien format)' ;;
  esac
}

# Commande suggérée pour un ticket, ou phrase quand aucune commande n'est utile.
demo_action_hint() {
  local action="$1"
  local name="$2"
  local ticket="$3"

  case "$action" in
    add)     printf 'jgit demo add %s --from %s' "$name" "$ticket" ;;
    refresh) printf 'jgit demo refresh %s --from %s' "$name" "$ticket" ;;
    drop)    printf 'retiré au prochain « jgit demo rebase %s »' "$name" ;;
  esac
}

# Date et auteur de la dernière modification de la démo.
demo_tip_info() {
  DEMO_UPDATED_AT=""
  DEMO_UPDATED_HUMAN=""
  DEMO_UPDATED_BY=""
  [[ -n "$DEMO_TIP" ]] || return 0

  IFS=$'\037' read -r DEMO_UPDATED_AT DEMO_UPDATED_HUMAN DEMO_UPDATED_BY < <(
    git log -n 1 --date='format:%Y-%m-%d %H:%M' --format='%cI%x1f%cd%x1f%cn' "$DEMO_TIP" 2>/dev/null)
}

# Résumé d'une démo lue (demo_load), au format JSON.
demo_summary_json() {
  local read_only=false
  local paused=false

  [[ "$DEMO_KIND" != "active" ]] && read_only=true
  demo_operation_paused_on "$DEMO_BRANCH" && paused=true
  demo_tip_info

  json_object \
    "$(json_kv_str name "$DEMO_NAME")" \
    "$(json_kv_str branch "$DEMO_BRANCH")" \
    "$(json_kv_str format "$DEMO_FORMAT")" \
    "$(json_kv_bool archived "$([[ "$DEMO_KIND" == "archived" ]] && echo true)")" \
    "$(json_kv_str_or_null archived_on "$DEMO_ARCHIVED_ON")" \
    "$(json_kv_bool read_only "$read_only")" \
    "$(json_kv_str_or_null base "$DEMO_BASE")" \
    "$(json_kv_bool base_exists "$DEMO_BASE_EXISTS")" \
    "$(json_kv_num behind_base "$DEMO_BEHIND")" \
    "$(json_kv_str_or_null tip_sha "$DEMO_TIP")" \
    "$(json_kv_str_or_null updated_at "$DEMO_UPDATED_AT")" \
    "$(json_kv_str_or_null updated_by "$DEMO_UPDATED_BY")" \
    "$(json_kv_num ticket_count "${#DEMO_TICKETS[@]}")" \
    "$(json_kv_num tickets_needing_attention "$DEMO_ATTENTION")" \
    "$(json_kv_num foreign_commit_count "$DEMO_FOREIGN_COUNT")" \
    "$(json_kv_bool needs_rebase "$DEMO_NEEDS_REBASE")" \
    "$(json_kv_bool operation_in_progress "$paused")"
}

# Ticket i de la démo lue, au format JSON.
demo_ticket_json() {
  local i="$1"
  local ticket="${DEMO_TICKETS[$i]}"
  local remote_exists=false

  demo_remote_exists "$ticket" && remote_exists=true

  json_object \
    "$(json_kv_str ticket "$ticket")" \
    "$(json_kv_str type "${ticket%%/*}")" \
    "$(json_kv_str id "${ticket#*/}")" \
    "$(json_kv_num position "$((i + 1))")" \
    "$(json_kv_str status "${DEMO_T_STATUS[$i]}")" \
    "$(json_kv_bool delivered "${DEMO_T_DELIVERED[$i]}")" \
    "$(json_kv_bool delivered_with_pending_work "${DEMO_T_PENDING[$i]}")" \
    "$(json_kv_bool remote_exists "$remote_exists")" \
    "$(json_kv_num commits_in_demo "${DEMO_T_IN[$i]}")" \
    "$(json_kv_num commits_not_in_demo "${DEMO_T_MISSING[$i]}")" \
    "$(json_kv_num commits_only_in_demo "${DEMO_T_ONLY[$i]}")" \
    "$(json_kv_num segments "${DEMO_T_SEGMENTS[$i]}")" \
    "$(json_kv_str suggested_action "${DEMO_T_ACTION[$i]}")"
}

# Tickets à reprendre dans une release : ni livrés, ni disparus.
demo_release_tickets() {
  local i

  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    [[ "${DEMO_T_DELIVERED[$i]}" == true || "${DEMO_T_STATUS[$i]}" == "missing" ]] && continue
    printf '%s\n' "${DEMO_TICKETS[$i]}"
  done
}

demo_release_command() {
  local tickets ticket command="jgit release merge"

  tickets=$(demo_release_tickets)
  [[ -n "$tickets" ]] || return 0
  while IFS= read -r ticket; do
    command="$command --from $ticket"
  done <<< "$tickets"
  printf '%s' "$command"
}

# Phrase d'état d'une démo, pour la liste.
demo_state_phrase() {
  local parts=()

  if [[ "$DEMO_KIND" == "legacy" ]]; then
    printf '%s⚠ ancien format : jgit demo migrate %s%s' "$C_YELLOW" "$DEMO_NAME" "$C_RESET"
    return
  fi
  if [[ "$DEMO_BASE_EXISTS" != true ]]; then
    printf "%s✖ sa base %s n'existe plus%s" "$C_RED" "${DEMO_BASE:-?}" "$C_RESET"
    return
  fi
  if [[ "$DEMO_NEEDS_REBASE" == true ]]; then
    parts[${#parts[@]}]="en retard de $DEMO_BEHIND commit(s) sur $DEMO_BASE"
  fi
  if [[ "$DEMO_ATTENTION" -gt 0 ]]; then
    parts[${#parts[@]}]="$DEMO_ATTENTION ticket(s) à reprendre"
  fi
  if [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]]; then
    parts[${#parts[@]}]="$DEMO_FOREIGN_COUNT commit(s) ajouté(s) à la main"
  fi

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf '%s✔ à jour%s' "$C_GREEN" "$C_RESET"
  else
    local IFS='|'
    printf '%s⚠ %s%s' "$C_YELLOW" "$(printf '%s' "${parts[*]}" | sed 's/|/ · /g')" "$C_RESET"
  fi
}

###############################################
#            jgit demo list
###############################################

demo_list_cmd() {
  local scope="${1:-active}"
  local branches branch
  local items=()
  local lines=()
  local archived_count=0

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  branches=$(demo_enumerate "$scope")

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    demo_load "$branch" || continue
    items[${#items[@]}]=$(demo_summary_json)
    lines[${#lines[@]}]=$(printf '  %-24s %-12s %-11s %s' \
      "$DEMO_NAME" "${DEMO_BASE:--}" "$(demo_ticket_count_label)" "$(demo_list_state_label)")
  done <<< "$branches"

  if [[ "$scope" == "active" ]]; then
    archived_count=$(demo_count_lines "$(demo_enumerate archived)")
  fi

  case "$scope" in
    archived) printf "%sDémos archivées sur %s%s\n\n" "$C_BLUE" "$j2s_remote" "$C_RESET" ;;
    all)      printf "%sToutes les démos sur %s%s\n\n" "$C_BLUE" "$j2s_remote" "$C_RESET" ;;
    *)        printf "%sDémos sur %s%s\n\n" "$C_BLUE" "$j2s_remote" "$C_RESET" ;;
  esac

  if [[ ${#lines[@]} -eq 0 ]]; then
    printf "  Aucune démo.\n"
    printf "\nCréer une démo : jgit demo create <nom> [--from <ticket>]...\n"
  else
    printf "  %s%-24s %-12s %-11s %s%s\n" "$C_DIM" "NOM" "BASE" "TICKETS" "ETAT" "$C_RESET"
    printf "%s\n" "${lines[@]}"
    printf "\nDétail d'une démo : jgit demo show <nom>\n"
  fi

  if [[ $archived_count -gt 0 ]]; then
    printf "%s démo(s) archivée(s) : jgit demo list --archived\n" "$archived_count"
  fi

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.list/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "demo list")" \
    "$(json_kv_str remote "$j2s_remote")" \
    "$(json_kv_str scope "$scope")" \
    "$(json_kv demos "$(json_array ${items[@]+"${items[@]}"})")" \
    "$(json_kv_num archived_count "$archived_count")")"
}

demo_ticket_count_label() {
  if [[ ${#DEMO_TICKETS[@]} -eq 1 ]]; then
    printf '1 ticket'
  else
    printf '%s tickets' "${#DEMO_TICKETS[@]}"
  fi
}

demo_list_state_label() {
  if [[ "$DEMO_KIND" == "archived" ]]; then
    printf '%sarchivée le %s%s' "$C_DIM" "$DEMO_ARCHIVED_ON" "$C_RESET"
  else
    demo_state_phrase
  fi
}

###############################################
#            jgit demo show
###############################################

demo_show_cmd() {
  local target="$1"
  local i ticket hint items=() foreign_items=() sha subject author release_command

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_require_target "$target" "demo show"

  if ! demo_load "$DEMO_BRANCH"; then
    jgit_fail not_a_demo "$JGIT_EXIT_REFUSED" \
      "La branche $DEMO_BRANCH n'a pas de commit d'initialisation de démo : jgit ne sait pas la lire."
  fi
  demo_tip_info

  # --- en-tête -------------------------------------------------------------
  printf "%sDémo %s%s (%s)" "$C_BLUE" "$DEMO_NAME" "$C_RESET" "$DEMO_BRANCH"
  case "$DEMO_KIND" in
    archived) printf " — %sarchivée le %s, lecture seule%s" "$C_DIM" "$DEMO_ARCHIVED_ON" "$C_RESET" ;;
    legacy)   printf " — %sancien format, lecture seule%s" "$C_YELLOW" "$C_RESET" ;;
  esac
  printf "\n"

  if [[ "$DEMO_BASE_EXISTS" != true ]]; then
    printf "  Base         %s%s — n'existe plus sur %s%s\n" "$C_RED" "${DEMO_BASE:-inconnue}" "$j2s_remote" "$C_RESET"
  elif [[ "$DEMO_NEEDS_REBASE" == true ]]; then
    printf "  Base         %s — %sen retard de %s commit(s)%s\n" "$DEMO_BASE" "$C_YELLOW" "$DEMO_BEHIND" "$C_RESET"
  else
    printf "  Base         %s — %sà jour%s\n" "$DEMO_BASE" "$C_GREEN" "$C_RESET"
  fi
  if [[ -n "$DEMO_UPDATED_HUMAN" ]]; then
    printf "  Mise à jour  %s par %s\n" "$DEMO_UPDATED_HUMAN" "$DEMO_UPDATED_BY"
  fi

  # --- tickets ---------------------------------------------------------------
  printf "\n%sTickets%s\n" "$C_BLUE" "$C_RESET"
  if [[ ${#DEMO_TICKETS[@]} -eq 0 ]]; then
    printf "  Aucun ticket.\n"
  fi
  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    ticket="${DEMO_TICKETS[$i]}"
    printf "  %2s. %-28s %s" "$((i + 1))" "$ticket" \
      "$(demo_status_label "${DEMO_T_STATUS[$i]}" "${DEMO_T_DELIVERED[$i]}" "${DEMO_T_MISSING[$i]}" "$DEMO_BASE")"
    if [[ "$DEMO_KIND" == "active" ]]; then
      hint=$(demo_action_hint "${DEMO_T_ACTION[$i]}" "$DEMO_NAME" "$ticket")
      [[ -n "$hint" ]] && printf "\n      %s→ %s%s" "$C_DIM" "$hint" "$C_RESET"
    fi
    if [[ "${DEMO_T_PENDING[$i]}" == true ]]; then
      printf "\n      %s⚠ du code de %s n'est pas encore livré (travail après la validation de la PR)%s" \
        "$C_YELLOW" "$ticket" "$C_RESET"
    fi
    printf "\n"
    items[${#items[@]}]=$(demo_ticket_json "$i")
  done

  # --- commits ajoutés à la main ------------------------------------------
  if [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]]; then
    printf "\n%sCommits ajoutés à la main sur la démo%s (ils n'appartiennent à aucun ticket)\n" "$C_YELLOW" "$C_RESET"
  fi
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    IFS=$'\037' read -r subject author < <(git log -n 1 --format='%s%x1f%an' "$sha")
    printf "  %s %s (%s)\n" "$(git rev-parse --short "$sha")" "$subject" "$author"
    foreign_items[${#foreign_items[@]}]=$(json_object \
      "$(json_kv_str sha "$sha")" \
      "$(json_kv_str subject "$subject")" \
      "$(json_kv_str author "$author")")
  done <<< "$DEMO_FOREIGN_SHAS"

  # --- à faire -----------------------------------------------------------------
  if [[ "$DEMO_KIND" == "active" && ( "$DEMO_NEEDS_REBASE" == true || "$DEMO_FOREIGN_COUNT" -gt 0 ) ]]; then
    printf "\n%sÀ faire%s\n" "$C_BLUE" "$C_RESET"
    if [[ "$DEMO_FOREIGN_COUNT" -gt 0 ]]; then
      printf "  Les commits ajoutés à la main bloquent la reconstruction : reportez-les dans un ticket,\n"
      printf "  puis jgit demo rebase %s --drop-foreign\n" "$DEMO_NAME"
    else
      printf "  jgit demo rebase %s\n" "$DEMO_NAME"
    fi
  elif [[ "$DEMO_KIND" == "legacy" ]]; then
    printf "\n%sÀ faire%s\n  jgit demo migrate %s\n" "$C_BLUE" "$C_RESET" "$DEMO_NAME"
  fi

  release_command=$(demo_release_command)
  if [[ -n "$release_command" ]]; then
    printf "\n%sPour livrer ces tickets%s (une fois leurs PR validées)\n  %s\n" "$C_BLUE" "$C_RESET" "$release_command"
  fi

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.show/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "demo show")" \
    "$(json_kv demo "$(demo_summary_json)")" \
    "$(json_kv tickets "$(json_array ${items[@]+"${items[@]}"})")" \
    "$(json_kv foreign_commits "$(json_array ${foreign_items[@]+"${foreign_items[@]}"})")" \
    "$(json_kv_str_or_null release_command "$release_command")")"
}

###############################################
#            jgit demo candidates
###############################################

# Les tickets que l'on peut ajouter : branches feature/ et hotfix/ du serveur,
# des plus récentes aux plus anciennes, moins celles déjà dans la démo.
demo_candidates_cmd() {
  local target="$1"
  local base demo_name="" ticket date subject author known line
  local j_ticket j_type j_id j_date j_subject j_author
  local items=() fresh_lines=() delivered_lines=()

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  if [[ -n "$target" ]] || demo_parse_branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" 2>/dev/null; then
    demo_require_target "$target" "demo candidates"
    demo_load "$DEMO_BRANCH" || DEMO_TICKETS=()
    demo_name="$DEMO_NAME"
    base="$DEMO_BASE"
  else
    DEMO_TICKETS=()
    base=$(get_reference_branch feature 2>/dev/null)
  fi

  demo_delivered_cache_load "$base"

  while IFS=$'\037' read -r ticket date subject author; do
    [[ -n "$ticket" ]] || continue
    for known in ${DEMO_TICKETS[@]+"${DEMO_TICKETS[@]}"}; do
      [[ "$known" == "$ticket" ]] && continue 2
    done

    local delivered=false
    demo_ticket_is_delivered "$ticket" && delivered=true

    # Des centaines de tickets possibles : aucun sous-shell dans la boucle.
    json_str_into j_ticket "$ticket"
    json_str_into j_type "${ticket%%/*}"
    json_str_into j_id "${ticket#*/}"
    json_str_into j_date "$date"
    json_str_into j_subject "$subject"
    json_str_into j_author "$author"
    items[${#items[@]}]="{\"ticket\":$j_ticket,\"type\":$j_type,\"id\":$j_id,\"updated_at\":$j_date,\"last_subject\":$j_subject,\"author\":$j_author,\"delivered\":$delivered}"

    if [[ $delivered == true ]]; then
      printf -v line '  %-28s %s' "$ticket" "$subject"
      delivered_lines[${#delivered_lines[@]}]="$line"
    else
      printf -v line '  %-28s %s  %s' "$ticket" "${date%%T*}" "$subject"
      fresh_lines[${#fresh_lines[@]}]="$line"
    fi
  done < <(git for-each-ref --sort=-committerdate \
             --format="%(refname:strip=3)%1f%(committerdate:iso-strict)%1f%(subject)%1f%(authorname)" \
             "refs/remotes/$j2s_remote/feature" "refs/remotes/$j2s_remote/hotfix" 2>/dev/null)

  if [[ -n "$demo_name" ]]; then
    printf "%sTickets disponibles pour la démo %s%s (base %s)\n" "$C_BLUE" "$demo_name" "$C_RESET" "${base:-?}"
  else
    printf "%sTickets disponibles%s (base %s)\n" "$C_BLUE" "$C_RESET" "${base:-?}"
  fi
  if [[ ${#fresh_lines[@]} -eq 0 ]]; then
    printf "  Aucun.\n"
  else
    printf "%s\n" "${fresh_lines[@]}"
  fi
  if [[ ${#delivered_lines[@]} -gt 0 ]]; then
    printf "\n%sDéjà livrés dans %s%s (inutile de les ajouter)\n" "$C_DIM" "$base" "$C_RESET"
    printf "%s\n" "${delivered_lines[@]}"
  fi
  if [[ -n "$demo_name" && ${#fresh_lines[@]} -gt 0 ]]; then
    printf "\nAjouter : jgit demo add %s --from <ticket>\n" "$demo_name"
  fi

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.candidates/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "demo candidates")" \
    "$(json_kv_str_or_null demo "$demo_name")" \
    "$(json_kv_str_or_null base "$base")" \
    "$(json_kv candidates "$(json_array ${items[@]+"${items[@]}"})")")"
}
