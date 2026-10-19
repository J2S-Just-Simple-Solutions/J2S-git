#!/bin/bash

###############################################
###############################################
#      Démos : le modèle (lecture seule)
###############################################
###############################################
#
# Une démo est une RECETTE : une branche de base et une liste ordonnée de
# tickets. La recette est écrite dans la branche démo elle-même — aucun autre
# stockage, rien à synchroniser.
#
#   base ── INIT ── a1 a2 ── ⟦A⟧ ── b1 ── ⟦B⟧ ── a3 ── ⟦A⟧
#
#   INIT  [jgit] INIT demo demo/<nom> [empty_commit]
#           jgit-branch: demo/<nom>
#           jgit-based-on: <base>
#           jgit-demo-format: 2
#
#   ⟦T⟧   [jgit] DEMO ticket <T> [empty_commit]
#           jgit-demo-ticket: <T>
#           jgit-demo-commits: <n>
#
# Les commits d'un ticket sont cherry-pickés TELS QUELS, puis le repère du ticket
# CLÔT son segment : tout ce qui se trouve entre deux repères appartient au
# ticket du second. Un ticket peut avoir plusieurs segments (des commits arrivés
# après coup, ajoutés à la suite). Ce qui suit le dernier repère n'appartient à
# aucun ticket : ce sont des commits poussés à la main sur la démo.
#
# Les résolutions de conflit sont dans les commits de la démo : reconstruire la
# démo à partir d'elle-même (retirer un ticket, changer de base) les rejoue.
#
# Ce qui identifie un ticket, ce sont ses commits repères — jamais un SHA, que
# « jgit feature rebase » recalcule. Ce qui identifie un commit d'un ticket,
# c'est son EMPREINTE : adresse de l'auteur, date d'auteur, sujet. Le cherry-pick
# la conserve, le rebase de jgit aussi (il cherry-picke) ; un squash ou un
# commit amendé la change.
#
# Les démos vivent sur le serveur : on lit toujours refs/remotes/<remote>/…
#
#   demo/<nom>                          démo active
#   demo-archive/<AAAA-MM-JJ>_<nom>     démo archivée (lecture seule) ;
#   demo-archive/<AAAA-MM-JJ>.<n>_<nom>   n-ième archive du même nom, le même jour
#   demo_<nom>                          ancien format (lecture seule, à migrer)

DEMO_PREFIX="demo/"
DEMO_ARCHIVE_PREFIX="demo-archive/"
DEMO_LEGACY_PREFIX="demo_"
trailer_demo_format="jgit-demo-format"
trailer_demo_ticket="jgit-demo-ticket"
trailer_demo_commits="jgit-demo-commits"

###############################################
#            Noms
###############################################

# Vrai si le nom est utilisable pour une démo : lisible, sans espace ni
# caractère spécial, et accepté par git comme nom de branche.
demo_name_is_valid() {
  local name="$1"

  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,59}$ ]] || return 1
  [[ "$name" != *..* && "$name" != *.lock && "$name" != *. ]] || return 1
  git check-ref-format --branch "$DEMO_PREFIX$name" >/dev/null 2>&1
}

demo_init_subject() {
  printf '%s demo %s %s' "$prefix_init_commit" "$1" "$suffix_init_commit"
}

demo_marker_subject() {
  printf '%s DEMO ticket %s %s' "$prefix_commit" "$1" "$suffix_init_commit"
}

demo_remote_ref() {
  printf 'refs/remotes/%s/%s' "$j2s_remote" "$1"
}

demo_remote_exists() {
  git show-ref --verify --quiet "$(demo_remote_ref "$1")"
}

# Décompose une branche de démo : genre, nom, date d'archivage.
#   demo_parse_branch <branche>  → DEMO_KIND DEMO_NAME DEMO_ARCHIVED_ON
demo_parse_branch() {
  local branch="$1"
  local rest

  DEMO_ARCHIVED_ON=""
  case "$branch" in
    "$DEMO_PREFIX"*)
      DEMO_KIND="active"
      DEMO_NAME="${branch#"$DEMO_PREFIX"}"
      ;;
    "$DEMO_ARCHIVE_PREFIX"*)
      DEMO_KIND="archived"
      rest="${branch#"$DEMO_ARCHIVE_PREFIX"}"
      DEMO_ARCHIVED_ON="${rest%%_*}"
      DEMO_ARCHIVED_ON="${DEMO_ARCHIVED_ON%%.*}"
      DEMO_NAME="${rest#*_}"
      ;;
    "$DEMO_LEGACY_PREFIX"*)
      DEMO_KIND="legacy"
      DEMO_NAME="${branch#"$DEMO_LEGACY_PREFIX"}"
      ;;
    *)
      return 1
      ;;
  esac
}

# Démos présentes sur le serveur, une branche par ligne, dans l'ordre :
# actives, anciennes, archivées.
#   demo_enumerate <active|archived|all>
demo_enumerate() {
  local scope="${1:-active}"
  local base="refs/remotes/$j2s_remote"

  if [[ "$scope" != "archived" ]]; then
    git for-each-ref --format='%(refname)' "$base/demo" | sed "s#^$base/##"
    git for-each-ref --format='%(refname)' "$base/demo_*" | sed "s#^$base/##"
  fi
  if [[ "$scope" != "active" ]]; then
    git for-each-ref --format='%(refname)' "$base/demo-archive" | sed "s#^$base/##"
  fi
}

# Archives d'une démo donnée, une branche par ligne.
demo_archives_of() {
  local name="$1"
  local branch

  demo_enumerate archived | while IFS= read -r branch; do
    demo_parse_branch "$branch" || continue
    [[ "$DEMO_NAME" == "$name" ]] && printf '%s\n' "$branch"
  done
}

# Trouve la démo désignée par une saisie : nom (« sprint12 »), branche active
# (« demo/sprint12 »), archive (« demo-archive/2026-10-12_sprint12 ») ou ancien
# format (« demo_sprint12 »). Seules les démos présentes sur le serveur comptent.
#
#   demo_resolve <saisie>  → DEMO_BRANCH DEMO_KIND DEMO_NAME DEMO_ARCHIVED_ON
#
# Code 1 si rien ne correspond, 2 si la saisie n'est pas un nom de démo.
demo_resolve() {
  local input="$1"
  local candidate

  DEMO_BRANCH=""

  case "$input" in
    "$DEMO_PREFIX"*|"$DEMO_ARCHIVE_PREFIX"*|"$DEMO_LEGACY_PREFIX"*)
      candidate="$input"
      ;;
    *)
      demo_name_is_valid "$input" || return 2
      candidate="$DEMO_PREFIX$input"
      if ! demo_remote_exists "$candidate" && demo_remote_exists "$DEMO_LEGACY_PREFIX$input"; then
        candidate="$DEMO_LEGACY_PREFIX$input"
      fi
      ;;
  esac

  demo_remote_exists "$candidate" || return 1
  demo_parse_branch "$candidate" || return 2
  DEMO_BRANCH="$candidate"
}

# La démo désignée par la commande : la cible, sinon la branche courante si
# c'en est une. Arrête la commande avec un refus explicite sinon.
#   demo_require_target <saisie> <commande>
demo_require_target() {
  local input="$1"
  local command="$2"
  local current

  if [[ -z "$input" ]]; then
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if demo_parse_branch "$current" 2>/dev/null; then
      input="$current"
    else
      jgit_fail usage "$JGIT_EXIT_ERROR" \
        "Quelle démo ? Nommez-la : jgit $command <nom>." \
        "Les démos du projet : jgit demo list"
    fi
  fi

  demo_resolve "$input"
  case $? in
    0) return 0 ;;
    2)
      jgit_fail invalid_name "$JGIT_EXIT_REFUSED" \
        "« $input » n'est pas un nom de démo valide." \
        "Un nom de démo commence par une lettre ou un chiffre, puis lettres, chiffres, « . », « _ » ou « - » (60 caractères au plus)."
      ;;
  esac

  local archives
  archives=$(demo_archives_of "${input#"$DEMO_PREFIX"}")
  if [[ -n "$archives" ]]; then
    jgit_fail demo_not_found "$JGIT_EXIT_REFUSED" \
      "La démo $input n'existe pas sur $j2s_remote, mais elle a des archives :" \
      "$(printf '%s\n' "$archives" | sed 's/^/  /')"
  fi
  jgit_fail demo_not_found "$JGIT_EXIT_REFUSED" \
    "La démo $input n'existe pas sur $j2s_remote." \
    "Les démos du projet : jgit demo list"
}

###############################################
#            Lecture de la recette
###############################################

# Lit une démo (format 2) depuis sa version serveur.
#
#   demo_read <branche>
#
# Renseigne :
#   DEMO_REF DEMO_TIP DEMO_INIT DEMO_BASE DEMO_FORMAT
#   DEMO_SEG_TICKET[i] DEMO_SEG_FPS[i] DEMO_SEG_SHAS[i] DEMO_SEG_MARKER[i]
#       segments, dans l'ordre ; empreintes et SHA séparés par des sauts de ligne
#   DEMO_TICKETS[]       tickets dans l'ordre de première apparition
#   DEMO_FOREIGN_SHAS    commits hors segment, un par ligne
#
# Code 1 si la branche n'a pas de commit d'init de démo.
demo_read() {
  local branch="$1"
  local marker_re='^\[jgit\] DEMO ticket ([^ ]+) \[empty_commit\]$'
  local sha parents email date subject fp
  local current_fps="" current_shas=""

  DEMO_REF=$(demo_remote_ref "$branch")
  DEMO_TIP=$(git rev-parse -q --verify "$DEMO_REF")
  DEMO_FORMAT="v2"
  DEMO_SEG_TICKET=()
  DEMO_SEG_FPS=()
  DEMO_SEG_SHAS=()
  DEMO_SEG_MARKER=()
  DEMO_TICKETS=()
  DEMO_FOREIGN_SHAS=""

  DEMO_INIT=$(git log --first-parent -n 1 --format=%H --basic-regexp \
    --grep="^$(escape_basic_regex "$prefix_init_commit demo ")" "$DEMO_REF" 2>/dev/null)
  [[ -n "$DEMO_INIT" ]] || return 1

  DEMO_BASE=$(git log -n 1 --format=%B "$DEMO_INIT" | sed -n "s/^$trailer_based_on: *//p" | tail -n 1)

  while IFS=$'\037' read -r -d '' sha parents email date subject; do
    if [[ "$parents" == *" "* ]]; then
      # Un commit de fusion n'appartient à aucune recette.
      DEMO_FOREIGN_SHAS="$DEMO_FOREIGN_SHAS$sha"$'\n'
      continue
    fi
    if [[ "$subject" =~ $marker_re ]]; then
      DEMO_SEG_TICKET[${#DEMO_SEG_TICKET[@]}]="${BASH_REMATCH[1]}"
      DEMO_SEG_FPS[${#DEMO_SEG_FPS[@]}]="$current_fps"
      DEMO_SEG_SHAS[${#DEMO_SEG_SHAS[@]}]="$current_shas"
      DEMO_SEG_MARKER[${#DEMO_SEG_MARKER[@]}]="$sha"
      demo_add_unique_ticket "${BASH_REMATCH[1]}"
      current_fps=""
      current_shas=""
      continue
    fi
    fp="$email"$'\037'"$date"$'\037'"$subject"
    current_fps="$current_fps$fp"$'\n'
    current_shas="$current_shas$sha"$'\n'
  done < <(git log -z --first-parent --reverse \
             --format='%H%x1f%P%x1f%ae%x1f%at%x1f%s' "$DEMO_INIT..$DEMO_REF" 2>/dev/null)

  # Ce qui suit le dernier repère n'a été posé par aucun ticket.
  DEMO_FOREIGN_SHAS="$DEMO_FOREIGN_SHAS$current_shas"
  return 0
}

demo_add_unique_ticket() {
  local ticket="$1"
  local known

  for known in ${DEMO_TICKETS[@]+"${DEMO_TICKETS[@]}"}; do
    [[ "$known" == "$ticket" ]] && return 0
  done
  DEMO_TICKETS[${#DEMO_TICKETS[@]}]="$ticket"
}

# Lit une démo à l'ancien format (demo_<nom>, rejouée par-dessus chaque ticket) :
# la liste des tickets vient des marqueurs « [jgit] DEMO merge <type> <branche> ».
demo_read_legacy() {
  local branch="$1"
  local subject prefix keyword action branch_type ticket

  DEMO_REF=$(demo_remote_ref "$branch")
  DEMO_TIP=$(git rev-parse -q --verify "$DEMO_REF")
  DEMO_FORMAT="legacy"
  DEMO_SEG_TICKET=()
  DEMO_SEG_FPS=()
  DEMO_SEG_SHAS=()
  DEMO_SEG_MARKER=()
  DEMO_TICKETS=()
  DEMO_FOREIGN_SHAS=""

  DEMO_INIT=$(git log --first-parent -n 1 --format=%H --basic-regexp \
    --grep="^$(escape_basic_regex "$prefix_init_commit demo $branch ")" "$DEMO_REF" 2>/dev/null)
  [[ -n "$DEMO_INIT" ]] || return 1

  DEMO_BASE=$(read_based_on "$DEMO_REF" "$branch") || DEMO_BASE=""

  while IFS= read -r subject; do
    read -r prefix keyword action branch_type ticket _ <<< "$subject"
    if [[ "$prefix" == "$prefix_commit" && "$keyword" == "DEMO" && "$action" == "merge" && -n "$ticket" ]]; then
      demo_add_unique_ticket "$ticket"
    fi
  done < <(git log --reverse --format=%s "$DEMO_INIT^..$DEMO_REF" 2>/dev/null)

  return 0
}

###############################################
#            Tickets
###############################################

# Commits utiles d'un ticket : ceux de sa version serveur qui suivent son
# dernier commit d'init (START, ou RESTART). Un par ligne, du plus ancien au
# plus récent, au format demandé (« %H » par défaut).
#
#   demo_ticket_log <ticket> <base> [format]
#
# Sans commit d'init (branche créée hors de jgit), on se rabat sur les commits
# absents de la base. Code 1 si le ticket n'existe pas sur le serveur.
demo_ticket_log() {
  local ticket="$1"
  local base="$2"
  local format="${3:-%H}"
  local ref start range

  ref=$(demo_remote_ref "$ticket")
  git show-ref --verify --quiet "$ref" || return 1

  start=$(git log --first-parent -n 1 --format=%H -F --grep="$suffix_init_commit" "$ref" 2>/dev/null)
  if [[ -n "$start" ]]; then
    range="$start..$ref"
  elif [[ -n "$base" ]] && git show-ref --verify --quiet "$(demo_remote_ref "$base")"; then
    range="$(demo_remote_ref "$base")..$ref"
  else
    range="$ref"
  fi

  git log --first-parent --reverse --no-merges --format="$format" "$range" 2>/dev/null
}

demo_ticket_fingerprints() {
  demo_ticket_log "$1" "$2" '%ae%x1f%at%x1f%s'
}

# Empreintes d'un ticket dans la démo lue, tous segments confondus.
demo_fingerprints_in_demo() {
  local ticket="$1"
  local i

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    [[ "${DEMO_SEG_TICKET[$i]}" == "$ticket" ]] && printf '%s' "${DEMO_SEG_FPS[$i]}"
  done
}

demo_segment_count() {
  local ticket="$1"
  local i count=0

  for i in ${DEMO_SEG_TICKET[@]+"${!DEMO_SEG_TICKET[@]}"}; do
    [[ "${DEMO_SEG_TICKET[$i]}" == "$ticket" ]] && count=$((count + 1))
  done
  printf '%s' "$count"
}

# Nombre de lignes d'une liste (vide → 0).
demo_count_lines() {
  if [[ -z "$1" ]]; then
    printf '0'
  else
    printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '
  fi
}

# Lignes de la liste A absentes de la liste B.
demo_lines_minus() {
  local a="$1"
  local b="$2"

  [[ -n "$a" ]] || return 0
  if [[ -z "$b" ]]; then
    printf '%s\n' "$a" | sed '/^$/d'
    return 0
  fi
  LC_ALL=C comm -23 <(printf '%s\n' "$a" | sed '/^$/d' | LC_ALL=C sort -u) \
                    <(printf '%s\n' "$b" | sed '/^$/d' | LC_ALL=C sort -u)
}

###############################################
#            Ce qui est déjà livré
###############################################
#
# Les SHA d'un ticket ne sont jamais ancêtres de la base : GitHub squash la PR.
# Ce qui atteste la livraison, ce sont les traces jgit que la release fait
# remonter dans la base : le commit d'init de la branche de PR
# (« [jgit] INIT feature/X [empty_commit] ») et le merge de release
# (« [jgit] Release merge feature branch : __PR__feature/X »).

DEMO_DELIVERED_BASE=""
# Tickets livrés dans la base, un par ligne, encadrés de sauts de ligne : la
# question « ce ticket est-il livré ? » se pose alors sans aucun processus,
# même pour des centaines de tickets.
DEMO_DELIVERED_TICKETS=""

demo_delivered_cache_load() {
  local base="$1"
  local p e

  [[ "$DEMO_DELIVERED_BASE" == "$base" ]] && return 0
  DEMO_DELIVERED_BASE="$base"
  DEMO_DELIVERED_TICKETS=""
  [[ -n "$base" ]] || return 0
  git show-ref --verify --quiet "$(demo_remote_ref "$base")" || return 0

  p=$(escape_basic_regex "$prefix_commit")
  e=$(escape_basic_regex "$suffix_init_commit")

  # Sujets exacts : « [jgit] INIT <ticket> [empty_commit] » (commit d'init de
  # la branche de PR), « [jgit] Release merge feature branch : __PR__<ticket> »,
  # et l'ancien « [jgit] Merge feature branch : __PR__<ticket> [[empty_commit]] ».
  DEMO_DELIVERED_TICKETS=$'\n'$(git log "$(demo_remote_ref "$base")" --format=%s -F \
    --grep="$prefix_init_commit " \
    --grep="Release merge feature branch : " \
    --grep="Merge feature branch : " 2>/dev/null \
    | sed -n \
        -e "s/^$p INIT \\([^ ]*\\) $e\$/\\1/p" \
        -e "s/^$p Release merge feature branch : $prefix_PR\\([^ ]*\\)\$/\\1/p" \
        -e "s/^$p Merge feature branch : $prefix_PR\\([^ ]*\\)\\( $e\\)\\{0,1\\}\$/\\1/p")$'\n'
}

# Vrai si le ticket est livré dans la base (cache chargé au préalable).
demo_ticket_is_delivered() {
  [[ "$DEMO_DELIVERED_TICKETS" == *$'\n'"$1"$'\n'* ]]
}

###############################################
#            États
###############################################

# Calcule l'état de chaque ticket de la démo lue.
#
# Renseigne, par ticket i (dans l'ordre de DEMO_TICKETS) :
#   DEMO_T_STATUS[i]     up_to_date | ahead | diverged | missing | unknown
#   DEMO_T_DELIVERED[i]  true | false
#   DEMO_T_IN[i]         commits du ticket présents dans la démo
#   DEMO_T_MISSING[i]    commits du ticket pas encore dans la démo
#   DEMO_T_ONLY[i]       commits de la démo que le ticket n'a plus
#   DEMO_T_ACTION[i]     none | add | refresh | drop
#   DEMO_T_PENDING[i]    true si la branche de travail a du code pas encore livré
#   DEMO_T_SEGMENTS[i]
# et, pour la démo :
#   DEMO_BASE_EXISTS DEMO_BEHIND DEMO_ATTENTION DEMO_FOREIGN_COUNT DEMO_NEEDS_REBASE
demo_compute_status() {
  local i ticket demo_fps ticket_fps missing only in_count

  DEMO_T_STATUS=()
  DEMO_T_DELIVERED=()
  DEMO_T_IN=()
  DEMO_T_MISSING=()
  DEMO_T_ONLY=()
  DEMO_T_ACTION=()
  DEMO_T_PENDING=()
  DEMO_T_SEGMENTS=()
  DEMO_ATTENTION=0
  DEMO_BEHIND=""
  DEMO_BASE_EXISTS=false

  if [[ -n "$DEMO_BASE" ]] && git show-ref --verify --quiet "$(demo_remote_ref "$DEMO_BASE")"; then
    DEMO_BASE_EXISTS=true
    DEMO_BEHIND=$(git rev-list --count "$DEMO_REF..$(demo_remote_ref "$DEMO_BASE")" 2>/dev/null)
  fi

  demo_delivered_cache_load "$DEMO_BASE"

  for i in ${DEMO_TICKETS[@]+"${!DEMO_TICKETS[@]}"}; do
    ticket="${DEMO_TICKETS[$i]}"
    DEMO_T_DELIVERED[$i]=false
    DEMO_T_PENDING[$i]=false
    DEMO_T_IN[$i]=""
    DEMO_T_MISSING[$i]=""
    DEMO_T_ONLY[$i]=""
    DEMO_T_SEGMENTS[$i]=$(demo_segment_count "$ticket")

    if demo_ticket_is_delivered "$ticket"; then
      DEMO_T_DELIVERED[$i]=true
      if demo_remote_exists "$ticket" && demo_remote_exists "$prefix_PR$ticket" \
         && ! git diff --quiet "$(demo_remote_ref "$prefix_PR$ticket")" "$(demo_remote_ref "$ticket")" 2>/dev/null; then
        DEMO_T_PENDING[$i]=true
      fi
    fi

    if ! demo_remote_exists "$ticket"; then
      DEMO_T_STATUS[$i]="missing"
    elif [[ "$DEMO_FORMAT" == "legacy" ]]; then
      if git merge-base --is-ancestor "$(demo_remote_ref "$ticket")" "$DEMO_REF" 2>/dev/null; then
        DEMO_T_STATUS[$i]="up_to_date"
      else
        DEMO_T_STATUS[$i]="unknown"
      fi
    else
      demo_fps=$(demo_fingerprints_in_demo "$ticket")
      ticket_fps=$(demo_ticket_fingerprints "$ticket" "$DEMO_BASE")
      missing=$(demo_lines_minus "$ticket_fps" "$demo_fps")
      only=$(demo_lines_minus "$demo_fps" "$ticket_fps")
      in_count=$(demo_count_lines "$demo_fps")
      DEMO_T_IN[$i]="$in_count"
      DEMO_T_MISSING[$i]=$(demo_count_lines "$missing")
      DEMO_T_ONLY[$i]=$(demo_count_lines "$only")

      if [[ "${DEMO_T_ONLY[$i]}" -gt 0 ]]; then
        DEMO_T_STATUS[$i]="diverged"
      elif [[ "${DEMO_T_MISSING[$i]}" -gt 0 ]]; then
        DEMO_T_STATUS[$i]="ahead"
      else
        DEMO_T_STATUS[$i]="up_to_date"
      fi
    fi

    if [[ "${DEMO_T_DELIVERED[$i]}" == true || "${DEMO_T_STATUS[$i]}" == "missing" ]]; then
      DEMO_T_ACTION[$i]="drop"
    elif [[ "${DEMO_T_STATUS[$i]}" == "diverged" ]]; then
      DEMO_T_ACTION[$i]="refresh"
    elif [[ "${DEMO_T_STATUS[$i]}" == "ahead" ]]; then
      DEMO_T_ACTION[$i]="add"
    else
      DEMO_T_ACTION[$i]="none"
    fi

    if [[ "${DEMO_T_ACTION[$i]}" != "none" ]]; then
      DEMO_ATTENTION=$((DEMO_ATTENTION + 1))
    fi
  done

  DEMO_FOREIGN_COUNT=$(demo_count_lines "$DEMO_FOREIGN_SHAS")
  DEMO_NEEDS_REBASE=false
  if [[ -n "$DEMO_BEHIND" && "$DEMO_BEHIND" -gt 0 ]]; then
    DEMO_NEEDS_REBASE=true
  fi
}

# Lit et évalue une démo, quel que soit son format.
#   demo_load <branche>  (après demo_parse_branch)
demo_load() {
  local branch="$1"

  demo_parse_branch "$branch" || return 1
  DEMO_BRANCH="$branch"
  if [[ "$DEMO_KIND" == "legacy" ]]; then
    demo_read_legacy "$branch" || return 1
  else
    demo_read "$branch" || return 1
  fi
  demo_compute_status
}

# Vrai si une opération en pause concerne cette démo.
demo_operation_paused_on() {
  local branch="$1"

  jgit_state_exists || return 1
  (
    jgit_state_load
    [[ "$OP_operation" == demo_* && "$OP_target" == "$branch" ]]
  )
}
