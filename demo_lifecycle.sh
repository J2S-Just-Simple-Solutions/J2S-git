#!/bin/bash

###############################################
###############################################
#      Démos : cycle de vie (archive, unarchive, delete, migrate)
###############################################
###############################################
#
# Archiver une démo, c'est la renommer demo-archive/<AAAA-MM-JJ>_<nom> : le nom
# est libéré pour une nouvelle démo, et la précédente reste consultable (et
# restaurable). Rien n'est réécrit : la branche change de nom, pas de contenu.
#
# Chaque changement de nom est un seul push --atomic : la création du nouveau
# nom et la suppression de l'ancien réussissent ensemble ou échouent ensemble,
# et seulement si personne n'a touché à la démo depuis la lecture
# (--force-with-lease sur la version lue, vide pour « ne doit pas exister »).

demo_today() {
  date +%Y-%m-%d
}

# Premier nom d'archive libre pour une démo, aujourd'hui.
demo_free_archive_branch() {
  local name="$1"
  local day n=2 candidate

  day=$(demo_today)
  candidate="$DEMO_ARCHIVE_PREFIX${day}_$name"
  while demo_remote_exists "$candidate"; do
    candidate="$DEMO_ARCHIVE_PREFIX$day.${n}_$name"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

# Renomme une branche sur le serveur, d'un seul geste.
#   demo_rename_remote <de> <vers> <sha attendu de « de »>
demo_rename_remote() {
  local from="$1"
  local to="$2"
  local sha="$3"

  if git push --quiet --atomic \
       --force-with-lease="refs/heads/$from:$sha" \
       --force-with-lease="refs/heads/$to:" \
       "$j2s_remote" "$sha:refs/heads/$to" ":refs/heads/$from" 2>/dev/null; then
    git update-ref "refs/remotes/$j2s_remote/$to" "$sha" 2>/dev/null
    git update-ref -d "refs/remotes/$j2s_remote/$from" 2>/dev/null
    return 0
  fi

  if demo_remote_moved "$from" "$sha" || demo_remote_exists "$to"; then
    jgit_fail lease_rejected "$JGIT_EXIT_LEASE" \
      "La démo $from a été modifiée sur le serveur pendant l'opération : rien n'a été changé." \
      "Relancez la commande : elle repartira de la version actuelle."
  fi
  jgit_fail push_failed "$JGIT_EXIT_ERROR" \
    "Le serveur a refusé de renommer $from en $to : rien n'a été changé." \
    "Vérifiez votre accès au serveur puis relancez."
}

# Copie locale d'une démo qui n'existe plus sous ce nom sur le serveur : on la
# supprime si elle n'a rien de plus que ce qui vient d'être déplacé, sinon on
# la garde et on le dit. On ne décide pas du sort de commits non publiés.
demo_forget_local_copy() {
  local branch="$1"
  local sha="$2"
  local local_ref="refs/heads/$branch"
  local reference

  git show-ref --verify --quiet "$local_ref" || return 0

  if [[ "$(git rev-parse "$local_ref")" != "$sha" ]] \
     && ! git merge-base --is-ancestor "$local_ref" "$sha" 2>/dev/null; then
    printf "%s⚠ Votre branche locale %s porte des commits absents du serveur : elle est conservée.%s\n" \
      "$C_YELLOW" "$branch" "$C_RESET" >&2
    return 0
  fi

  if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$branch" ]]; then
    if ! reference=$(get_reference_branch feature 2>/dev/null); then
      printf "%s⚠ Vous êtes sur %s, qui n'existe plus sous ce nom : changez de branche puis supprimez-la.%s\n" \
        "$C_YELLOW" "$branch" "$C_RESET" >&2
      return 0
    fi
    switch_branch "$reference"
    current_branch="$reference"
  fi

  git branch -D "$branch" --quiet >/dev/null 2>&1
}

# Document jgit.demo.result/1 d'un changement de nom ou d'une suppression.
demo_emit_lifecycle() {
  local operation="$1"
  local previous="$2"
  local branch="$3"
  local sha="$4"

  json_emit "$(json_object \
    "$(json_kv_str schema "jgit.demo.result/1")" \
    "$(json_kv_bool ok true)" \
    "$(json_kv_str_or_null command "$JGIT_COMMAND")" \
    "$(json_kv_str operation "$operation")" \
    "$(json_kv_str demo "$DEMO_NAME")" \
    "$(json_kv_str_or_null branch "$branch")" \
    "$(json_kv_str previous_branch "$previous")" \
    "$(json_kv_bool changed true)" \
    "$(json_kv_bool pushed true)" \
    "$(json_kv_bool dry_run false)" \
    "$(json_kv_str sha "$sha")")"
}

###############################################
#            jgit demo archive
###############################################

demo_archive_cmd() {
  local target="$1"
  local sha archive

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_require_target "$target" "demo archive"

  case "$DEMO_KIND" in
    archived)
      jgit_fail archived "$JGIT_EXIT_REFUSED" "La démo $DEMO_BRANCH est déjà archivée."
      ;;
    legacy)
      jgit_fail legacy_format "$JGIT_EXIT_REFUSED" \
        "La démo $DEMO_BRANCH est à l'ancien format : elle ne s'archive pas." \
        "Convertissez-la (jgit demo migrate $DEMO_NAME) ou supprimez-la (jgit demo delete $DEMO_BRANCH)."
      ;;
  esac

  sha=$(git rev-parse "$(demo_remote_ref "$DEMO_BRANCH")")
  archive=$(demo_free_archive_branch "$DEMO_NAME")

  printf "%sJGit va archiver la démo %s sous %s.%s\n" "$C_GREEN" "$DEMO_BRANCH" "$archive" "$C_RESET"
  if [[ $JGIT_DRY_RUN == true ]]; then
    printf "%s--dry-run : rien n'a été modifié.%s\n" "$C_DIM" "$C_RESET"
    json_emit "$(json_object \
      "$(json_kv_str schema "jgit.demo.result/1")" "$(json_kv_bool ok true)" \
      "$(json_kv_str_or_null command "$JGIT_COMMAND")" "$(json_kv_str operation archive)" \
      "$(json_kv_str demo "$DEMO_NAME")" "$(json_kv_str branch "$archive")" \
      "$(json_kv_str previous_branch "$DEMO_BRANCH")" "$(json_kv_bool changed true)" \
      "$(json_kv_bool pushed false)" "$(json_kv_bool dry_run true)" "$(json_kv_str sha "$sha")")"
    exit_safe 0
  fi

  demo_rename_remote "$DEMO_BRANCH" "$archive" "$sha"
  demo_forget_local_copy "$DEMO_BRANCH" "$sha"

  printf "%sDémo archivée : %s%s\n" "$C_GREEN" "$archive" "$C_RESET"
  printf "Le nom %s est libre pour une nouvelle démo.\n" "$DEMO_NAME"
  printf "Pour la reprendre : jgit demo unarchive %s\n" "$archive"
  demo_emit_lifecycle archive "$DEMO_BRANCH" "$archive" "$sha"
}

###############################################
#            jgit demo unarchive
###############################################

demo_unarchive_cmd() {
  local input="$1"
  local archive="" archives count sha target

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  if [[ -z "$input" ]]; then
    jgit_fail usage "$JGIT_EXIT_ERROR" \
      "Quelle archive ? Nommez-la : jgit demo unarchive <archive>." \
      "Les archives : jgit demo list --archived"
  fi

  case "$input" in
    "$DEMO_ARCHIVE_PREFIX"*) archive="$input" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*_*) archive="$DEMO_ARCHIVE_PREFIX$input" ;;
    *)
      archives=$(demo_archives_of "${input#"$DEMO_PREFIX"}")
      count=$(demo_count_lines "$archives")
      if [[ $count -gt 1 ]]; then
        jgit_fail ambiguous "$JGIT_EXIT_REFUSED" \
          "La démo ${input#"$DEMO_PREFIX"} a plusieurs archives : précisez laquelle." \
          "$(printf '%s\n' "$archives" | sed 's/^/  jgit demo unarchive /')"
      fi
      archive="$archives"
      ;;
  esac

  if [[ -z "$archive" ]] || ! demo_remote_exists "$archive"; then
    jgit_fail demo_not_found "$JGIT_EXIT_REFUSED" \
      "Aucune archive ne correspond à « $input » sur $j2s_remote." \
      "Les archives : jgit demo list --archived"
  fi

  demo_parse_branch "$archive"
  DEMO_BRANCH="$archive"
  target="$DEMO_PREFIX$DEMO_NAME"

  if demo_remote_exists "$target"; then
    jgit_fail already_exists "$JGIT_EXIT_REFUSED" \
      "La démo $target existe déjà : l'archive ne peut pas reprendre son nom." \
      "Archivez d'abord la démo actuelle : jgit demo archive $DEMO_NAME"
  fi

  sha=$(git rev-parse "$(demo_remote_ref "$archive")")
  demo_rename_remote "$archive" "$target" "$sha"

  printf "%sDémo %s restaurée depuis %s.%s\n" "$C_GREEN" "$target" "$archive" "$C_RESET"
  printf "Elle est peut-être en retard sur sa base : jgit demo show %s\n" "$DEMO_NAME"
  demo_emit_lifecycle unarchive "$archive" "$target" "$sha"
}

###############################################
#            jgit demo delete
###############################################

demo_delete_cmd() {
  local target="$1"
  local sha

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"
  demo_require_target "$target" "demo delete"

  sha=$(git rev-parse "$(demo_remote_ref "$DEMO_BRANCH")")

  printf "%sSuppression de la démo %s%s%s\n" "$C_BLUE" "$C_RED" "$DEMO_BRANCH" "$C_RESET"
  printf "%sElle sera retirée de %s, et votre copie locale avec elle si elle n'a rien de plus.%s\n" \
    "$C_GREEN" "$j2s_remote" "$C_RESET"
  if [[ "$DEMO_KIND" == "active" ]]; then
    printf "Pour la garder consultable, archivez-la plutôt : jgit demo archive %s\n" "$DEMO_NAME"
  fi

  if ! confirm_action "Confirmez-vous la suppression ?" "y"; then
    echo "Opération annulée."
    jgit_error_set cancelled "Suppression annulée : la démo est conservée."
    exit_safe 1
  fi

  if ! git push --quiet --force-with-lease="refs/heads/$DEMO_BRANCH:$sha" \
         "$j2s_remote" ":refs/heads/$DEMO_BRANCH" 2>/dev/null; then
    if demo_remote_moved "$DEMO_BRANCH" "$sha"; then
      jgit_fail lease_rejected "$JGIT_EXIT_LEASE" \
        "La démo $DEMO_BRANCH a été modifiée sur le serveur entre-temps : elle n'a pas été supprimée." \
        "Regardez ce qui a changé (jgit demo show $DEMO_BRANCH) puis relancez."
    fi
    jgit_fail push_failed "$JGIT_EXIT_ERROR" \
      "Le serveur a refusé de supprimer $DEMO_BRANCH." \
      "Vérifiez votre accès au serveur puis relancez."
  fi
  git update-ref -d "refs/remotes/$j2s_remote/$DEMO_BRANCH" 2>/dev/null

  demo_forget_local_copy "$DEMO_BRANCH" "$sha"

  printf "%sDémo %s supprimée.%s\n" "$C_GREEN" "$DEMO_BRANCH" "$C_RESET"
  demo_emit_lifecycle delete "$DEMO_BRANCH" "" "$sha"
}

###############################################
#            jgit demo migrate
###############################################

# Convertit une démo à l'ancien format (demo_<nom>) : une nouvelle démo
# demo/<nom> est fabriquée avec les mêmes tickets, à jour, sur la même base.
# L'ancienne est conservée ; on la supprime quand on veut.
demo_migrate_cmd() {
  local input="$1"
  local based_on="$2"
  local base legacy_branch ticket

  jgit_fetch_once || exit_safe "$JGIT_EXIT_REMOTE"

  if [[ -z "$input" ]]; then
    jgit_fail usage "$JGIT_EXIT_ERROR" "Quelle démo convertir ? jgit demo migrate <nom>."
  fi

  demo_require_target "${input#"$DEMO_LEGACY_PREFIX"}" "demo migrate"
  if [[ "$DEMO_KIND" != "legacy" ]] && demo_remote_exists "$DEMO_LEGACY_PREFIX${input#"$DEMO_LEGACY_PREFIX"}"; then
    DEMO_BRANCH="$DEMO_LEGACY_PREFIX${input#"$DEMO_LEGACY_PREFIX"}"
    demo_parse_branch "$DEMO_BRANCH"
  fi
  if [[ "$DEMO_KIND" != "legacy" ]]; then
    jgit_fail not_legacy "$JGIT_EXIT_REFUSED" \
      "La démo $DEMO_BRANCH est déjà au format actuel : il n'y a rien à convertir."
  fi

  legacy_branch="$DEMO_BRANCH"
  if ! demo_read_legacy "$legacy_branch"; then
    jgit_fail not_a_demo "$JGIT_EXIT_REFUSED" \
      "La branche $legacy_branch n'a pas de commit d'initialisation de démo : jgit ne sait pas la lire."
  fi

  if [[ -n "$based_on" ]]; then
    base="$based_on"
  elif [[ -n "$DEMO_BASE" ]]; then
    base="$DEMO_BASE"
  else
    jgit_fail base_unknown "$JGIT_EXIT_REFUSED" \
      "La démo $legacy_branch ne dit pas de quelle branche elle est partie : elle date d'avant ce mécanisme." \
      "Nommez sa base : jgit demo migrate $DEMO_NAME --based-on <branche>"
  fi
  if ! demo_remote_exists "$base"; then
    jgit_fail base_not_found "$JGIT_EXIT_REFUSED" \
      "La branche de base $base n'existe pas sur $j2s_remote." \
      "Nommez une base vivante : jgit demo migrate $DEMO_NAME --based-on <branche>"
  fi
  if demo_remote_exists "$DEMO_PREFIX$DEMO_NAME"; then
    jgit_fail already_exists "$JGIT_EXIT_REFUSED" \
      "La démo $DEMO_PREFIX$DEMO_NAME existe déjà." \
      "Archivez-la d'abord (jgit demo archive $DEMO_NAME), ou supprimez l'ancienne (jgit demo delete $legacy_branch)."
  fi

  demo_op_begin migrate "la conversion de la démo $legacy_branch"
  OP_base="$base"
  OP_old_sha=""
  OP_lease=""
  OP_plan="init:$base"

  for ticket in ${DEMO_TICKETS[@]+"${DEMO_TICKETS[@]}"}; do
    if ! demo_remote_exists "$ticket"; then
      OP_dropped=$(demo_list_add "$OP_dropped" "$ticket:missing")
      continue
    fi
    OP_plan=$(demo_list_add "$OP_plan" "$(demo_plan_fresh_segment "$ticket" "$base")")
    OP_added=$(demo_list_add "$OP_added" "$ticket")
  done

  printf "%sJGit va recréer la démo %s au format actuel, sous %s, basée sur %s :%s\n" \
    "$C_GREEN" "$legacy_branch" "$OP_target" "$base" "$C_RESET"
  printf "L'ancienne démo est conservée : jgit demo delete %s pour la supprimer ensuite.\n" "$legacy_branch"
  demo_run "$(demo_remote_ref "$base")" "Souhaitez-vous continuer ?"
}
