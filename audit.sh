#!/bin/bash

###############################################
###############################################
#      jgit audit : l'état des lieux des tickets et des démos
###############################################
###############################################
#
#   jgit audit                   tous les tickets du serveur, puis toutes les démos
#   jgit audit tickets           les tickets seulement
#   jgit audit demos [<nom>]     les démos (et les tickets qu'elles contiennent)
#
# Rien n'est modifié : tout est simulé.
#
# Pour chaque TICKET (branche feature/… ou hotfix/… du serveur) :
#   - est-il à jour sur sa propre base, celle enregistrée à sa création ?
#   - sinon, son rebase passerait-il ? S'il coince : le commit en cause et son
#     auteur, les fichiers, et en face le commit de la base et son auteur ;
#   - son propriétaire, sa dernière activité, sa PR, les démos qui le contiennent.
#
# Pour chaque DÉMO, dans l'ordre où il faut faire les choses :
#   1. d'abord rebaser, chez eux, ses tickets en retard sur leur base
#      (jgit feature rebase) : c'est là que leurs conflits avec la base se
#      résolvent, par leur auteur ;
#   2. puis remettre la démo à jour : rebase sur sa base, en reprenant depuis
#      leur branche les tickets rebasés ou réécrits (--from), puis ajout des
#      nouveaux commits. Les conflits qui restent sont ceux entre tickets, ou
#      entre un ticket à jour et la démo : ils se résolvent dans la démo.
#
# Un ticket en conflit est écarté et la simulation reprend sans lui : tous les
# tickets fautifs sont signalés, pas seulement le premier.
#
# Le rebase d'un ticket se juge par git merge-tree (git 2.38), sans copie de
# travail ; celui d'une démo se rejoue commit par commit dans une copie de
# travail temporaire (git worktree), sous .git/jgit/audit/, supprimée en
# sortant : ni l'espace de travail de l'utilisateur (même modifié), ni sa
# branche courante, ni le serveur ne sont touchés. Les commits de simulation
# n'ont de branche nulle part ; git les oubliera. C'est l'exception assumée à
# la règle « un seul git checkout » (choix technique n°17).

AUDIT_WT=""

###############################################
#            Copie de travail de simulation
###############################################

audit_cleanup() {
  [[ -n "$AUDIT_WT" ]] || return 0
  git -C "$AUDIT_WT" cherry-pick --abort >/dev/null 2>&1
  git worktree remove --force "$AUDIT_WT" >/dev/null 2>&1
  git worktree prune >/dev/null 2>&1
  AUDIT_WT=""
}

# git dans la copie de simulation : sans hooks du projet, et avec une identité
# de circonstance (l'audit ne demande pas celle du poste).
audit_git() {
  git -C "$AUDIT_WT" -c core.hooksPath=/dev/null \
    -c user.name="jgit" -c user.email="jgit@localhost" "$@"
}

# Place la copie de simulation sur un point de départ (la crée au besoin).
audit_worktree() {
  local start="$1"
  local root

  if [[ -z "$AUDIT_WT" ]]; then
    root="$(cd "$(git rev-parse --git-common-dir)" && pwd)/jgit/audit"
    mkdir -p "$root" || return 1
    git worktree prune >/dev/null 2>&1
    AUDIT_WT="$root/$$"
    jgit_on_exit audit_cleanup
    if ! git -c core.hooksPath=/dev/null worktree add --detach --quiet "$AUDIT_WT" "$start" >/dev/null 2>&1; then
      AUDIT_WT=""
      return 1
    fi
    return 0
  fi

  audit_git cherry-pick --abort >/dev/null 2>&1
  audit_git checkout --detach --quiet --force "$start" >/dev/null 2>&1 || return 1
  audit_git clean -fdq >/dev/null 2>&1
}

# Rejoue une liste d'entrées « sha<US>ticket<US>étape » depuis un point de
# départ. Code 0 : tout passe ; 1 : conflit (AUDIT_C_* renseignés) ; 2 : la
# simulation n'a pas pu se faire.
#
# provenance_cb : fonction qui dit d'où vient un commit de la copie (pour le
# « en face » d'un conflit), appelée avec le sha et la table des commits rejoués.
audit_replay() {
  local start="$1"
  local provenance_cb="$2"
  local entry sha ticket step new map=""

  audit_worktree "$start" || return 2

  for entry in ${AUDIT_PLAN[@]+"${AUDIT_PLAN[@]}"}; do
    IFS=$'\037' read -r sha ticket step <<< "$entry"
    if audit_git cherry-pick --allow-empty --keep-redundant-commits "$sha" >/dev/null 2>&1; then
      new=$(audit_git rev-parse HEAD)
      map="$map$new $ticket"$'\n'
      continue
    fi

    AUDIT_C_TICKET="$ticket"
    AUDIT_C_STEP="$step"
    AUDIT_C_SHA="$sha"
    AUDIT_C_LINES=$(replay_conflict_lines "$AUDIT_WT")
    audit_other_side "$map" "$provenance_cb"
    audit_git cherry-pick --abort >/dev/null 2>&1
    return 1
  done

  return 0
}

# Pour chaque fichier en conflit : le dernier commit qui l'a touché dans la
# copie, et d'où il vient. AUDIT_C_OTHERS : une ligne par fichier,
# « chemin<US>sha<US>auteur<US>email<US>sujet<US>provenance ».
audit_other_side() {
  local map="$1"
  local provenance_cb="$2"
  local line path info sha author email subject origin

  AUDIT_C_OTHERS=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"
    info=$(audit_git log -n 1 --format='%H%x1f%an%x1f%ae%x1f%s' HEAD -- "$path" 2>/dev/null)
    if [[ -z "$info" ]]; then
      AUDIT_C_OTHERS="$AUDIT_C_OTHERS$path"$'\n'
      continue
    fi
    IFS=$'\037' read -r sha author email subject <<< "$info"
    origin=$("$provenance_cb" "$sha" "$map")
    AUDIT_C_OTHERS="$AUDIT_C_OTHERS$path"$'\037'"$sha"$'\037'"$author"$'\037'"$email"$'\037'"$subject"$'\037'"$origin"$'\n'
  done <<< "$AUDIT_C_LINES"
}

# Le conflit courant, mis en forme : AUDIT_C_REPORT (texte, chaque ligne
# précédée de $1), AUDIT_C_COMMIT_JSON et AUDIT_C_FILES_JSON. Rien n'est
# affiché ici : l'appelant décide où le rapport va.
audit_conflict_report() {
  local indent="$1"
  local info c_subject c_author c_email c_date text
  local line code path kind other sha author email subject origin
  local files_json=()

  info=$(git log -n 1 --format='%s%x1f%an%x1f%ae%x1f%ad' --date=short "$AUDIT_C_SHA" 2>/dev/null)
  IFS=$'\037' read -r c_subject c_author c_email c_date <<< "$info"

  printf -v text '%scommit %s « %s »\n%spar %s <%s>, le %s\n' \
    "$indent" "${AUDIT_C_SHA:0:7}" "$c_subject" "$indent" "$c_author" "$c_email" "$c_date"
  AUDIT_C_REPORT="$text"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    code="${line:0:2}"
    path="${line:3}"
    kind=$(replay_conflict_kind "$code")
    other=$(printf '%s\n' "$AUDIT_C_OTHERS" | awk -F '\037' -v p="$path" '$1 == p { print; exit }')
    printf -v text '%s%s (%s)\n' "$indent" "$path" "$(replay_conflict_kind_label "$code")"
    AUDIT_C_REPORT="$AUDIT_C_REPORT$text"

    if [[ "$other" == *$'\037'* ]]; then
      IFS=$'\037' read -r path sha author email subject origin <<< "$other"
      printf -v text '%s  en face : %s « %s » par %s <%s> (%s)\n' \
        "$indent" "${sha:0:7}" "$subject" "$author" "$email" "$origin"
      AUDIT_C_REPORT="$AUDIT_C_REPORT$text"
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
        "$(json_kv_str path "$path")" "$(json_kv_str kind "$kind")" "$(json_kv_null other)")
    fi
  done <<< "$AUDIT_C_LINES"

  AUDIT_C_COMMIT_JSON=$(json_object \
    "$(json_kv_str sha "$AUDIT_C_SHA")" \
    "$(json_kv_str subject "$c_subject")" \
    "$(json_kv_str author "$c_author")" \
    "$(json_kv_str email "$c_email")" \
    "$(json_kv_str date "$c_date")")
  AUDIT_C_FILES_JSON=$(json_array ${files_json[@]+"${files_json[@]}"})
}

# Progression, seulement face à un terminal : un audit de centaines de
# tickets prend quelques dizaines de secondes.
audit_progress() {
  [[ -t 2 ]] || return 0
  printf "\r  %s %s/%s…   " "$1" "$2" "$3" >&2
}

audit_progress_end() {
  [[ -t 2 ]] || return 0
  printf "\r%60s\r" "" >&2
}

###############################################
#            Tickets
###############################################
#
# Un ticket n'est évalué qu'une fois, même s'il est dans plusieurs démos.
# Tables parallèles (bash 3.2 n'a pas de tableaux associatifs), indexées par
# audit_ticket_index.

AUDIT_T_NAME=()
AUDIT_T_STATUS=()      # up_to_date | to_rebase | conflicts | delivered | base_missing
AUDIT_T_BASE=()
AUDIT_T_BEHIND=()
AUDIT_T_COMMAND=()
AUDIT_T_OWNER=()
AUDIT_T_JSON_PART=()   # champs JSON calculés à l'évaluation (hors « demos »)
AUDIT_T_REPORT=()      # rapport humain du conflit, s'il y en a un
AUDIT_T_DEMOS=()       # démos qui contiennent le ticket, séparées par des espaces

# Index d'un ticket dans les tables, dans AUDIT_I (code 1 s'il n'y est pas).
# Sans sous-shell : sous macOS, chaque processus coûte, et il y a des
# centaines de tickets.
audit_ticket_index() {
  local i

  for i in ${AUDIT_T_NAME[@]+"${!AUDIT_T_NAME[@]}"}; do
    if [[ "${AUDIT_T_NAME[$i]}" == "$1" ]]; then
      AUDIT_I="$i"
      return 0
    fi
  done
  return 1
}

# Inscrit un ticket dans les tables (sans l'évaluer) ; AUDIT_I reçoit son index.
# Avec « new », le ticket est inscrit sans chercher s'il l'est déjà.
audit_ticket_register() {
  local ticket="$1"

  [[ "$2" == "new" ]] || ! audit_ticket_index "$ticket" || return 0
  AUDIT_I=${#AUDIT_T_NAME[@]}
  AUDIT_T_NAME[$AUDIT_I]="$ticket"
  AUDIT_T_STATUS[$AUDIT_I]=""
  AUDIT_T_DEMOS[$AUDIT_I]=""
}

# Note qu'une démo contient un ticket.
audit_ticket_in_demo() {
  local ticket="$1"
  local demo="$2"

  audit_ticket_register "$ticket"
  [[ -n "$demo" ]] || return 0
  demo_list_has "${AUDIT_T_DEMOS[$AUDIT_I]}" "$demo" \
    || AUDIT_T_DEMOS[$AUDIT_I]="${AUDIT_T_DEMOS[$AUDIT_I]:+${AUDIT_T_DEMOS[$AUDIT_I]} }$demo"
}

audit_ticket_provenance() {
  printf '%s' "$AUDIT_TICKET_BASE"
}

# Lectures groupées, une fois pour tous les tickets : un appel à git par
# ticket et par information coûterait des dizaines de secondes sur un projet
# de centaines de branches. AUDIT_P_NAME[k] / AUDIT_P_DATA[k] : les tickets du
# serveur, du plus récemment modifié au plus ancien, et pour chacun
# « base<US>auteur<US>email<US>date<US>sujet de sa PR ». Des tableaux, pas
# une longue chaîne : bash 3.2 met un temps quadratique à y extraire une valeur.
AUDIT_P_NAME=()
AUDIT_P_DATA=()
AUDIT_REMOTE_REFS=""
AUDIT_MERGE_TREE=""
AUDIT_REF_FEATURE=""
AUDIT_REF_HOTFIX=""
AUDIT_DC_BASES=()      # caches « livré » par base (voir audit_delivered)
AUDIT_DC_TICKETS=()

# La table des tickets du serveur, une ligne par ticket :
# « ticket<US>base<US>auteur<US>email<US>date<US>sujet de sa PR ». Trois
# lectures, jointes par awk :
#   B  sa base : le trailer jgit-based-on du commit d'init le plus récent qui
#      nomme la branche (jgit-branch), comme read_based_on ;
#   P  le sujet du dernier commit de sa branche de PR ;
#   T  les tickets, du plus récemment modifié au plus ancien.
audit_tickets_table() {
  local remote="refs/remotes/$j2s_remote"

  {
    git log --format="B%x09%(trailers:key=$trailer_branch,valueonly,separator=%x2C)%x09%(trailers:key=$trailer_based_on,valueonly,separator=%x2C)" \
        --basic-regexp --grep="^$trailer_branch: " \
        $(git for-each-ref --format='%(refname)' "$remote/feature" "$remote/hotfix") 2>/dev/null
    git for-each-ref --format='P%09%(refname:strip=3)%09%(subject)' "$remote" 2>/dev/null \
      | sed -n "s#^P	$prefix_PR#P	#p"
    git for-each-ref --sort=-committerdate \
        --format='T%09%(refname:strip=3)%09%(authorname)%09%(authoremail:trim)%09%(committerdate:iso-strict)' \
        "$remote/feature" "$remote/hotfix" 2>/dev/null
  } | awk -F '\t' '
    $1 == "B" && $2 != "" && !($2 in base) { n = split($3, b, ","); base[$2] = b[n]; next }
    $1 == "P" { pr[$2] = $3; next }
    $1 == "T" { printf "%s\037%s\037%s\037%s\037%s\037%s\n", $2, base[$2], $3, $4, $5, pr[$2] }'
}

audit_tickets_preload() {
  local line k=0

  AUDIT_P_NAME=()
  AUDIT_P_DATA=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    AUDIT_P_NAME[$k]="${line%%$'\037'*}"
    AUDIT_P_DATA[$k]="${line#*$'\037'}"
    k=$((k + 1))
  done < <(audit_tickets_table)

  # Les branches du serveur, pour savoir sans git si une base existe.
  AUDIT_REMOTE_REFS=$'\n'$(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$j2s_remote" 2>/dev/null)$'\n'

  AUDIT_REF_FEATURE=$(get_reference_branch feature 2>/dev/null)
  AUDIT_REF_HOTFIX=$(get_reference_branch hotfix 2>/dev/null)

  # git merge-tree --write-tree (git 2.38) simule une fusion sans copie de
  # travail : bien plus rapide que de rejouer chaque ticket.
  if git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
    AUDIT_MERGE_TREE=true
  else
    AUDIT_MERGE_TREE=false
  fi
}

# Les données préchargées d'un ticket, dans AUDIT_V (vide s'il n'est pas sur
# le serveur). k : son rang dans AUDIT_P_*, s'il est connu.
audit_preloaded() {
  local ticket="$1"
  local k="$2"

  AUDIT_V=""
  if [[ -n "$k" && "${AUDIT_P_NAME[$k]}" == "$ticket" ]]; then
    AUDIT_V="${AUDIT_P_DATA[$k]}"
    return 0
  fi
  for k in ${AUDIT_P_NAME[@]+"${!AUDIT_P_NAME[@]}"}; do
    if [[ "${AUDIT_P_NAME[$k]}" == "$ticket" ]]; then
      AUDIT_V="${AUDIT_P_DATA[$k]}"
      return 0
    fi
  done
  return 1
}

audit_remote_exists() {
  [[ "$AUDIT_REMOTE_REFS" == *$'\n'"$1"$'\n'* ]]
}

# Le ticket est-il livré dans cette base ? Un cache par base : les tickets
# arrivent dans le désordre (features sur la préprod, hotfix sur la prod).
audit_delivered() {
  local ticket="$1"
  local base="$2"
  local k

  for k in ${AUDIT_DC_BASES[@]+"${!AUDIT_DC_BASES[@]}"}; do
    if [[ "${AUDIT_DC_BASES[$k]}" == "$base" ]]; then
      [[ "${AUDIT_DC_TICKETS[$k]}" == *$'\n'"$ticket"$'\n'* ]]
      return
    fi
  done
  demo_delivered_cache_load "$base"
  k=${#AUDIT_DC_BASES[@]}
  AUDIT_DC_BASES[$k]="$base"
  AUDIT_DC_TICKETS[$k]="$DEMO_DELIVERED_TICKETS"
  demo_ticket_is_delivered "$ticket"
}

# Le rebase d'un ticket sur sa base passerait-il ? Code 0 : oui ; 1 : conflit
# (AUDIT_C_* renseignés). git merge-tree juge le résultat d'ensemble ; à
# défaut (git trop ancien), les commits sont rejoués un par un.
audit_ticket_rebase_check() {
  local ticket="$1"
  local base="$2"
  local ticket_ref="refs/remotes/$j2s_remote/$ticket" base_ref="refs/remotes/$j2s_remote/$base"
  local out status files messages path code fork sha info author email subject

  if [[ "$AUDIT_MERGE_TREE" != true ]]; then
    AUDIT_PLAN=()
    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      AUDIT_PLAN[${#AUDIT_PLAN[@]}]="$sha"$'\037'"$ticket"$'\037'"ticket_rebase"
    done < <(demo_ticket_log "$ticket" "$base")
    AUDIT_TICKET_BASE="$base"
    audit_replay "$base_ref" audit_ticket_provenance
    [[ $? -eq 1 ]] && return 1
    return 0
  fi

  out=$(LC_ALL=C git -c core.quotePath=false merge-tree --write-tree --name-only "$base_ref" "$ticket_ref" 2>/dev/null)
  status=$?
  [[ $status -eq 1 ]] || return 0

  # Sortie : l'arbre, les fichiers en conflit, une ligne vide, les messages.
  files=$(printf '%s\n' "$out" | sed -n '2,/^$/p' | sed '/^$/d')
  messages=$(printf '%s\n' "$out" | sed -n '/^$/,$p')
  fork=$(git merge-base "$base_ref" "$ticket_ref" 2>/dev/null)

  AUDIT_C_TICKET="$ticket"
  AUDIT_C_STEP="ticket_rebase"
  AUDIT_C_SHA=""
  AUDIT_C_LINES=""
  AUDIT_C_OTHERS=""
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$messages" in
      *"CONFLICT (add/add)"*"$path"*) code="AA" ;;
      *"CONFLICT (modify/delete): $path deleted in $ticket_ref"*) code="UD" ;;
      *"CONFLICT (modify/delete): $path deleted in "*) code="DU" ;;
      *) code="UU" ;;
    esac
    AUDIT_C_LINES="$AUDIT_C_LINES$code $path"$'\n'

    # Côté ticket : le commit du ticket qui a touché le fichier en dernier.
    if [[ -z "$AUDIT_C_SHA" ]]; then
      AUDIT_C_SHA=$(git log -n 1 --format=%H "$fork..$ticket_ref" -- "$path" 2>/dev/null)
    fi
    # En face : le dernier commit de la base qui l'a touché depuis le départ du ticket.
    info=$(git log -n 1 --format='%H%x1f%an%x1f%ae%x1f%s' "$fork..$base_ref" -- "$path" 2>/dev/null)
    if [[ -n "$info" ]]; then
      IFS=$'\037' read -r sha author email subject <<< "$info"
      AUDIT_C_OTHERS="$AUDIT_C_OTHERS$path"$'\037'"$sha"$'\037'"$author"$'\037'"$email"$'\037'"$subject"$'\037'"$base"$'\n'
    else
      AUDIT_C_OTHERS="$AUDIT_C_OTHERS$path"$'\n'
    fi
  done <<< "$files"

  [[ -n "$AUDIT_C_SHA" ]] || AUDIT_C_SHA=$(git rev-parse "$ticket_ref")
  return 1
}

# Évalue un ticket (s'il ne l'a pas déjà été) : base, retard, livraison, et
# faisabilité de son rebase. Sans sous-shell pour le JSON : il y en a des
# centaines.
audit_ticket_eval() {
  local ticket="$1"
  local i base base_recorded=true base_ref behind=0 status command="" conflict_json="null"
  local type="${ticket%%/*}" id="${ticket#*/}"
  local owner_name="" owner_email="" last_activity="" pr_subject pr_validated="null" report=""
  local j_ticket j_type j_id j_base j_status j_owner j_email j_last j_command

  audit_ticket_register "$ticket"
  i="$AUDIT_I"
  [[ -n "${AUDIT_T_STATUS[$i]}" ]] && return 0

  audit_preloaded "$ticket" "$i"
  IFS=$'\037' read -r base owner_name owner_email last_activity pr_subject <<< "$AUDIT_V"

  # Sa base : celle enregistrée à sa création, sinon la référence du projet.
  if [[ -z "$base" ]]; then
    base_recorded=false
    if [[ "$type" == "hotfix" ]]; then base="$AUDIT_REF_HOTFIX"; else base="$AUDIT_REF_FEATURE"; fi
  fi
  base_ref="refs/remotes/$j2s_remote/$base"

  if [[ "$pr_subject" == "$prefix_init_commit $ticket $suffix_init_commit" ]]; then
    pr_validated=false
  elif [[ -n "$pr_subject" ]]; then
    pr_validated=true
  fi

  if [[ -z "$base" ]] || ! audit_remote_exists "$base"; then
    status="base_missing"
    command="jgit $type rebase $id --based-on <branche>"
  else
    if audit_delivered "$ticket" "$base"; then
      status="delivered"
    else
      behind=$(git rev-list --count "refs/remotes/$j2s_remote/$ticket..$base_ref" 2>/dev/null)
      if [[ "${behind:-0}" -eq 0 ]]; then
        status="up_to_date"
      elif audit_ticket_rebase_check "$ticket" "$base"; then
        status="to_rebase"
        command="jgit $type rebase $id"
      else
        status="conflicts"
        command="jgit $type rebase $id --on-conflict pause"
        audit_conflict_report "      "
        report="${AUDIT_C_REPORT%$'\n'}"
        conflict_json="{\"commit\":$AUDIT_C_COMMIT_JSON,\"files\":$AUDIT_C_FILES_JSON}"
      fi
    fi
  fi

  AUDIT_T_STATUS[$i]="$status"
  AUDIT_T_BASE[$i]="$base"
  AUDIT_T_BEHIND[$i]="${behind:-0}"
  AUDIT_T_COMMAND[$i]="$command"
  AUDIT_T_OWNER[$i]="$owner_name"
  AUDIT_T_REPORT[$i]="$report"

  json_str_into j_ticket "$ticket"
  json_str_into j_type "$type"
  json_str_into j_id "$id"
  json_str_into j_status "$status"
  if [[ -n "$base" ]]; then json_str_into j_base "$base"; else j_base=null; fi
  if [[ -n "$owner_name" ]]; then json_str_into j_owner "$owner_name"; else j_owner=null; fi
  if [[ -n "$owner_email" ]]; then json_str_into j_email "$owner_email"; else j_email=null; fi
  if [[ -n "$last_activity" ]]; then json_str_into j_last "$last_activity"; else j_last=null; fi
  if [[ -n "$command" ]]; then json_str_into j_command "$command"; else j_command=null; fi

  AUDIT_T_JSON_PART[$i]="{\"ticket\":$j_ticket,\"type\":$j_type,\"id\":$j_id,\"base\":$j_base,\"base_recorded\":$base_recorded,\"behind_base\":${behind:-0},\"status\":$j_status,\"delivered\":$([[ "$status" == delivered ]] && echo true || echo false),\"pr_validated\":$pr_validated,\"owner\":{\"author\":$j_owner,\"email\":$j_email},\"last_activity\":$j_last,\"command\":$j_command,\"conflict\":$conflict_json}"
}

# L'objet JSON complet d'un ticket : ce que l'évaluation a calculé, plus les
# démos qui le contiennent.
audit_ticket_json() {
  local i="$1"
  local part="${AUDIT_T_JSON_PART[$i]}"
  local demo j_demo demos=""

  for demo in ${AUDIT_T_DEMOS[$i]}; do
    json_str_into j_demo "$demo"
    demos="${demos:+$demos,}$j_demo"
  done
  AUDIT_T_JSON="${part%\}},\"demos\":[$demos]}"
}

# Rapport humain des tickets : le détail de ce qui coince, et des tickets des
# démos ; pour les autres tickets à rebaser, un compte par propriétaire — sur
# un projet de centaines de branches, la liste complète noierait l'essentiel
# (elle est dans --json).
audit_print_tickets() {
  local order="" order0="" order1="" order2="" order3="" i status who demos up=0 delivered=0 others=0 owners=""

  printf "\n%sTICKETS%s (%s)\n" "$C_BLUE" "$C_RESET" "${#AUDIT_T_NAME[@]}"

  # Ce qui coince d'abord, puis ce qui est à rebaser, puis le reste.
  for i in ${AUDIT_T_NAME[@]+"${!AUDIT_T_NAME[@]}"}; do
    case "${AUDIT_T_STATUS[$i]}" in
      conflicts) order0="$order0 $i" ;;
      base_missing) order1="$order1 $i" ;;
      to_rebase) order2="$order2 $i" ;;
      *) order3="$order3 $i" ;;
    esac
  done
  order="$order0 $order1 $order2 $order3"

  for i in $order; do
    status="${AUDIT_T_STATUS[$i]}"
    who="${AUDIT_T_OWNER[$i]:-?}"
    demos=""
    [[ -n "${AUDIT_T_DEMOS[$i]}" ]] && demos=" · démos : ${AUDIT_T_DEMOS[$i]}"
    case "$status" in
      conflicts)
        printf "  %s✖ %s%s — en retard de %s commit(s) sur %s, son rebase coince\n" \
          "$C_RED" "${AUDIT_T_NAME[$i]}" "$C_RESET" "${AUDIT_T_BEHIND[$i]}" "${AUDIT_T_BASE[$i]}"
        printf "%s\n" "${AUDIT_T_REPORT[$i]}"
        printf "      → %s%s%s   (propriétaire : %s%s)\n" "$C_CYAN" "${AUDIT_T_COMMAND[$i]}" "$C_RESET" "$who" "$demos"
        ;;
      base_missing)
        printf "  %s✖ %s%s — sa base %s n'existe plus\n" "$C_RED" "${AUDIT_T_NAME[$i]}" "$C_RESET" "${AUDIT_T_BASE[$i]:-?}"
        printf "      → %s%s%s   (propriétaire : %s%s)\n" "$C_CYAN" "${AUDIT_T_COMMAND[$i]}" "$C_RESET" "$who" "$demos"
        ;;
      to_rebase)
        if [[ -n "${AUDIT_T_DEMOS[$i]}" ]]; then
          printf "  %s↻ %s%s — en retard de %s commit(s) sur %s, son rebase passe\n" \
            "$C_YELLOW" "${AUDIT_T_NAME[$i]}" "$C_RESET" "${AUDIT_T_BEHIND[$i]}" "${AUDIT_T_BASE[$i]}"
          printf "      → %s%s%s   (propriétaire : %s%s)\n" "$C_CYAN" "${AUDIT_T_COMMAND[$i]}" "$C_RESET" "$who" "$demos"
        else
          others=$((others + 1))
          owners="$owners$who"$'\n'
        fi
        ;;
      up_to_date) up=$((up + 1)) ;;
      delivered) delivered=$((delivered + 1)) ;;
    esac
  done

  if [[ $others -gt 0 ]]; then
    printf "  %s↻ %s autre(s) ticket(s) en retard sur leur base, rebase sans conflit%s — par propriétaire : %s\n" \
      "$C_YELLOW" "$others" "$C_RESET" \
      "$(printf '%s' "$owners" | sed '/^$/d' | sort | uniq -c | sort -rn | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "%s%s (%s)", (NR > 1 ? ", " : ""), $0, n }')"
  fi
  if [[ $((up + delivered)) -gt 0 ]]; then
    printf "  %s✔ %s à jour sur leur base, %s déjà livré(s)%s\n" "$C_GREEN" "$up" "$delivered" "$C_RESET"
  fi
  printf "  %sLa liste complète, ticket par ticket : jgit audit tickets --json%s\n" "$C_DIM" "$C_RESET"
}

###############################################
#            Démos
###############################################

# D'où vient un commit de la démo en cours de reconstruction : un ticket
# (commit rejoué par la simulation, ou déjà dans la démo quand on ne fait
# qu'ajouter à la suite), un commit ajouté à la main, ou la base.
audit_demo_provenance() {
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

# Ce qu'il y a à faire pour la démo lue (demo_load fait). Renseigne :
#   AUDIT_D_PREREQ    tickets à rebaser d'abord, chez eux, sur leur base
#   AUDIT_D_HELD      ceux dont ce rebase coince : leur auteur résoudra le
#                     conflit, la démo ne peut pas les simuler avant
#   AUDIT_D_DROPS     « ticket:raison »
#   AUDIT_D_FRESH     tickets à reprendre depuis leur branche (--from) : les
#                     réécrits, et ceux que leur auteur aura résolus
#   AUDIT_D_ADD       tickets dont les nouveaux commits s'ajoutent à la suite
#   AUDIT_D_REBASE    true si la démo doit être reconstruite
#
# Un ticket seulement en retard sur sa base, sans conflit, n'est pas repris
# depuis sa branche : la démo rejoue son segment, avec les résolutions déjà
# faites dans la démo. La simulation le reprendra si son segment coince
# (audit_demo_eval).
audit_demo_needs() {
  local i ticket t

  AUDIT_D_PREREQ=""
  AUDIT_D_HELD=""
  AUDIT_D_DROPS=""
  AUDIT_D_FRESH=""
  AUDIT_D_ADD=""
  AUDIT_D_REBASE=false
  AUDIT_D_REASON=""

  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    ticket="${DEMO_TICKETS[$i]}"
    if [[ "${DEMO_T_DELIVERED[$i]}" == true ]]; then
      AUDIT_D_DROPS=$(demo_list_add "$AUDIT_D_DROPS" "$ticket:delivered")
      continue
    fi
    if [[ "${DEMO_T_STATUS[$i]}" == "missing" ]]; then
      AUDIT_D_DROPS=$(demo_list_add "$AUDIT_D_DROPS" "$ticket:missing")
      continue
    fi

    t=""
    audit_ticket_index "$ticket" && t="$AUDIT_I"
    case "${t:+${AUDIT_T_STATUS[$t]}}" in
      to_rebase)
        AUDIT_D_PREREQ=$(demo_list_add "$AUDIT_D_PREREQ" "$ticket")
        ;;
      conflicts|base_missing)
        AUDIT_D_PREREQ=$(demo_list_add "$AUDIT_D_PREREQ" "$ticket")
        AUDIT_D_HELD=$(demo_list_add "$AUDIT_D_HELD" "$ticket")
        AUDIT_D_FRESH=$(demo_list_add "$AUDIT_D_FRESH" "$ticket")
        continue
        ;;
    esac

    case "${DEMO_T_STATUS[$i]}" in
      diverged) AUDIT_D_FRESH=$(demo_list_add "$AUDIT_D_FRESH" "$ticket") ;;
      ahead) AUDIT_D_ADD=$(demo_list_add "$AUDIT_D_ADD" "$ticket") ;;
    esac
  done

  if [[ "$DEMO_NEEDS_REBASE" == true || -n "$AUDIT_D_FRESH" || -n "$AUDIT_D_DROPS" ]]; then
    AUDIT_D_REBASE=true
  fi
}

# Pourquoi reconstruire la démo, une fois la simulation faite (elle a pu
# ajouter des tickets à reprendre depuis leur branche).
audit_demo_reason() {
  local parts=() fresh
  local IFS='|'

  if [[ "$DEMO_NEEDS_REBASE" == true ]]; then
    parts[${#parts[@]}]="base $DEMO_BASE en retard de $DEMO_BEHIND commit(s)"
  fi
  if [[ -n "$AUDIT_D_FRESH" ]]; then
    fresh="$AUDIT_D_FRESH"
    fresh="${fresh// /, }"
    parts[${#parts[@]}]="reprend $fresh depuis leur branche"
  fi
  if [[ -n "$AUDIT_D_DROPS" ]]; then
    parts[${#parts[@]}]="retire $(audit_drop_words)"
  fi
  printf '%s' "${parts[*]}" | sed 's/|/ ; /g'
}

audit_list_remove() {
  local item out=""

  for item in $1; do
    [[ "$item" == "$2" ]] || out="${out:+$out }$item"
  done
  printf '%s' "$out"
}

audit_drop_words() {
  local item words=""

  for item in $AUDIT_D_DROPS; do
    case "${item##*:}" in
      delivered) words=$(demo_list_add "$words" "${item%:*} (livré)") ;;
      missing) words=$(demo_list_add "$words" "${item%:*} (branche supprimée)") ;;
    esac
  done
  printf '%s' "$words"
}

# La commande de reconstruction de la démo, avec ses --from.
audit_demo_rebase_command() {
  local command="jgit demo rebase $DEMO_NAME"
  local ticket

  for ticket in $AUDIT_D_FRESH; do
    command="$command --from $ticket"
  done
  printf '%s' "$command"
}

# Commits à rejouer pour la démo, dans l'ordre où les commandes de mise à jour
# les poseraient : la reconstruction (si AUDIT_D_REBASE), puis les ajouts.
#   audit_demo_plan <tickets écartés>
audit_demo_plan() {
  local excluded=" $1 "
  local i ticket sha instr fresh_done=""

  AUDIT_PLAN=()

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    [[ "$AUDIT_D_REBASE" == true ]] || break
    ticket="${DEMO_SEG_TICKET[$i]}"
    [[ "$excluded" == *" $ticket "* ]] && continue
    demo_list_has "$AUDIT_D_DROPS" "$ticket:delivered" && continue
    demo_list_has "$AUDIT_D_DROPS" "$ticket:missing" && continue

    if demo_list_has "$AUDIT_D_FRESH" "$ticket"; then
      demo_list_has "$fresh_done" "$ticket" && continue
      fresh_done=$(demo_list_add "$fresh_done" "$ticket")
      for instr in $(demo_plan_fresh_segment "$ticket" "$DEMO_BASE"); do
        [[ "$instr" == pick:* ]] || continue
        sha="${instr#pick:}"
        AUDIT_PLAN[${#AUDIT_PLAN[@]}]="${sha%%:*}"$'\037'"$ticket"$'\037'"fresh"
      done
      continue
    fi

    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      AUDIT_PLAN[${#AUDIT_PLAN[@]}]="$sha"$'\037'"$ticket"$'\037'"rebase"
    done <<< "${DEMO_SEG_SHAS[$i]}"
  done

  if [[ "$AUDIT_D_REBASE" == true && "$excluded" != *" - "* ]]; then
    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      AUDIT_PLAN[${#AUDIT_PLAN[@]}]="$sha"$'\037'"-"$'\037'"foreign"
    done <<< "$DEMO_FOREIGN_SHAS"
  fi

  for ticket in $AUDIT_D_ADD; do
    [[ "$excluded" == *" $ticket "* ]] && continue
    for instr in $(demo_plan_fresh_segment "$ticket" "$DEMO_BASE" true); do
      [[ "$instr" == pick:* ]] || continue
      sha="${instr#pick:}"
      AUDIT_PLAN[${#AUDIT_PLAN[@]}]="${sha%%:*}"$'\037'"$ticket"$'\037'"add"
    done
  done
}

AUDIT_D_ACTIONS_JSON=()

audit_demo_action() {
  local command="$1"
  local reason="$2"
  local kind="$3"

  printf "      %s%s%s\n        %s%s%s\n" "$C_CYAN" "$command" "$C_RESET" "$C_DIM" "$reason" "$C_RESET"
  AUDIT_D_ACTIONS_JSON[${#AUDIT_D_ACTIONS_JSON[@]}]=$(json_object \
    "$(json_kv_str kind "$kind")" \
    "$(json_kv_str command "$command")" \
    "$(json_kv_str reason "$reason")")
}

audit_step_label() {
  case "$1" in
    rebase|foreign) printf 'au rebase de la démo sur sa base à jour' ;;
    fresh) printf 'à la reprise du ticket depuis sa branche' ;;
    add) printf "à l'ajout de ses nouveaux commits" ;;
  esac
}

# Évalue la démo lue. Renseigne AUDIT_D_STATUS (up_to_date, feasible,
# conflicts, blocked) et AUDIT_D_ITEM (objet JSON), et affiche le rapport.
audit_demo_eval() {
  local start excluded rc loops=0 tried="" ticket t k command reason item
  local conflicts_json=() dropped_json=() prereq_json=()
  local c_ticket=() c_step=() c_report=() c_commit=() c_files=()
  local conflict_steps="" conflict_tickets="" resolve drop label

  AUDIT_D_STATUS="up_to_date"
  AUDIT_D_MESSAGE=""
  AUDIT_D_ACTIONS_JSON=()
  AUDIT_D_HELD=""

  printf "\n  %s%s%s  (base %s)\n" "$C_BOLD" "$DEMO_BRANCH" "$C_RESET" "${DEMO_BASE:-?}"

  if [[ "$DEMO_BASE_EXISTS" != true ]]; then
    AUDIT_D_STATUS="blocked"
    AUDIT_D_MESSAGE="Sa base ${DEMO_BASE:-?} n'existe plus : il faut la reconstruire sur une autre (jgit demo rebase $DEMO_NAME --based-on <branche>)."
  elif [[ -n "$(demo_foreign_merges)" ]]; then
    AUDIT_D_STATUS="blocked"
    AUDIT_D_MESSAGE="Un commit de fusion a été poussé à la main sur la démo : il ne se rejoue pas (jgit demo rebase $DEMO_NAME --drop-foreign pour l'écarter)."
  fi
  if [[ "$AUDIT_D_STATUS" == "blocked" ]]; then
    printf "    %s✖ %s%s\n" "$C_RED" "$AUDIT_D_MESSAGE" "$C_RESET"
    audit_demo_item "[]" "[]" "[]" "[]"
    return
  fi

  audit_demo_needs

  if [[ "$AUDIT_D_REBASE" != true && -z "$AUDIT_D_ADD" ]]; then
    printf "    %s✔ À jour, rien à faire.%s\n" "$C_GREEN" "$C_RESET"
    audit_demo_item "[]" "[]" "[]" "[]"
    return
  fi

  # Les tickets dont le rebase coince ne se simulent pas dans la démo avant
  # d'être résolus chez eux : on les écarte d'emblée.
  excluded="$AUDIT_D_HELD"

  if [[ "$AUDIT_D_REBASE" == true ]]; then
    start=$(demo_remote_ref "$DEMO_BASE")
  else
    start="$DEMO_TIP"
  fi

  # Simulation. Le segment d'un ticket qui coince au rebase de la démo est
  # d'abord repris depuis la branche du ticket : son auteur a pu la rebaser et
  # y résoudre le conflit. S'il coince encore, on revient à son segment et le
  # conflit est retenu. Un ticket en conflit est écarté et la simulation
  # reprend sans lui : tous les conflits sont signalés.
  while :; do
    loops=$((loops + 1))
    [[ $loops -gt $(( 3 * ${#DEMO_TICKETS[@]} + 3 )) ]] && break
    audit_demo_plan "$excluded"
    audit_replay "$start" audit_demo_provenance
    rc=$?
    [[ $rc -eq 0 ]] && break
    if [[ $rc -eq 2 ]]; then
      AUDIT_D_STATUS="blocked"
      AUDIT_D_MESSAGE="La simulation n'a pas pu se faire (copie de travail temporaire impossible)."
      printf "    %s✖ %s%s\n" "$C_RED" "$AUDIT_D_MESSAGE" "$C_RESET"
      audit_demo_item "[]" "[]" "[]" "[]"
      return
    fi

    ticket="$AUDIT_C_TICKET"
    if [[ "$AUDIT_C_STEP" == "rebase" && "$ticket" != "-" ]] \
       && ! demo_list_has "$tried" "$ticket" && audit_remote_exists "$ticket"; then
      tried=$(demo_list_add "$tried" "$ticket")
      AUDIT_D_FRESH=$(demo_list_add "$AUDIT_D_FRESH" "$ticket")
      continue
    fi
    if [[ "$AUDIT_C_STEP" == "fresh" ]] && demo_list_has "$tried" "$ticket" \
       && demo_list_has "$AUDIT_D_FRESH" "$ticket"; then
      AUDIT_D_FRESH=$(audit_list_remove "$AUDIT_D_FRESH" "$ticket")
      continue
    fi

    AUDIT_D_STATUS="conflicts"
    audit_conflict_report "        "
    c_ticket[${#c_ticket[@]}]="$ticket"
    c_step[${#c_step[@]}]="$AUDIT_C_STEP"
    c_report[${#c_report[@]}]="$AUDIT_C_REPORT"
    c_commit[${#c_commit[@]}]="$AUDIT_C_COMMIT_JSON"
    c_files[${#c_files[@]}]="$AUDIT_C_FILES_JSON"
    conflict_steps=$(demo_list_add "$conflict_steps" "$AUDIT_C_STEP")
    conflict_tickets=$(demo_list_add "$conflict_tickets" "$ticket")
    excluded=$(demo_list_add "$excluded" "$ticket")
  done
  AUDIT_D_REASON=$(audit_demo_reason)

  # Les conflits retenus, avec les commandes calculées sur le plan final.
  for k in ${c_ticket[@]+"${!c_ticket[@]}"}; do
    ticket="${c_ticket[$k]}"
    if [[ "$ticket" == "-" ]]; then
      label="des commits ajoutés à la main"
      drop="jgit demo rebase $DEMO_NAME --drop-foreign"
    else
      label="$ticket"
      drop="jgit demo drop $DEMO_NAME --from $ticket"
    fi
    if [[ "${c_step[$k]}" == "add" ]]; then
      resolve="jgit demo add $DEMO_NAME --from $ticket --on-conflict pause"
    else
      resolve="$(audit_demo_rebase_command) --on-conflict pause"
    fi

    printf "    %s✖ Conflit : %s%s (%s)\n" "$C_RED" "$label" "$C_RESET" "$(audit_step_label "${c_step[$k]}")"
    printf '%s' "${c_report[$k]}"
    printf "        → résoudre dans la démo : %s\n" "$resolve"
    printf "        → ou retirer : %s\n" "$drop"
    conflicts_json[${#conflicts_json[@]}]=$(json_object \
      "$(json_kv_str ticket "$ticket")" \
      "$(json_kv_str step "${c_step[$k]}")" \
      "$(json_kv commit "${c_commit[$k]}")" \
      "$(json_kv files "${c_files[$k]}")" \
      "$(json_kv commands "$(json_object \
          "$(json_kv_str resolve "$resolve")" \
          "$(json_kv_str drop "$drop")")")")
  done

  if [[ "$AUDIT_D_STATUS" == "up_to_date" ]]; then
    if [[ -n "$AUDIT_D_HELD" ]]; then
      AUDIT_D_STATUS="conflicts"
    else
      AUDIT_D_STATUS="feasible"
    fi
  fi
  if [[ "$AUDIT_D_STATUS" == "feasible" ]]; then
    printf "    %s✔ Mise à jour faisable sans conflit.%s\n" "$C_GREEN" "$C_RESET"
  fi

  # --- les actions, dans l'ordre -----------------------------------------------
  printf "    Dans l'ordre :\n"

  for ticket in $AUDIT_D_PREREQ; do
    audit_ticket_index "$ticket"
    t="$AUDIT_I"
    case "${AUDIT_T_STATUS[$t]}" in
      conflicts) reason="d'abord rebaser le ticket chez lui : son rebase sur ${AUDIT_T_BASE[$t]} coince (voir TICKETS) — propriétaire : ${AUDIT_T_OWNER[$t]:-?}" ;;
      base_missing) reason="d'abord rebaser le ticket chez lui : sa base ${AUDIT_T_BASE[$t]:-?} n'existe plus — propriétaire : ${AUDIT_T_OWNER[$t]:-?}" ;;
      *) reason="d'abord rebaser le ticket chez lui : en retard de ${AUDIT_T_BEHIND[$t]} commit(s) sur ${AUDIT_T_BASE[$t]} — propriétaire : ${AUDIT_T_OWNER[$t]:-?}" ;;
    esac
    audit_demo_action "${AUDIT_T_COMMAND[$t]}" "$reason" "ticket"
    prereq_json[${#prereq_json[@]}]=$(json_object \
      "$(json_kv_str ticket "$ticket")" \
      "$(json_kv_str status "${AUDIT_T_STATUS[$t]}")" \
      "$(json_kv_str command "${AUDIT_T_COMMAND[$t]}")")
  done

  if [[ "$AUDIT_D_REBASE" == true ]]; then
    command=$(audit_demo_rebase_command)
    if demo_list_has "$conflict_steps" rebase || demo_list_has "$conflict_steps" foreign \
       || demo_list_has "$conflict_steps" fresh; then
      command="$command --on-conflict pause"
    fi
    audit_demo_action "$command" "$AUDIT_D_REASON" "demo"
  fi
  for ticket in $AUDIT_D_ADD; do
    command="jgit demo add $DEMO_NAME --from $ticket"
    demo_list_has "$conflict_tickets" "$ticket" && command="$command --on-conflict pause"
    audit_demo_action "$command" "$ticket a de nouveaux commits" "demo"
  done
  if [[ -n "$AUDIT_D_HELD" ]]; then
    printf "    %s⚠ %s : à simuler de nouveau une fois rebasé(s) chez eux.%s\n" \
      "$C_YELLOW" "$(printf '%s' "$AUDIT_D_HELD" | sed 's/ /, /g')" "$C_RESET"
  fi

  for item in $AUDIT_D_DROPS; do
    dropped_json[${#dropped_json[@]}]=$(json_object \
      "$(json_kv_str ticket "${item%:*}")" "$(json_kv_str reason "${item##*:}")")
  done

  audit_demo_item \
    "$(json_array ${AUDIT_D_ACTIONS_JSON[@]+"${AUDIT_D_ACTIONS_JSON[@]}"})" \
    "$(json_array ${dropped_json[@]+"${dropped_json[@]}"})" \
    "$(json_array ${conflicts_json[@]+"${conflicts_json[@]}"})" \
    "$(json_array ${prereq_json[@]+"${prereq_json[@]}"})"
}

audit_demo_item() {
  AUDIT_D_ITEM=$(json_object \
    "$(json_kv_str name "$DEMO_NAME")" \
    "$(json_kv_str branch "$DEMO_BRANCH")" \
    "$(json_kv_str_or_null base "$DEMO_BASE")" \
    "$(json_kv_num behind_base "$DEMO_BEHIND")" \
    "$(json_kv_str status "$AUDIT_D_STATUS")" \
    "$(json_kv_str_or_null message "$AUDIT_D_MESSAGE")" \
    "$(json_kv prerequisites "$4")" \
    "$(json_kv held "$(json_str_array $AUDIT_D_HELD)")" \
    "$(json_kv actions "$1")" \
    "$(json_kv dropped "$2")" \
    "$(json_kv conflicts "$3")")
}

###############################################
#            jgit audit
###############################################

#   audit_cmd <all|tickets|demos> [démo]
audit_cmd() {
  local scope="${1:-all}"
  local target="$2"
  local branches="" branch ticket i n total skipped=0
  local ticket_items=() demo_items=()
  local t_up=0 t_rebase=0 t_conflicts=0 t_delivered=0 t_missing=0
  local d_up=0 d_feasible=0 d_conflicts=0 d_blocked=0

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  # --- les démos concernées -------------------------------------------------
  if [[ "$scope" != "tickets" ]]; then
    if [[ -n "$target" ]]; then
      demo_require_target "$target" "audit demos"
      if [[ "$DEMO_KIND" != "active" ]]; then
        jgit_fail read_only "$JGIT_EXIT_REFUSED" \
          "La démo $DEMO_BRANCH est en lecture seule ($( [[ "$DEMO_KIND" == archived ]] && echo archivée || echo ancien format)) : il n'y a pas de mise à jour à vérifier."
      fi
      branches="$DEMO_BRANCH"
    else
      branches=$(demo_enumerate active | grep "^$DEMO_PREFIX")
      skipped=$(demo_count_lines "$(demo_enumerate active | grep "^$DEMO_LEGACY_PREFIX")")
    fi
  fi

  printf "%sÉtat des lieux sur %s%s — simulation : rien n'est modifié.\n" "$C_BLUE" "$j2s_remote" "$C_RESET"
  audit_tickets_preload

  # --- les tickets ------------------------------------------------------------
  # Tous ceux du serveur (au même rang que dans AUDIT_P_*), ou seulement ceux
  # des démos vérifiées ; puis, pour chacun, les démos qui le contiennent.
  if [[ "$scope" != "demos" ]]; then
    for ticket in ${AUDIT_P_NAME[@]+"${AUDIT_P_NAME[@]}"}; do
      audit_ticket_register "$ticket" new
    done
  fi
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    demo_load "$branch" || continue
    for ticket in ${DEMO_TICKETS[@]+"${DEMO_TICKETS[@]}"}; do
      audit_remote_exists "$ticket" && audit_ticket_in_demo "$ticket" "$DEMO_NAME"
    done
  done <<< "$branches"

  total=${#AUDIT_T_NAME[@]}
  n=0
  for i in ${AUDIT_T_NAME[@]+"${!AUDIT_T_NAME[@]}"}; do
    n=$((n + 1))
    audit_progress "Tickets" "$n" "$total"
    audit_ticket_eval "${AUDIT_T_NAME[$i]}"
    audit_ticket_json "$i"
    ticket_items[${#ticket_items[@]}]="$AUDIT_T_JSON"
    case "${AUDIT_T_STATUS[$i]}" in
      up_to_date) t_up=$((t_up + 1)) ;;
      to_rebase) t_rebase=$((t_rebase + 1)) ;;
      conflicts) t_conflicts=$((t_conflicts + 1)) ;;
      delivered) t_delivered=$((t_delivered + 1)) ;;
      base_missing) t_missing=$((t_missing + 1)) ;;
    esac
  done
  audit_progress_end
  audit_print_tickets

  # --- les démos --------------------------------------------------------------
  if [[ "$scope" != "tickets" ]]; then
    printf "\n%sDÉMOS%s (%s)\n" "$C_BLUE" "$C_RESET" "$(demo_count_lines "$branches")"
    while IFS= read -r branch; do
      [[ -n "$branch" ]] || continue
      demo_load "$branch" || continue
      audit_demo_eval
      demo_items[${#demo_items[@]}]="$AUDIT_D_ITEM"
      case "$AUDIT_D_STATUS" in
        up_to_date) d_up=$((d_up + 1)) ;;
        feasible) d_feasible=$((d_feasible + 1)) ;;
        conflicts) d_conflicts=$((d_conflicts + 1)) ;;
        blocked) d_blocked=$((d_blocked + 1)) ;;
      esac
    done <<< "$branches"
    if [[ -z "$branches" ]]; then
      printf "  Aucune démo.\n"
    fi
    if [[ $skipped -gt 0 ]]; then
      printf "  %s démo(s) à l'ancien format non vérifiée(s) : jgit demo migrate <nom>.\n" "$skipped"
    fi
  fi

  audit_cleanup

  printf "\nBilan : tickets — %s à jour, %s à rebaser, %s en conflit, %s base disparue, %s livré(s)" \
    "$t_up" "$t_rebase" "$t_conflicts" "$t_missing" "$t_delivered"
  if [[ "$scope" != "tickets" ]]; then
    printf " ; démos — %s à jour, %s faisable(s), %s en conflit, %s bloquée(s)" \
      "$d_up" "$d_feasible" "$d_conflicts" "$d_blocked"
  fi
  printf ".\n"

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.audit/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str command "$JGIT_COMMAND")" \
    "$(json_kv_str scope "$scope")" \
    "$(json_kv tickets "$(json_array ${ticket_items[@]+"${ticket_items[@]}"})")" \
    "$(json_kv demos "$(json_array ${demo_items[@]+"${demo_items[@]}"})")" \
    "$(json_kv summary "$(json_object \
        "$(json_kv tickets "$(json_object \
            "$(json_kv_num total "$total")" \
            "$(json_kv_num up_to_date "$t_up")" \
            "$(json_kv_num to_rebase "$t_rebase")" \
            "$(json_kv_num conflicts "$t_conflicts")" \
            "$(json_kv_num base_missing "$t_missing")" \
            "$(json_kv_num delivered "$t_delivered")")")" \
        "$(json_kv demos "$(json_object \
            "$(json_kv_num total "${#demo_items[@]}")" \
            "$(json_kv_num up_to_date "$d_up")" \
            "$(json_kv_num feasible "$d_feasible")" \
            "$(json_kv_num conflicts "$d_conflicts")" \
            "$(json_kv_num blocked "$d_blocked")" \
            "$(json_kv_num skipped_legacy "$skipped")")")")")")"

  # Un conflit ou un blocage prévu se lit aussi au code de sortie : un job
  # planifié peut s'arrêter dessus sans lire le rapport.
  if [[ $((t_conflicts + t_missing + d_conflicts + d_blocked)) -gt 0 ]]; then
    exit "$JGIT_EXIT_CONFLICT"
  fi
}
