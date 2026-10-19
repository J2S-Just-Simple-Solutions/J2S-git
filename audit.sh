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

# Le conflit courant, pour le JSON : AUDIT_C_COMMIT_JSON (le commit en
# cause) et AUDIT_C_FILES_JSON (les fichiers, et en face de chacun le dernier
# commit qui l'a touché). Le rapport humain n'en garde que les personnes
# (audit_conflict_people) : c'est ce qu'il faut savoir pour agir.
audit_conflict_json() {
  local info c_subject c_author c_email c_date
  local line code path kind k found sha author email subject origin
  local o_path=() o_rest=() files="" j_path j_kind j_sha j_subject j_author j_email j_origin
  local j_c_sha j_c_subject j_c_author j_c_email j_c_date

  info=$(git log -n 1 --format='%s%x1f%an%x1f%ae%x1f%ad' --date=short "$AUDIT_C_SHA" 2>/dev/null)
  IFS=$'\037' read -r c_subject c_author c_email c_date <<< "$info"
  AUDIT_C_AUTHOR="$c_author"

  # Sans sous-shell : un conflit peut toucher des dizaines de fichiers, et un
  # audit compter des dizaines de conflits.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    o_path[${#o_path[@]}]="${line%%$'\037'*}"
    if [[ "$line" == *$'\037'* ]]; then o_rest[${#o_rest[@]}]="${line#*$'\037'}"; else o_rest[${#o_rest[@]}]=""; fi
  done <<< "$AUDIT_C_OTHERS"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    code="${line:0:2}"
    path="${line:3}"
    case "$code" in
      UU) kind="both_modified" ;;
      AA) kind="both_added" ;;
      DD) kind="both_deleted" ;;
      AU) kind="added_by_us" ;;
      UA) kind="added_by_them" ;;
      DU) kind="deleted_by_us" ;;
      UD) kind="deleted_by_them" ;;
      MK) kind="conflict_markers" ;;
      *) kind="unknown" ;;
    esac
    json_str_into j_path "$path"
    json_str_into j_kind "$kind"

    found=""
    for k in ${o_path[@]+"${!o_path[@]}"}; do
      if [[ "${o_path[$k]}" == "$path" ]]; then
        found="${o_rest[$k]}"
        break
      fi
    done
    if [[ -n "$found" ]]; then
      IFS=$'\037' read -r sha author email subject origin <<< "$found"
      json_str_into j_sha "$sha"
      json_str_into j_subject "$subject"
      json_str_into j_author "$author"
      json_str_into j_email "$email"
      json_str_into j_origin "$origin"
      files="${files:+$files,}{\"path\":$j_path,\"kind\":$j_kind,\"other\":{\"sha\":$j_sha,\"subject\":$j_subject,\"author\":$j_author,\"email\":$j_email,\"origin\":$j_origin}}"
    else
      files="${files:+$files,}{\"path\":$j_path,\"kind\":$j_kind,\"other\":null}"
    fi
  done <<< "$AUDIT_C_LINES"

  json_str_into j_c_sha "$AUDIT_C_SHA"
  json_str_into j_c_subject "$c_subject"
  json_str_into j_c_author "$c_author"
  json_str_into j_c_email "$c_email"
  json_str_into j_c_date "$c_date"
  AUDIT_C_COMMIT_JSON="{\"sha\":$j_c_sha,\"subject\":$j_c_subject,\"author\":$j_c_author,\"email\":$j_c_email,\"date\":$j_c_date}"
  AUDIT_C_FILES_JSON="[$files]"
}

# Qui est concerné par le conflit courant d'une démo : l'auteur du commit qui
# ne passe pas, et en face ceux qui ont touché les mêmes fichiers, chacun avec
# sa provenance. « Camille (feature/B), Yann (feature/A) ».
audit_conflict_people() {
  { printf '%s\037%s\n' "$AUDIT_C_AUTHOR" "$AUDIT_C_TICKET"; printf '%s' "$AUDIT_C_OTHERS"; } \
    | awk -F '\037' '
        NR == 1 && $1 != "" { who = $1; from = ($2 == "-" ? "commit ajouté à la main" : $2) }
        NR > 1 && NF >= 6 { who = $3; from = $6 }
        who != "" && !seen[who "|" from]++ { printf "%s%s (%s)", (n++ ? ", " : ""), who, from }
        { who = "" }'
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
AUDIT_T_STATUS=()      # up_to_date | to_rebase | conflicts | delivered | base_missing | no_init
AUDIT_T_BASE=()
AUDIT_T_BEHIND=()
AUDIT_T_COMMAND=()
AUDIT_T_OWNER=()
AUDIT_T_JSON_PART=()   # champs JSON calculés à l'évaluation (hors « demos »)
AUDIT_T_BASE_SOURCE=() # recorded | inferred
AUDIT_T_TITLE=()       # titre de la PR sur GitHub
AUDIT_T_PEOPLE=()      # qui doit intervenir, « A, B »
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
# « base<US>auteur<US>email<US>date<US>sujet de sa PR<US>titre de sa PR ».
# Des tableaux, pas une longue chaîne : bash 3.2 met un temps quadratique à y
# extraire une valeur.
AUDIT_P_NAME=()
AUDIT_P_DATA=()
AUDIT_P_MEASURE=()     # « base<US>origine<US>avance<US>retard » (audit_tickets_measure)
AUDIT_REMOTE_REFS=""
AUDIT_MERGE_TREE=""
AUDIT_REF_FEATURE=""
AUDIT_REF_HOTFIX=""
AUDIT_KNOWN_BASES=""   # bases connues, pour supposer celle d'un ticket qui n'en a pas
AUDIT_DC_BASES=()      # caches « livré » par base (voir audit_delivered)
AUDIT_DC_TICKETS=()

# Les titres des PR ouvertes sur GitHub, « branche<TAB>titre ». Sans gh, sans
# réseau, ou avec --no-fetch : rien, et le rapport s'en passe.
audit_pr_titles() {
  [[ "$JGIT_NO_FETCH" == true ]] && return 0
  command -v gh >/dev/null 2>&1 || return 0
  GH_PROMPT_DISABLED=1 gh pr list --state open --limit 1000 --json headRefName,title \
    --jq '.[] | [.headRefName, .title] | @tsv' 2>/dev/null
}

# La table des tickets du serveur, une ligne par ticket :
# « ticket<US>base<US>auteur<US>email<US>date<US>sujet de sa PR<US>titre de sa PR<US>commit d'init ».
# Quatre lectures, jointes par awk :
#   B  sa base : le trailer jgit-based-on du commit d'init le plus récent qui
#      nomme la branche (jgit-branch), comme read_based_on — et ce commit ;
#   P  le sujet du dernier commit de sa branche de PR ;
#   G  le titre de sa PR sur GitHub ;
#   T  les tickets, du plus récemment modifié au plus ancien.
audit_tickets_table() {
  local remote="refs/remotes/$j2s_remote"

  {
    git log --format="B%x09%(trailers:key=$trailer_branch,valueonly,separator=%x2C)%x09%(trailers:key=$trailer_based_on,valueonly,separator=%x2C)%x09%H" \
        --basic-regexp --grep="^$trailer_branch: " \
        $(git for-each-ref --format='%(refname)' "$remote/feature" "$remote/hotfix") 2>/dev/null
    git for-each-ref --format='P%09%(refname:strip=3)%09%(subject)' "$remote" 2>/dev/null \
      | sed -n "s#^P	$prefix_PR#P	#p"
    audit_pr_titles | sed 's/^/G	/'
    git for-each-ref --sort=-committerdate \
        --format='T%09%(refname:strip=3)%09%(authorname)%09%(authoremail:trim)%09%(committerdate:iso-strict)' \
        "$remote/feature" "$remote/hotfix" 2>/dev/null
  } | awk -F '\t' '
    $1 == "B" && $2 != "" && !($2 in base) { n = split($3, b, ","); base[$2] = b[n]; start[$2] = $4; next }
    $1 == "P" { pr[$2] = $3; next }
    $1 == "G" && !($2 in title) { title[$2] = $3; next }
    $1 == "T" { printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n", $2, base[$2], $3, $4, $5, pr[$2], title[$2], start[$2] }'
}

audit_tickets_preload() {
  local line k=0 base

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

  # Les bases connues : la préprod, la production, et toute branche qu'un
  # ticket ou une démo a enregistrée comme base (une branche de projet au long
  # cours, par exemple).
  AUDIT_KNOWN_BASES=""
  audit_known_base_add "$AUDIT_REF_FEATURE"
  audit_known_base_add "$AUDIT_REF_HOTFIX"
  for k in ${AUDIT_P_DATA[@]+"${!AUDIT_P_DATA[@]}"}; do
    base="${AUDIT_P_DATA[$k]%%$'\037'*}"
    [[ -n "$base" ]] && audit_known_base_add "$base"
  done
  while IFS= read -r base; do
    audit_known_base_add "$base"
  done < <(git log --format="%(trailers:key=$trailer_based_on,valueonly,separator=%x0A)" \
             --basic-regexp --grep="^$trailer_branch: $DEMO_PREFIX" \
             $(git for-each-ref --format='%(refname)' "refs/remotes/$j2s_remote/$DEMO_PREFIX") 2>/dev/null \
           | sed '/^$/d' | sort -u)

  # git merge-tree --write-tree --merge-base (git 2.40) simule le rebase d'un
  # ticket sans copie de travail : bien plus rapide que de le rejouer.
  if git merge-tree --write-tree --merge-base=HEAD HEAD HEAD >/dev/null 2>&1; then
    AUDIT_MERGE_TREE=true
  else
    AUDIT_MERGE_TREE=false
  fi
}

audit_known_base_add() {
  [[ -n "$1" ]] || return 0
  audit_remote_exists "$1" || return 0
  demo_list_has "$AUDIT_KNOWN_BASES" "$1" && return 0
  AUDIT_KNOWN_BASES="${AUDIT_KNOWN_BASES:+$AUDIT_KNOWN_BASES }$1"
}

# Les données préchargées d'un ticket, dans AUDIT_V (vide s'il n'est pas sur
# le serveur). k : son rang dans AUDIT_P_*, s'il est connu.
audit_preloaded() {
  local ticket="$1"
  local k="$2"

  AUDIT_V=""
  AUDIT_K=""
  if [[ -n "$k" && "${AUDIT_P_NAME[$k]}" == "$ticket" ]]; then
    AUDIT_V="${AUDIT_P_DATA[$k]}"
    AUDIT_K="$k"
    return 0
  fi
  for k in ${AUDIT_P_NAME[@]+"${!AUDIT_P_NAME[@]}"}; do
    if [[ "${AUDIT_P_NAME[$k]}" == "$ticket" ]]; then
      AUDIT_V="${AUDIT_P_DATA[$k]}"
      AUDIT_K="$k"
      return 0
    fi
  done
  return 1
}

audit_remote_exists() {
  [[ "$AUDIT_REMOTE_REFS" == *$'\n'"$1"$'\n'* ]]
}

# Pour tous les tickets d'un coup : leur base (enregistrée, ou supposée : la
# base connue dont ils s'écartent le moins, la référence de leur type en premier
# à égalité) et leur avance et leur retard sur elle. Un appel à git par base
# connue (%(ahead-behind), git 2.41) au lieu de plusieurs par ticket. À
# appeler une fois les bases des démos connues. Sans git 2.41, rien :
# audit_ticket_eval compte alors ticket par ticket.
audit_tickets_measure() {
  local k cand base line

  AUDIT_P_MEASURE=()
  git for-each-ref --count=1 --format='%(ahead-behind:HEAD)' >/dev/null 2>&1 || return 0

  k=0
  while IFS= read -r line; do
    AUDIT_P_MEASURE[$k]="$line"
    k=$((k + 1))
  done < <(
    {
      for k in ${AUDIT_P_NAME[@]+"${!AUDIT_P_NAME[@]}"}; do
        base="${AUDIT_P_DATA[$k]%%$'\037'*}"
        printf 'R\t%s\t%s\n' "${AUDIT_P_NAME[$k]}" "$base"
      done
      for cand in $AUDIT_KNOWN_BASES; do
        git for-each-ref --format="A%09$cand%09%(refname:strip=3)%09%(ahead-behind:refs/remotes/$j2s_remote/$cand)" \
          "refs/remotes/$j2s_remote/feature" "refs/remotes/$j2s_remote/hotfix" 2>/dev/null
      done
    } | awk -F '\t' -v cands="$AUDIT_KNOWN_BASES" -v reff="$AUDIT_REF_FEATURE" -v refh="$AUDIT_REF_HOTFIX" '
      $1 == "R" { order[++n] = $2; rec[$2] = $3; next }
      $1 == "A" { split($4, ab, " "); ahead[$3, $2] = ab[1]; behind[$3, $2] = ab[2]; next }
      END {
        nc = split(cands, c, " ")
        for (i = 1; i <= n; i++) {
          t = order[i]
          if (rec[t] != "") {
            b = rec[t]; src = "recorded"
          } else {
            src = "inferred"
            b = (substr(t, 1, 7) == "hotfix/") ? refh : reff
            best = ((t, b) in ahead) ? ahead[t, b] : ""
            for (j = 1; j <= nc; j++) {
              if (!((t, c[j]) in ahead)) continue
              if (best == "" || ahead[t, c[j]] + 0 < best + 0) { best = ahead[t, c[j]]; b = c[j] }
            }
          }
          if ((t, b) in ahead) printf "%s\037%s\037%s\037%s\n", b, src, ahead[t, b], behind[t, b]
          else printf "%s\037%s\037\037\n", b, src
        }
      }'
  )
}

# La base d'un ticket qui n'en a pas d'enregistrée (créé avant que jgit
# l'enregistre) : parmi les bases connues, celle dont il s'écarte le moins. La
# référence du projet pour son type passe en premier à égalité. AUDIT_V.
audit_infer_base() {
  local ticket_ref="refs/remotes/$j2s_remote/$1"
  local type="$2"
  local first cand n best="" best_n="" candidates

  if [[ "$type" == "hotfix" ]]; then first="$AUDIT_REF_HOTFIX"; else first="$AUDIT_REF_FEATURE"; fi
  candidates="$first $AUDIT_KNOWN_BASES"
  for cand in $candidates; do
    audit_remote_exists "$cand" || continue
    n=$(git rev-list --count "refs/remotes/$j2s_remote/$cand..$ticket_ref" 2>/dev/null) || continue
    if [[ -z "$best_n" || $n -lt $best_n ]]; then
      best="$cand"
      best_n=$n
    fi
  done
  AUDIT_V="${best:-$first}"
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

# Le rebase d'un ticket sur sa base passerait-il ? Comme jgit feature rebase,
# seuls ses propres commits comptent : ceux qui suivent son commit d'init
# (start). Code 0 : oui ; 1 : conflit (AUDIT_C_* renseignés). git merge-tree
# juge l'ensemble en prenant le commit d'init pour ancêtre commun ; à défaut
# (git avant 2.40), les commits sont rejoués un par un.
audit_ticket_rebase_check() {
  local ticket="$1"
  local base="$2"
  local start="$3"
  local ticket_ref="refs/remotes/$j2s_remote/$ticket" base_ref="refs/remotes/$j2s_remote/$base"
  local out status files messages path code fork sha paths=()

  if [[ "$AUDIT_MERGE_TREE" != true ]]; then
    AUDIT_PLAN=()
    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      AUDIT_PLAN[${#AUDIT_PLAN[@]}]="$sha"$'\037'"$ticket"$'\037'"ticket_rebase"
    done < <(git log --first-parent --reverse --no-merges --format=%H "$start..$ticket_ref" 2>/dev/null)
    AUDIT_TICKET_BASE="$base"
    audit_replay "$base_ref" audit_ticket_provenance
    [[ $? -eq 1 ]] || return 0
    AUDIT_C_FILES=$(printf '%s' "$AUDIT_C_LINES" | cut -c4-)
    return 1
  fi

  out=$(LC_ALL=C git -c core.quotePath=false merge-tree --write-tree --name-only \
          --merge-base="$start" "$base_ref" "$ticket_ref" 2>/dev/null)
  status=$?
  [[ $status -eq 1 ]] || return 0

  # Sortie : l'arbre, les fichiers en conflit, une ligne vide, les messages.
  files=$(printf '%s\n' "$out" | sed -n '2,/^$/p' | sed '/^$/d')
  messages=$(printf '%s\n' "$out" | sed -n '/^$/,$p')
  fork=$(git merge-base "$base_ref" "$start" 2>/dev/null)

  AUDIT_C_TICKET="$ticket"
  AUDIT_C_STEP="ticket_rebase"
  AUDIT_C_LINES=""
  AUDIT_C_FILES="$files"
  paths=()
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    paths[${#paths[@]}]="$path"
    case "$messages" in
      *"CONFLICT (add/add)"*"$path"*) code="AA" ;;
      *"CONFLICT (modify/delete): $path deleted in $ticket_ref"*) code="UD" ;;
      *"CONFLICT (modify/delete): $path deleted in "*) code="DU" ;;
      *) code="UU" ;;
    esac
    AUDIT_C_LINES="$AUDIT_C_LINES$code $path"$'\n'
  done <<< "$files"

  # Côté ticket : le dernier de ses commits qui a touché ces fichiers.
  AUDIT_C_SHA=$(git log -n 1 --format=%H "$start..$ticket_ref" -- ${paths[@]+"${paths[@]}"} 2>/dev/null)
  [[ -n "$AUDIT_C_SHA" ]] || AUDIT_C_SHA=$(git rev-parse "$ticket_ref")

  # En face : pour chaque fichier, le dernier commit de la base qui l'a touché
  # depuis le départ du ticket. Un seul parcours de l'historique pour tous les
  # fichiers : un par fichier coûtait des secondes sur un gros projet.
  AUDIT_C_OTHERS=$(
    {
      printf '%s\n' "$files"
      printf '\036\n'
      git -c core.quotePath=false log --format='%x1d%H%x1f%an%x1f%ae%x1f%s' --name-only \
        "$fork..$base_ref" -- ${paths[@]+"${paths[@]}"} 2>/dev/null
    } | awk -v base="$base" '
        BEGIN { phase = 0 }
        $0 == "\036" { phase = 1; next }
        phase == 0 { if ($0 != "") { want[$0] = 1; order[++n] = $0 } next }
        /^\035/ { info = substr($0, 2); next }
        $0 != "" && ($0 in want) && !($0 in found) { found[$0] = info }
        END {
          for (i = 1; i <= n; i++) {
            p = order[i]
            if (p in found) printf "%s\037%s\037%s\n", p, found[p], base
            else printf "%s\n", p
          }
        }')
  return 1
}

# Qui doit intervenir sur le rebase d'un ticket qui coince : ceux qui ont écrit,
# depuis son commit d'init, les commits qui touchent les fichiers en conflit —
# hors commits de la base fusionnés dans le ticket, qui ne sont pas les siens.
# Une ligne « nom<US>email » par personne (un même nom n'apparaît qu'une fois).
#   audit_ticket_people <start> <ticket_ref> <base_ref> <fichiers, un par ligne>
audit_ticket_people() {
  local start="$1"
  local ticket_ref="$2"
  local base_ref="$3"
  local paths=() path

  while IFS= read -r path; do
    [[ -n "$path" ]] && paths[${#paths[@]}]="$path"
  done <<< "$4"
  git log --no-merges --format='%an%x1f%ae' "$ticket_ref" "^$start" "^$base_ref" \
      -- ${paths[@]+"${paths[@]}"} 2>/dev/null \
    | awk -F '\037' '$1 != "" && !seen[tolower($1)]++'
}

# Évalue un ticket (s'il ne l'a pas déjà été) : base, retard, livraison,
# faisabilité de son rebase, et qui doit intervenir. Sans sous-shell pour le
# JSON : il y en a des centaines.
audit_ticket_eval() {
  local ticket="$1"
  local i base base_source="recorded" base_ref ticket_ref counts="" behind=0 ahead=0 start=""
  local status command="" conflict_json="null" people="" line name mail
  local type="${ticket%%/*}" id="${ticket#*/}" reference
  local owner_name="" owner_email="" last_activity="" pr_subject="" pr_title="" pr_validated="null"
  local j_ticket j_type j_id j_base j_status j_owner j_email j_last j_command j_title j_name j_mail concerned=""

  audit_ticket_register "$ticket"
  i="$AUDIT_I"
  [[ -n "${AUDIT_T_STATUS[$i]}" ]] && return 0

  audit_preloaded "$ticket" "$i"
  IFS=$'\037' read -r base owner_name owner_email last_activity pr_subject pr_title start <<< "$AUDIT_V"
  if [[ "$type" == "hotfix" ]]; then reference="$AUDIT_REF_HOTFIX"; else reference="$AUDIT_REF_FEATURE"; fi

  # Sa base : celle enregistrée à sa création ; à défaut, la base connue dont
  # il s'écarte le moins (un ticket parti d'une branche de projet n'a rien à
  # faire sur la préprod). Mesurée d'avance pour tous les tickets si git le
  # permet (audit_tickets_measure), sinon ici.
  if [[ -n "$AUDIT_K" && -n "${AUDIT_P_MEASURE[$AUDIT_K]}" ]]; then
    IFS=$'\037' read -r base base_source ahead behind <<< "${AUDIT_P_MEASURE[$AUDIT_K]}"
    [[ -n "$ahead" ]] && counts="$behind $ahead"
  elif [[ -z "$base" ]]; then
    base_source="inferred"
    audit_infer_base "$ticket" "$type"
    base="$AUDIT_V"
  fi
  base_ref="refs/remotes/$j2s_remote/$base"
  ticket_ref="refs/remotes/$j2s_remote/$ticket"

  if [[ "$pr_subject" == "$prefix_init_commit $ticket $suffix_init_commit" ]]; then
    pr_validated=false
  elif [[ -n "$pr_subject" ]]; then
    pr_validated=true
  fi
  pr_title=$(audit_title_without_key "$pr_title" "$id")

  # La commande de rebase : la base supposée se donne explicitement, sinon
  # jgit feature rebase partirait sur la référence du projet.
  command="jgit $type rebase $id"
  if [[ "$base_source" == "inferred" && "$base" != "$reference" ]]; then
    command="$command --based-on $base"
  fi

  if [[ -z "$base" ]] || ! audit_remote_exists "$base"; then
    status="base_missing"
    command="jgit $type rebase $id --based-on <branche>"
  elif audit_delivered "$ticket" "$base"; then
    status="delivered"
  else
    [[ -n "$counts" ]] || counts=$(git rev-list --left-right --count "$base_ref...$ticket_ref" 2>/dev/null)
    behind="${counts%%[[:space:]]*}"
    ahead="${counts##*[[:space:]]}"
    if [[ "${ahead:-0}" -eq 0 ]]; then
      # Tous ses commits sont déjà dans sa base.
      status="delivered"
    elif [[ "${behind:-0}" -eq 0 ]]; then
      status="up_to_date"
    else
      # Son commit d'init : celui qui porte sa branche d'origine, sinon le
      # dernier commit d'init qui lui est propre.
      if [[ -z "$start" ]]; then
        start=$(git log --first-parent -n 1 --format=%H -F --grep="$suffix_init_commit" "$base_ref..$ticket_ref" 2>/dev/null)
      fi
      if [[ -z "$start" ]]; then
        # Sans commit d'init, jgit ne sait pas quels commits sont les siens.
        status="no_init"
      elif audit_ticket_rebase_check "$ticket" "$base" "$start"; then
        status="to_rebase"
      else
        status="conflicts"
        command="$command --on-conflict pause"
        audit_conflict_json
        conflict_json="{\"commit\":$AUDIT_C_COMMIT_JSON,\"files\":$AUDIT_C_FILES_JSON}"
        people=$(audit_ticket_people "$start" "$ticket_ref" "$base_ref" "$AUDIT_C_FILES")
      fi
    fi
  fi
  case "$status" in
    up_to_date|delivered) command="" ;;
    no_init) command="" ;;
  esac

  # Qui doit intervenir : pour un conflit, les auteurs des commits en cause ;
  # sinon, le dernier à avoir travaillé sur la branche.
  case "$status" in
    up_to_date|delivered) people="" ;;
    *) [[ -n "$people" ]] || people="$owner_name"$'\037'"$owner_email" ;;
  esac
  AUDIT_T_PEOPLE[$i]=""
  while IFS=$'\037' read -r name mail; do
    [[ -n "$name" ]] || continue
    AUDIT_T_PEOPLE[$i]="${AUDIT_T_PEOPLE[$i]:+${AUDIT_T_PEOPLE[$i]}, }$name"
    json_str_into j_name "$name"
    if [[ -n "$mail" ]]; then json_str_into j_mail "$mail"; else j_mail=null; fi
    concerned="${concerned:+$concerned,}{\"author\":$j_name,\"email\":$j_mail}"
  done <<< "$people"

  AUDIT_T_STATUS[$i]="$status"
  AUDIT_T_BASE[$i]="$base"
  AUDIT_T_BASE_SOURCE[$i]="$base_source"
  AUDIT_T_BEHIND[$i]="${behind:-0}"
  AUDIT_T_COMMAND[$i]="$command"
  AUDIT_T_OWNER[$i]="$owner_name"
  AUDIT_T_TITLE[$i]="$pr_title"

  json_str_into j_ticket "$ticket"
  json_str_into j_type "$type"
  json_str_into j_id "$id"
  json_str_into j_status "$status"
  if [[ -n "$base" ]]; then json_str_into j_base "$base"; else j_base=null; fi
  if [[ -n "$owner_name" ]]; then json_str_into j_owner "$owner_name"; else j_owner=null; fi
  if [[ -n "$owner_email" ]]; then json_str_into j_email "$owner_email"; else j_email=null; fi
  if [[ -n "$last_activity" ]]; then json_str_into j_last "$last_activity"; else j_last=null; fi
  if [[ -n "$command" ]]; then json_str_into j_command "$command"; else j_command=null; fi
  if [[ -n "$pr_title" ]]; then json_str_into j_title "$pr_title"; else j_title=null; fi

  AUDIT_T_JSON_PART[$i]="{\"ticket\":$j_ticket,\"type\":$j_type,\"id\":$j_id,\"pr_title\":$j_title,\"base\":$j_base,\"base_source\":\"$base_source\",\"behind_base\":${behind:-0},\"status\":$j_status,\"delivered\":$([[ "$status" == delivered ]] && echo true || echo false),\"pr_validated\":$pr_validated,\"owner\":{\"author\":$j_owner,\"email\":$j_email},\"last_activity\":$j_last,\"concerned\":[$concerned],\"command\":$j_command,\"conflict\":$conflict_json}"
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

# Le titre d'une PR sans la clé du ticket qu'il répète souvent en tête :
# « F4DEV-731 - OpenSearch — … » → « OpenSearch — … » ; vide s'il n'y a que la clé.
audit_title_without_key() {
  local title="$1"
  local id="$2"
  local rest

  case "$title" in
    "$id") printf '' ; return ;;
    "$id "*|"$id:"*|"$id-"*)
      rest="${title#"$id"}"
      # Les tirets longs se retirent entiers : hors locale UTF-8, « ? » ne
      # désignerait qu'un de leurs octets.
      while :; do
        case "$rest" in
          "—"*) rest="${rest#"—"}" ;;
          "–"*) rest="${rest#"–"}" ;;
          [[:space:]]*|-*|:*) rest="${rest#?}" ;;
          *) break ;;
        esac
      done
      printf '%s' "${rest:-$title}"
      ;;
    *) printf '%s' "$title" ;;
  esac
}

# « Yann (12), Camille (3) » : combien de tickets attendent chaque personne,
# sans tenir compte de la casse (« barry » et « Barry » sont la même personne).
# Une ligne par ticket, « A, B » quand plusieurs personnes y sont attendues.
audit_count_people() {
  printf '%s' "$1" | awk -F ', ' '
      { for (i = 1; i <= NF; i++) if ($i != "") { k = tolower($i); if (!(k in name)) name[k] = $i; c[k]++ } }
      END { for (k in c) printf "%d\t%s\n", c[k], name[k] }' \
    | sort -t "$(printf '\t')" -k1,1nr -k2,2 \
    | awk -F '\t' '{ printf "%s%s (%s)", (NR > 1 ? ", " : ""), $2, $1 }'
}

# « develop », ou « ripolin (base supposée) » pour un ticket sans base enregistrée.
audit_ticket_base_text() {
  local i="$1"

  if [[ "${AUDIT_T_BASE_SOURCE[$i]}" == "inferred" ]]; then
    printf '%s (base supposée)' "${AUDIT_T_BASE[$i]}"
  else
    printf '%s' "${AUDIT_T_BASE[$i]:-?}"
  fi
}

# Rapport humain des tickets : pour ce qui demande une action, qui doit
# intervenir et quoi lancer — le détail des fichiers et des commits est dans
# --json. Les tickets hors démo simplement à rebaser sont comptés par personne :
# sur un projet de centaines de branches, la liste complète noierait l'essentiel.
audit_print_tickets() {
  local order0="" order1="" order2="" order3="" i

  AUDIT_PRINT_UP=0
  AUDIT_PRINT_DELIVERED=0
  AUDIT_PRINT_OTHERS=""
  AUDIT_PRINT_NO_INIT=""

  printf "\n%sTICKETS%s (%s)\n" "$C_BLUE" "$C_RESET" "${#AUDIT_T_NAME[@]}"

  # Ce qui coince d'abord, puis ce qui est à rebaser, puis le reste.
  for i in ${AUDIT_T_NAME[@]+"${!AUDIT_T_NAME[@]}"}; do
    case "${AUDIT_T_STATUS[$i]}" in
      conflicts) order0="$order0 $i" ;;
      base_missing|no_init) order1="$order1 $i" ;;
      to_rebase) order2="$order2 $i" ;;
      *) order3="$order3 $i" ;;
    esac
  done

  for i in $order0 $order1; do
    audit_print_ticket "$i"
  done
  if [[ -n "$AUDIT_PRINT_NO_INIT" ]]; then
    printf "  %s✖ %s autre(s) ticket(s) en retard, sans commit d'init : à rebaser à la main%s\n" \
      "$C_RED" "$(demo_count_lines "$AUDIT_PRINT_NO_INIT")" "$C_RESET"
    printf "      à faire par : %s\n" "$(audit_count_people "$AUDIT_PRINT_NO_INIT")"
  fi
  for i in $order2 $order3; do
    audit_print_ticket "$i"
  done
  if [[ -n "$AUDIT_PRINT_OTHERS" ]]; then
    printf "  %s↻ %s autre(s) ticket(s) en retard sur leur base, rebase sans conflit%s\n" \
      "$C_YELLOW" "$(demo_count_lines "$AUDIT_PRINT_OTHERS")" "$C_RESET"
    printf "      à faire par : %s\n" "$(audit_count_people "$AUDIT_PRINT_OTHERS")"
  fi
  if [[ $((AUDIT_PRINT_UP + AUDIT_PRINT_DELIVERED)) -gt 0 ]]; then
    printf "  %s✔ %s à jour sur leur base, %s déjà livré(s)%s\n" "$C_GREEN" "$AUDIT_PRINT_UP" "$AUDIT_PRINT_DELIVERED" "$C_RESET"
  fi
  printf "  %sLe détail, ticket par ticket (fichiers, commits) : jgit audit tickets --json%s\n" "$C_DIM" "$C_RESET"
}

# Un ticket du rapport humain : ce qui se passe, le titre de sa PR, qui doit
# intervenir, quoi lancer. Les tickets hors démo simplement à rebaser, ou sans
# commit d'init, sont mis de côté pour être comptés par personne.
audit_print_ticket() {
  local i="$1"
  local name="${AUDIT_T_NAME[$i]}" demos="" command="${AUDIT_T_COMMAND[$i]}"

  [[ -n "${AUDIT_T_DEMOS[$i]}" ]] && demos="   (démos : ${AUDIT_T_DEMOS[$i]})"
  case "${AUDIT_T_STATUS[$i]}" in
    conflicts)
      printf "  %s✖ %s%s — en retard de %s commit(s) sur %s : son rebase coince\n" \
        "$C_RED" "$name" "$C_RESET" "${AUDIT_T_BEHIND[$i]}" "$(audit_ticket_base_text "$i")"
      ;;
    base_missing)
      printf "  %s✖ %s%s — sa base %s n'existe plus\n" "$C_RED" "$name" "$C_RESET" "${AUDIT_T_BASE[$i]:-?}"
      ;;
    no_init)
      if [[ -z "${AUDIT_T_DEMOS[$i]}" ]]; then
        AUDIT_PRINT_NO_INIT="$AUDIT_PRINT_NO_INIT${AUDIT_T_PEOPLE[$i]:-?}"$'\n'
        return 0
      fi
      printf "  %s✖ %s%s — en retard sur %s, sans commit d'init : jgit ne sait pas quels commits sont les siens\n" \
        "$C_RED" "$name" "$C_RESET" "$(audit_ticket_base_text "$i")"
      command="à rebaser à la main"
      ;;
    to_rebase)
      if [[ -z "${AUDIT_T_DEMOS[$i]}" ]]; then
        AUDIT_PRINT_OTHERS="$AUDIT_PRINT_OTHERS${AUDIT_T_PEOPLE[$i]:-?}"$'\n'
        return 0
      fi
      printf "  %s↻ %s%s — en retard de %s commit(s) sur %s, son rebase passe\n" \
        "$C_YELLOW" "$name" "$C_RESET" "${AUDIT_T_BEHIND[$i]}" "$(audit_ticket_base_text "$i")"
      ;;
    up_to_date) AUDIT_PRINT_UP=$((AUDIT_PRINT_UP + 1)); return 0 ;;
    delivered) AUDIT_PRINT_DELIVERED=$((AUDIT_PRINT_DELIVERED + 1)); return 0 ;;
    *) return 0 ;;
  esac

  [[ -n "${AUDIT_T_TITLE[$i]}" ]] && printf "      « %s »\n" "${AUDIT_T_TITLE[$i]}"
  printf "      à faire par : %s\n" "${AUDIT_T_PEOPLE[$i]:-?}"
  printf "      → %s%s%s%s\n" "$C_CYAN" "$command" "$C_RESET" "$demos"
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
    audit_conflict_json
    c_ticket[${#c_ticket[@]}]="$ticket"
    c_step[${#c_step[@]}]="$AUDIT_C_STEP"
    c_report[${#c_report[@]}]="$(audit_conflict_people)"
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
    printf "        concerne : %s\n" "${c_report[$k]:-?}"
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
      conflicts) reason="d'abord rebaser le ticket chez lui : son rebase sur $(audit_ticket_base_text "$t") coince — à faire par : ${AUDIT_T_PEOPLE[$t]:-?}" ;;
      base_missing) reason="d'abord rebaser le ticket chez lui : sa base ${AUDIT_T_BASE[$t]:-?} n'existe plus — à faire par : ${AUDIT_T_PEOPLE[$t]:-?}" ;;
      *) reason="d'abord rebaser le ticket chez lui : en retard de ${AUDIT_T_BEHIND[$t]} commit(s) sur $(audit_ticket_base_text "$t") — à faire par : ${AUDIT_T_PEOPLE[$t]:-?}" ;;
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
  local t_up=0 t_rebase=0 t_conflicts=0 t_delivered=0 t_missing=0 t_no_init=0
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
    audit_known_base_add "$DEMO_BASE"
    for ticket in ${DEMO_TICKETS[@]+"${DEMO_TICKETS[@]}"}; do
      audit_remote_exists "$ticket" && audit_ticket_in_demo "$ticket" "$DEMO_NAME"
    done
  done <<< "$branches"
  audit_tickets_measure

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
      no_init) t_no_init=$((t_no_init + 1)) ;;
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

  printf "\nBilan : tickets — %s à jour, %s à rebaser, %s en conflit, %s base disparue, %s sans commit d'init, %s livré(s)" \
    "$t_up" "$t_rebase" "$t_conflicts" "$t_missing" "$t_no_init" "$t_delivered"
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
            "$(json_kv_num no_init "$t_no_init")" \
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
  if [[ $((t_conflicts + t_missing + t_no_init + d_conflicts + d_blocked)) -gt 0 ]]; then
    exit "$JGIT_EXIT_CONFLICT"
  fi
}
