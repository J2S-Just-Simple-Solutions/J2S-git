#!/bin/bash

###############################################
###############################################
#      jgit demo check : les mises à jour sont-elles faisables ?
###############################################
###############################################
#
# Simule, pour chaque démo, tout ce qui la remettrait à jour — rebase sur la
# base actuelle (tickets livrés et disparus retirés), reprise des tickets
# réécrits, ajout des nouveaux commits — et dit, sans rien modifier :
#
#   - ce qu'il y a à faire, et dans quel ordre ;
#   - si cela passe, ou quels tickets conflictent : le commit en cause et son
#     auteur, les fichiers, et en face, le dernier commit qui les a touchés,
#     son auteur et sa provenance (un autre ticket, ou la base) ;
#   - les commandes pour résoudre, ou pour retirer le ticket.
#
# Pour trouver tous les conflits et pas seulement le premier, un ticket qui
# conflicte est écarté et la simulation reprend sans lui : chaque ticket est
# ainsi jugé face à ce qui reste.
#
# La simulation se fait dans une copie de travail temporaire (git worktree),
# sous .git/jgit/check/, supprimée en sortant : ni l'espace de travail de
# l'utilisateur (même modifié), ni sa branche courante, ni le serveur ne sont
# touchés. Les commits de la simulation n'ont de branche nulle part ; git les
# oubliera.

DEMO_CHECK_WT=""

demo_check_cleanup() {
  [[ -n "$DEMO_CHECK_WT" ]] || return 0
  git -C "$DEMO_CHECK_WT" cherry-pick --abort >/dev/null 2>&1
  git worktree remove --force "$DEMO_CHECK_WT" >/dev/null 2>&1
  git worktree prune >/dev/null 2>&1
  DEMO_CHECK_WT=""
}

# git dans la copie de travail de simulation : sans hooks du projet, et avec
# une identité de circonstance (la commande ne demande pas celle du poste).
demo_check_git() {
  git -C "$DEMO_CHECK_WT" -c core.hooksPath=/dev/null \
    -c user.name="jgit" -c user.email="jgit@localhost" "$@"
}

# Place la copie de simulation sur un point de départ (la crée au besoin).
demo_check_worktree() {
  local start="$1"
  local root

  if [[ -z "$DEMO_CHECK_WT" ]]; then
    root="$(cd "$(git rev-parse --git-common-dir)" && pwd)/jgit/check"
    mkdir -p "$root" || return 1
    git worktree prune >/dev/null 2>&1
    DEMO_CHECK_WT="$root/$$"
    jgit_on_exit demo_check_cleanup
    if ! git -c core.hooksPath=/dev/null worktree add --detach --quiet "$DEMO_CHECK_WT" "$start" >/dev/null 2>&1; then
      DEMO_CHECK_WT=""
      return 1
    fi
    return 0
  fi

  demo_check_git cherry-pick --abort >/dev/null 2>&1
  demo_check_git checkout --detach --quiet --force "$start" >/dev/null 2>&1 || return 1
  demo_check_git clean -fdq >/dev/null 2>&1
}

###############################################
#            Ce qu'il y a à faire
###############################################

# Les actions qui remettraient la démo lue à jour (demo_load fait), dans
# l'ordre où les lancer. Renseigne :
#   DEMO_CHECK_REBASE  true si un rebase est nécessaire (base en retard, tickets
#                      livrés ou disparus à retirer)
#   DEMO_CHECK_REBASE_REASON
#   DEMO_CHECK_DROPS   « ticket:raison » séparés par des espaces
#   DEMO_CHECK_REFRESH tickets réécrits
#   DEMO_CHECK_ADD     tickets qui ont avancé
demo_check_needs() {
  local i ticket parts=()

  DEMO_CHECK_REBASE=false
  DEMO_CHECK_REBASE_REASON=""
  DEMO_CHECK_DROPS=""
  DEMO_CHECK_REFRESH=""
  DEMO_CHECK_ADD=""

  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    ticket="${DEMO_TICKETS[$i]}"
    if [[ "${DEMO_T_DELIVERED[$i]}" == true ]]; then
      DEMO_CHECK_DROPS=$(demo_list_add "$DEMO_CHECK_DROPS" "$ticket:delivered")
    elif [[ "${DEMO_T_STATUS[$i]}" == "missing" ]]; then
      DEMO_CHECK_DROPS=$(demo_list_add "$DEMO_CHECK_DROPS" "$ticket:missing")
    elif [[ "${DEMO_T_STATUS[$i]}" == "diverged" ]]; then
      DEMO_CHECK_REFRESH=$(demo_list_add "$DEMO_CHECK_REFRESH" "$ticket")
    elif [[ "${DEMO_T_STATUS[$i]}" == "ahead" ]]; then
      DEMO_CHECK_ADD=$(demo_list_add "$DEMO_CHECK_ADD" "$ticket")
    fi
  done

  if [[ "$DEMO_NEEDS_REBASE" == true ]]; then
    parts[${#parts[@]}]="base $DEMO_BASE en retard de $DEMO_BEHIND commit(s)"
  fi
  if [[ -n "$DEMO_CHECK_DROPS" ]]; then
    parts[${#parts[@]}]="retire $(demo_check_drop_words)"
  fi
  if [[ ${#parts[@]} -gt 0 ]]; then
    DEMO_CHECK_REBASE=true
    DEMO_CHECK_REBASE_REASON="${parts[0]}"
    [[ ${#parts[@]} -gt 1 ]] && DEMO_CHECK_REBASE_REASON="$DEMO_CHECK_REBASE_REASON ; ${parts[1]}"
  fi
}

demo_check_drop_words() {
  local item words=""

  for item in $DEMO_CHECK_DROPS; do
    case "${item##*:}" in
      delivered) words=$(demo_list_add "$words" "${item%:*} (livré)") ;;
      missing) words=$(demo_list_add "$words" "${item%:*} (branche supprimée)") ;;
    esac
  done
  printf '%s' "$words"
}

###############################################
#            Simulation
###############################################

# Commits à rejouer, une entrée « sha<US>ticket<US>étape » par commit, dans
# l'ordre où les commandes de mise à jour les poseraient.
#   demo_check_plan <tickets écartés>
demo_check_plan() {
  local excluded=" $1 "
  local i ticket sha instr refreshed=""

  DEMO_CHECK_PLAN=()

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    ticket="${DEMO_SEG_TICKET[$i]}"
    [[ "$excluded" == *" $ticket "* ]] && continue
    demo_list_has "$DEMO_CHECK_DROPS" "$ticket:delivered" && continue
    demo_list_has "$DEMO_CHECK_DROPS" "$ticket:missing" && continue

    if demo_list_has "$DEMO_CHECK_REFRESH" "$ticket"; then
      demo_list_has "$refreshed" "$ticket" && continue
      refreshed=$(demo_list_add "$refreshed" "$ticket")
      for instr in $(demo_plan_fresh_segment "$ticket" "$DEMO_BASE"); do
        [[ "$instr" == pick:* ]] || continue
        sha="${instr#pick:}"
        DEMO_CHECK_PLAN[${#DEMO_CHECK_PLAN[@]}]="${sha%%:*}"$'\037'"$ticket"$'\037'"refresh"
      done
      continue
    fi

    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      DEMO_CHECK_PLAN[${#DEMO_CHECK_PLAN[@]}]="$sha"$'\037'"$ticket"$'\037'"rebase"
    done <<< "${DEMO_SEG_SHAS[$i]}"
  done

  if [[ "$excluded" != *" - "* ]]; then
    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      DEMO_CHECK_PLAN[${#DEMO_CHECK_PLAN[@]}]="$sha"$'\037'"-"$'\037'"foreign"
    done <<< "$DEMO_FOREIGN_SHAS"
  fi

  for ticket in $DEMO_CHECK_ADD; do
    [[ "$excluded" == *" $ticket "* ]] && continue
    for instr in $(demo_plan_fresh_segment "$ticket" "$DEMO_BASE" true); do
      [[ "$instr" == pick:* ]] || continue
      sha="${instr#pick:}"
      DEMO_CHECK_PLAN[${#DEMO_CHECK_PLAN[@]}]="${sha%%:*}"$'\037'"$ticket"$'\037'"add"
    done
  done
}

# Rejoue le plan depuis un point de départ. Code 0 : tout passe ; 1 : conflit
# (DEMO_CHECK_C_* renseignés) ; 2 : la simulation n'a pas pu se faire.
demo_check_run() {
  local start="$1"
  local entry sha ticket step new map=""

  demo_check_worktree "$start" || return 2

  for entry in ${DEMO_CHECK_PLAN[@]+"${DEMO_CHECK_PLAN[@]}"}; do
    IFS=$'\037' read -r sha ticket step <<< "$entry"
    if demo_check_git cherry-pick --allow-empty --keep-redundant-commits "$sha" >/dev/null 2>&1; then
      new=$(demo_check_git rev-parse HEAD)
      map="$map$new $ticket"$'\n'
      continue
    fi

    DEMO_CHECK_C_TICKET="$ticket"
    DEMO_CHECK_C_STEP="$step"
    DEMO_CHECK_C_SHA="$sha"
    DEMO_CHECK_C_LINES=$(replay_conflict_lines "$DEMO_CHECK_WT")
    demo_check_other_side "$map"
    demo_check_git cherry-pick --abort >/dev/null 2>&1
    return 1
  done

  return 0
}

# Pour chaque fichier en conflit : le dernier commit qui l'a touché du côté de
# la démo en cours de reconstruction, et d'où il vient (un ticket, ou la base).
# Renseigne DEMO_CHECK_C_OTHERS : une ligne « chemin<US>sha<US>auteur<US>email<US>sujet<US>provenance ».
demo_check_other_side() {
  local map="$1"
  local line path info sha author email subject origin

  DEMO_CHECK_C_OTHERS=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"
    info=$(demo_check_git log -n 1 --format='%H%x1f%an%x1f%ae%x1f%s' HEAD -- "$path" 2>/dev/null)
    if [[ -z "$info" ]]; then
      DEMO_CHECK_C_OTHERS="$DEMO_CHECK_C_OTHERS$path"$'\n'
      continue
    fi
    IFS=$'\037' read -r sha author email subject <<< "$info"
    origin=$(demo_check_origin_of "$sha" "$map")
    DEMO_CHECK_C_OTHERS="$DEMO_CHECK_C_OTHERS$path"$'\037'"$sha"$'\037'"$author"$'\037'"$email"$'\037'"$subject"$'\037'"$origin"$'\n'
  done <<< "$DEMO_CHECK_C_LINES"
}

# D'où vient un commit de la démo en cours de reconstruction : un ticket
# (commit rejoué par la simulation, ou déjà dans la démo quand on ne fait
# qu'ajouter à la suite), un commit ajouté à la main, ou la base.
demo_check_origin_of() {
  local sha="$1"
  local map="$2"
  local origin i

  origin=$(printf '%s' "$map" | sed -n "s/^$sha //p" | head -n 1)
  if [[ -z "$origin" ]]; then
    for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
      if [[ $'\n'"${DEMO_SEG_SHAS[$i]}" == *$'\n'"$sha"$'\n'* ]]; then
        origin="${DEMO_SEG_TICKET[$i]}"
        break
      fi
    done
  fi
  if [[ -z "$origin" && $'\n'"$DEMO_FOREIGN_SHAS" == *$'\n'"$sha"$'\n'* ]]; then
    origin="-"
  fi

  case "$origin" in
    "") printf '%s' "$DEMO_BASE" ;;
    -) printf 'commit ajouté à la main' ;;
    *) printf '%s' "$origin" ;;
  esac
}

###############################################
#            Une démo
###############################################

# Commande qui ferait l'étape où un conflit apparaît.
demo_check_step_command() {
  local step="$1"
  local ticket="$2"

  case "$step" in
    refresh) printf 'jgit demo refresh %s --from %s' "$DEMO_NAME" "$ticket" ;;
    add) printf 'jgit demo add %s --from %s' "$DEMO_NAME" "$ticket" ;;
    *) printf 'jgit demo rebase %s' "$DEMO_NAME" ;;
  esac
}

# Vérifie la démo lue. Renseigne DEMO_CHECK_STATUS (up_to_date, feasible,
# conflicts, blocked), DEMO_CHECK_ITEM (objet JSON) et affiche le rapport.
demo_check_one() {
  local start excluded="" iterations=0 rc
  local conflicts_json=() dropped_json=()
  local conflict_steps="" conflict_tickets="" item ticket command

  DEMO_CHECK_STATUS="up_to_date"
  DEMO_CHECK_MESSAGE=""

  printf "\n%s%s%s  (base %s)\n" "$C_BOLD" "$DEMO_BRANCH" "$C_RESET" "${DEMO_BASE:-?}"

  if [[ "$DEMO_BASE_EXISTS" != true ]]; then
    DEMO_CHECK_STATUS="blocked"
    DEMO_CHECK_MESSAGE="Sa base ${DEMO_BASE:-?} n'existe plus : il faut la rebaser ailleurs (jgit demo rebase $DEMO_NAME --based-on <branche>)."
  elif [[ -n "$(demo_foreign_merges)" ]]; then
    DEMO_CHECK_STATUS="blocked"
    DEMO_CHECK_MESSAGE="Un commit de fusion a été poussé à la main sur la démo : il ne se rejoue pas (jgit demo rebase $DEMO_NAME --drop-foreign pour l'écarter)."
  fi

  if [[ "$DEMO_CHECK_STATUS" == "blocked" ]]; then
    printf "  %s✖ %s%s\n" "$C_RED" "$DEMO_CHECK_MESSAGE" "$C_RESET"
    demo_check_item "[]" "[]" "[]"
    return
  fi

  demo_check_needs

  if [[ "$DEMO_CHECK_REBASE" != true && -z "$DEMO_CHECK_REFRESH$DEMO_CHECK_ADD" ]]; then
    printf "  %s✔ À jour, rien à faire.%s\n" "$C_GREEN" "$C_RESET"
    demo_check_item "[]" "[]" "[]"
    return
  fi

  # Un rebase ou une reprise reconstruit depuis la base ; un simple ajout
  # pose les nouveaux commits au bout de la démo.
  if [[ "$DEMO_CHECK_REBASE" == true ]]; then
    start=$(demo_remote_ref "$DEMO_BASE")
  elif [[ -n "$DEMO_CHECK_REFRESH" ]]; then
    start=$(git rev-parse "$DEMO_INIT^")
  else
    start="$DEMO_TIP"
  fi

  while :; do
    demo_check_plan "$excluded"
    demo_check_run "$start"
    rc=$?
    [[ $rc -eq 0 ]] && break
    if [[ $rc -eq 2 ]]; then
      DEMO_CHECK_STATUS="blocked"
      DEMO_CHECK_MESSAGE="La simulation n'a pas pu se faire (copie de travail temporaire impossible)."
      printf "  %s✖ %s%s\n" "$C_RED" "$DEMO_CHECK_MESSAGE" "$C_RESET"
      demo_check_item "[]" "[]" "[]"
      return
    fi

    DEMO_CHECK_STATUS="conflicts"
    conflict_steps=$(demo_list_add "$conflict_steps" "$DEMO_CHECK_C_STEP")
    conflict_tickets=$(demo_list_add "$conflict_tickets" "$DEMO_CHECK_C_TICKET")
    demo_check_report_conflict
    conflicts_json[${#conflicts_json[@]}]="$DEMO_CHECK_C_JSON"

    excluded=$(demo_list_add "$excluded" "$DEMO_CHECK_C_TICKET")
    iterations=$((iterations + 1))
    [[ $iterations -gt $(( ${#DEMO_TICKETS[@]} + 1 )) ]] && break
  done

  # --- les actions, dans l'ordre -----------------------------------------------
  if [[ "$DEMO_CHECK_STATUS" == "up_to_date" ]]; then
    DEMO_CHECK_STATUS="feasible"
    printf "  %s✔ Mise à jour faisable sans conflit :%s\n" "$C_GREEN" "$C_RESET"
  else
    printf "  Pour la remettre à jour, dans l'ordre :\n"
  fi

  if [[ "$DEMO_CHECK_REBASE" == true ]]; then
    command="jgit demo rebase $DEMO_NAME"
    if demo_list_has "$conflict_steps" rebase || demo_list_has "$conflict_steps" foreign; then
      command="$command --on-conflict pause"
    fi
    demo_check_action "$command" "$DEMO_CHECK_REBASE_REASON"
  fi
  for ticket in $DEMO_CHECK_REFRESH; do
    command="jgit demo refresh $DEMO_NAME --from $ticket"
    demo_list_has "$conflict_tickets" "$ticket" && command="$command --on-conflict pause"
    demo_check_action "$command" "$ticket a été réécrit depuis son ajout"
  done
  for ticket in $DEMO_CHECK_ADD; do
    command="jgit demo add $DEMO_NAME --from $ticket"
    demo_list_has "$conflict_tickets" "$ticket" && command="$command --on-conflict pause"
    demo_check_action "$command" "$ticket a de nouveaux commits"
  done

  for item in $DEMO_CHECK_DROPS; do
    dropped_json[${#dropped_json[@]}]=$(json_object \
      "$(json_kv_str ticket "${item%:*}")" "$(json_kv_str reason "${item##*:}")")
  done

  demo_check_item \
    "$(json_array ${DEMO_CHECK_ACTIONS_JSON[@]+"${DEMO_CHECK_ACTIONS_JSON[@]}"})" \
    "$(json_array ${dropped_json[@]+"${dropped_json[@]}"})" \
    "$(json_array ${conflicts_json[@]+"${conflicts_json[@]}"})"
}

DEMO_CHECK_ACTIONS_JSON=()

demo_check_action() {
  local command="$1"
  local reason="$2"

  printf "      %s%s%s\n        %s%s%s\n" "$C_CYAN" "$command" "$C_RESET" "$C_DIM" "$reason" "$C_RESET"
  DEMO_CHECK_ACTIONS_JSON[${#DEMO_CHECK_ACTIONS_JSON[@]}]=$(json_object \
    "$(json_kv_str command "$command")" "$(json_kv_str reason "$reason")")
}

# Affiche un conflit et en prépare l'objet JSON (DEMO_CHECK_C_JSON).
demo_check_report_conflict() {
  local ticket="$DEMO_CHECK_C_TICKET"
  local step="$DEMO_CHECK_C_STEP"
  local info c_subject c_author c_email c_date
  local line path code kind other sha author email subject origin
  local files_json=() resolve drop label

  info=$(git log -n 1 --format='%s%x1f%an%x1f%ae%x1f%ad' --date=short "$DEMO_CHECK_C_SHA" 2>/dev/null)
  IFS=$'\037' read -r c_subject c_author c_email c_date <<< "$info"

  resolve="$(demo_check_step_command "$step" "$ticket") --on-conflict pause"
  if [[ "$ticket" == "-" ]]; then
    label="des commits ajoutés à la main"
    drop="jgit demo rebase $DEMO_NAME --drop-foreign"
  else
    label="$ticket"
    drop="jgit demo drop $DEMO_NAME --from $ticket"
  fi

  printf "  %s✖ Conflit : %s%s (%s)\n" "$C_RED" "$label" "$C_RESET" "$(demo_check_step_label "$step")"
  printf "      commit %s « %s »\n" "$(git rev-parse --short "$DEMO_CHECK_C_SHA" 2>/dev/null)" "$c_subject"
  printf "      par %s <%s>, le %s\n" "$c_author" "$c_email" "$c_date"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    code="${line:0:2}"
    path="${line:3}"
    kind=$(replay_conflict_kind "$code")
    other=$(printf '%s\n' "$DEMO_CHECK_C_OTHERS" | awk -F '\037' -v p="$path" '$1 == p { print; exit }')
    printf "      %s (%s)\n" "$path" "$(replay_conflict_kind_label "$code")"

    if [[ "$other" == *$'\037'* ]]; then
      IFS=$'\037' read -r path sha author email subject origin <<< "$other"
      printf "        en face : %s « %s » par %s <%s> (%s)\n" "${sha:0:7}" "$subject" "$author" "$email" "$origin"
      files_json[${#files_json[@]}]=$(json_object \
        "$(json_kv_str path "$path")" \
        "$(json_kv_str kind "$kind")" \
        "$(json_kv other "$(json_object \
            "$(json_kv_str sha "$sha")" \
            "$(json_kv_str subject "$subject")" \
            "$(json_kv_str author "$author")" \
            "$(json_kv_str email "$email")" \
            "$(json_kv_str origin "$origin")")")")
    else
      files_json[${#files_json[@]}]=$(json_object \
        "$(json_kv_str path "$path")" \
        "$(json_kv_str kind "$kind")" \
        "$(json_kv_null other)")
    fi
  done <<< "$DEMO_CHECK_C_LINES"

  printf "      → résoudre : %s\n" "$resolve"
  printf "      → ou retirer : %s\n" "$drop"

  DEMO_CHECK_C_JSON=$(json_object \
    "$(json_kv_str ticket "$ticket")" \
    "$(json_kv_str step "$step")" \
    "$(json_kv commit "$(json_object \
        "$(json_kv_str sha "$DEMO_CHECK_C_SHA")" \
        "$(json_kv_str subject "$c_subject")" \
        "$(json_kv_str author "$c_author")" \
        "$(json_kv_str email "$c_email")" \
        "$(json_kv_str date "$c_date")")")" \
    "$(json_kv files "$(json_array ${files_json[@]+"${files_json[@]}"})")" \
    "$(json_kv commands "$(json_object \
        "$(json_kv_str resolve "$resolve")" \
        "$(json_kv_str drop "$drop")")")")
}

demo_check_step_label() {
  case "$1" in
    rebase) printf 'au rebase sur la base à jour' ;;
    refresh) printf 'à la reprise du ticket' ;;
    add) printf "à l'ajout de ses nouveaux commits" ;;
    foreign) printf 'au rebase sur la base à jour' ;;
  esac
}

# Objet JSON d'une démo vérifiée (DEMO_CHECK_ITEM).
demo_check_item() {
  DEMO_CHECK_ITEM=$(json_object \
    "$(json_kv_str name "$DEMO_NAME")" \
    "$(json_kv_str branch "$DEMO_BRANCH")" \
    "$(json_kv_str_or_null base "$DEMO_BASE")" \
    "$(json_kv_num behind_base "$DEMO_BEHIND")" \
    "$(json_kv_str status "$DEMO_CHECK_STATUS")" \
    "$(json_kv_str_or_null message "$DEMO_CHECK_MESSAGE")" \
    "$(json_kv actions "$1")" \
    "$(json_kv dropped "$2")" \
    "$(json_kv conflicts "$3")")
}

###############################################
#            jgit demo check
###############################################

demo_check_cmd() {
  local target="$1"
  local branches branch items=() skipped=0
  local total=0 up=0 feasible=0 conflicted=0 blocked=0

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  if [[ -n "$target" ]]; then
    demo_require_target "$target" "demo check"
    if [[ "$DEMO_KIND" != "active" ]]; then
      jgit_fail read_only "$JGIT_EXIT_REFUSED" \
        "La démo $DEMO_BRANCH est en lecture seule ($( [[ "$DEMO_KIND" == archived ]] && echo archivée || echo ancien format)) : il n'y a pas de mise à jour à vérifier."
    fi
    branches="$DEMO_BRANCH"
  else
    branches=$(demo_enumerate active | grep "^$DEMO_PREFIX")
    skipped=$(demo_count_lines "$(demo_enumerate active | grep "^$DEMO_LEGACY_PREFIX")")
  fi

  printf "%sVérification des démos sur %s%s — simulation : rien n'est modifié.\n" "$C_BLUE" "$j2s_remote" "$C_RESET"

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    demo_load "$branch" || continue
    DEMO_CHECK_ACTIONS_JSON=()
    demo_check_one
    items[${#items[@]}]="$DEMO_CHECK_ITEM"
    total=$((total + 1))
    case "$DEMO_CHECK_STATUS" in
      up_to_date) up=$((up + 1)) ;;
      feasible) feasible=$((feasible + 1)) ;;
      conflicts) conflicted=$((conflicted + 1)) ;;
      blocked) blocked=$((blocked + 1)) ;;
    esac
  done <<< "$branches"

  demo_check_cleanup

  if [[ $total -eq 0 ]]; then
    printf "\nAucune démo à vérifier.\n"
  fi
  printf "\nBilan : %s démo(s) — %s à jour, %s faisable(s), %s en conflit, %s bloquée(s).\n" \
    "$total" "$up" "$feasible" "$conflicted" "$blocked"
  if [[ $skipped -gt 0 ]]; then
    printf "%s démo(s) à l'ancien format non vérifiée(s) : jgit demo migrate <nom>.\n" "$skipped"
  fi

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.check/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "demo check")" \
    "$(json_kv demos "$(json_array ${items[@]+"${items[@]}"})")" \
    "$(json_kv summary "$(json_object \
        "$(json_kv_num demos "$total")" \
        "$(json_kv_num up_to_date "$up")" \
        "$(json_kv_num feasible "$feasible")" \
        "$(json_kv_num conflicts "$conflicted")" \
        "$(json_kv_num blocked "$blocked")" \
        "$(json_kv_num skipped_legacy "$skipped")")")")"

  # Un conflit ou un blocage prévu se lit aussi au code de sortie : un job
  # planifié peut s'arrêter dessus sans lire le rapport.
  if [[ $conflicted -gt 0 || $blocked -gt 0 ]]; then
    exit "$JGIT_EXIT_CONFLICT"
  fi
}
