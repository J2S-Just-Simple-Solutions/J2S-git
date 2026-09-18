#!/bin/bash
#
# Assertions specifiques a git / jgit, exprimees dans le vocabulaire metier :
# branches locales, branches du remote (notre "GitHub"), tags, contenu des
# fichiers, appels passes au client gh.

###############################################
#            Branches locales
###############################################

assert_local_branch_exists() {
    local branch="$1"
    local label="${2:-branche locale $branch presente}"

    if repo_git show-ref --verify --quiet "refs/heads/$branch"; then
        assert_ok "$label"
    else
        assert_failed "$label" "branches locales :" "$(repo_git branch --format='%(refname:short)')"
    fi
}

assert_local_branch_missing() {
    local branch="$1"
    local label="${2:-branche locale $branch absente}"

    if repo_git show-ref --verify --quiet "refs/heads/$branch"; then
        assert_failed "$label" "branches locales :" "$(repo_git branch --format='%(refname:short)')"
    else
        assert_ok "$label"
    fi
}

assert_current_branch() {
    local expected="$1"
    assert_equals "$expected" "$(repo_current_branch)" "branche courante = $expected"
}

###############################################
#            Branches du remote
###############################################

assert_remote_branch_exists() {
    local branch="$1"
    local label="${2:-branche distante $branch presente}"

    if origin_git show-ref --verify --quiet "refs/heads/$branch"; then
        assert_ok "$label"
    else
        assert_failed "$label" "branches du remote :" "$(origin_git branch --format='%(refname:short)')"
    fi
}

assert_remote_branch_missing() {
    local branch="$1"
    local label="${2:-branche distante $branch absente}"

    if origin_git show-ref --verify --quiet "refs/heads/$branch"; then
        assert_failed "$label" "branches du remote :" "$(origin_git branch --format='%(refname:short)')"
    else
        assert_ok "$label"
    fi
}

assert_remote_tag_exists() {
    local tag="$1"
    local label="${2:-tag $tag pousse sur le remote}"

    if origin_git show-ref --verify --quiet "refs/tags/$tag"; then
        assert_ok "$label"
    else
        assert_failed "$label" "tags du remote :" "$(origin_git tag -l)"
    fi
}

assert_remote_tag_missing() {
    local tag="$1"
    local label="${2:-absence du tag $tag sur le remote}"

    if origin_git show-ref --verify --quiet "refs/tags/$tag"; then
        assert_failed "$label" "tags du remote :" "$(origin_git tag -l)"
    else
        assert_ok "$label"
    fi
}

###############################################
#            Contenu des branches
###############################################

# Verifie qu'un fichier existe sur une branche du remote.
assert_remote_file_exists() {
    local branch="$1"
    local path="$2"
    local label="${3:-$path present sur $branch (remote)}"

    if origin_git cat-file -e "refs/heads/$branch:$path" 2>/dev/null; then
        assert_ok "$label"
    else
        assert_failed "$label" "contenu de $branch :" "$(origin_git ls-tree -r --name-only "refs/heads/$branch" 2>/dev/null)"
    fi
}

assert_remote_file_missing() {
    local branch="$1"
    local path="$2"
    local label="${3:-$path absent de $branch (remote)}"

    if origin_git cat-file -e "refs/heads/$branch:$path" 2>/dev/null; then
        assert_failed "$label" "le fichier existe pourtant sur $branch"
    else
        assert_ok "$label"
    fi
}

assert_remote_file_content() {
    local branch="$1"
    local path="$2"
    local expected="$3"
    local label="${4:-contenu de $path sur $branch (remote)}"
    local actual

    actual=$(origin_git show "refs/heads/$branch:$path" 2>/dev/null) || {
        assert_failed "$label" "fichier introuvable : $branch:$path"
    }
    assert_equals "$expected" "$actual" "$label"
}

# Verifie que le tag pointe sur un commit qui contient bien le fichier attendu.
assert_tag_file_exists() {
    local tag="$1"
    local path="$2"
    local label="${3:-$path present dans le tag $tag}"

    if origin_git cat-file -e "refs/tags/$tag^{commit}:$path" 2>/dev/null; then
        assert_ok "$label"
    else
        assert_failed "$label" "contenu du tag $tag :" "$(origin_git ls-tree -r --name-only "refs/tags/$tag^{commit}" 2>/dev/null)"
    fi
}

###############################################
#            Historique
###############################################

assert_commit_subject_contains() {
    local ref="$1"
    local needle="$2"
    local label="${3:-message du dernier commit de $ref}"
    local subject

    subject=$(origin_git log -1 --pretty=%s "$ref" 2>/dev/null) || subject=""
    assert_contains "$subject" "$needle" "$label"
}

# Nombre de commits d'une reference du remote.
remote_commit_count() {
    origin_git rev-list --count "$1"
}

assert_remote_log_contains() {
    local ref="$1"
    local needle="$2"
    local label="${3:-historique de $ref contient [$needle]}"
    local history

    history=$(origin_git log --pretty=%s "$ref" 2>/dev/null) || history=""
    assert_contains "$history" "$needle" "$label"
}

###############################################
#            Appels au client gh (mock)
###############################################

assert_gh_called() {
    local needle="$1"
    local label="${2:-gh appele avec [$needle]}"

    assert_contains "$(gh_calls)" "$needle" "$label"
}

assert_gh_not_called() {
    local needle="$1"
    local label="${2:-gh non appele avec [$needle]}"

    assert_not_contains "$(gh_calls)" "$needle" "$label"
}

assert_gh_call_count() {
    local expected="$1"
    local actual
    actual=$(grep -c . "$JGIT_GH_LOG" | tr -d ' ')
    assert_equals "$expected" "$actual" "nombre d'appels a gh"
}

###############################################
#            Code de sortie de jgit
###############################################

assert_jgit_success() {
    local label="${1:-jgit termine sans erreur}"
    if [[ $JGIT_STATUS -eq 0 ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "code de sortie : $JGIT_STATUS" "--- sortie ---" "$JGIT_OUTPUT"
    fi
}

assert_jgit_failure() {
    local label="${1:-jgit termine en erreur}"
    if [[ $JGIT_STATUS -ne 0 ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "jgit a pourtant retourne 0" "--- sortie ---" "$JGIT_OUTPUT"
    fi
}

assert_jgit_exit_code() {
    local expected="$1"
    local label="${2:-code de sortie de jgit = $expected}"

    if [[ $JGIT_STATUS -eq $expected ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "code de sortie : $JGIT_STATUS" "--- sortie ---" "$JGIT_OUTPUT"
    fi
}

###############################################
#            Branche d'origine
###############################################
#
# jgit inscrit la branche de depart dans le corps du commit d'init, sous forme
# de trailers. Les assertions les relisent comme le fait read_based_on : le
# commit le plus recent qui se declare porteur de CETTE branche. Chercher
# seulement "jgit-based-on" repondrait avec la trace d'un ancetre, puisque les
# commits d'init remontent dans les branches livrees.

based_on_of_ref() {
    local git_fn="$1"
    local ref="$2"
    local branch="$3"
    local commit

    commit=$($git_fn log -n 1 --format=%H --grep="^jgit-branch: $branch\$" "$ref" 2>/dev/null) || commit=""
    [[ -n "$commit" ]] || return 1

    $git_fn log -n 1 --format=%B "$commit" 2>/dev/null \
        | sed -n 's/^jgit-based-on: *//p' | tail -n 1
}

assert_local_based_on() {
    local branch="$1"
    local expected="$2"
    local label="${3:-la branche locale $branch est partie de $expected}"
    local actual

    actual=$(based_on_of_ref repo_git "$branch" "$branch") || actual=""
    assert_equals "$expected" "$actual" "$label"
}

assert_remote_based_on() {
    local branch="$1"
    local expected="$2"
    local label="${3:-la branche distante $branch est partie de $expected}"
    local actual

    actual=$(based_on_of_ref origin_git "refs/heads/$branch" "$branch") || actual=""
    assert_equals "$expected" "$actual" "$label"
}

assert_remote_without_based_on() {
    local branch="$1"
    local label="${2:-la branche distante $branch ne porte aucune branche d origine}"
    local actual

    actual=$(based_on_of_ref origin_git "refs/heads/$branch" "$branch") || actual=""
    if [[ -z "$actual" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "branche d origine trouvee : $actual"
    fi
}

# Les trailers ne doivent pas remonter dans les sujets : c'est ce qui les rend
# invisibles en --oneline comme dans la liste des commits de GitHub.
assert_remote_subject_without_based_on() {
    local branch="$1"
    local label="${2:-aucun sujet de $branch ne porte les trailers}"
    local subjects

    subjects=$(origin_git log --pretty=%s "refs/heads/$branch" 2>/dev/null) || subjects=""
    assert_not_contains "$subjects" "jgit-based-on" "$label"
    assert_not_contains "$subjects" "jgit-branch" "$label"
}

assert_jgit_output_contains() {
    assert_contains "$JGIT_OUTPUT" "$1" "${2:-sortie de jgit contient [$1]}"
}

assert_jgit_output_not_contains() {
    assert_not_contains "$JGIT_OUTPUT" "$1" "${2:-sortie de jgit ne contient pas [$1]}"
}

###############################################
#            Historique local
###############################################

assert_local_log_contains() {
    local branch="$1"
    local needle="$2"
    local label="${3:-historique local de $branch contient [$needle]}"
    local history

    history=$(repo_git log --pretty=%s "$branch" 2>/dev/null) || history=""
    assert_contains "$history" "$needle" "$label"
}

assert_local_log_not_contains() {
    local branch="$1"
    local needle="$2"
    local label="${3:-historique local de $branch ne contient pas [$needle]}"
    local history

    history=$(repo_git log --pretty=%s "$branch" 2>/dev/null) || history=""
    assert_not_contains "$history" "$needle" "$label"
}

assert_local_commit_subject_contains() {
    local branch="$1"
    local needle="$2"
    local label="${3:-message du dernier commit local de $branch}"
    local subject

    subject=$(repo_git log -1 --pretty=%s "$branch" 2>/dev/null) || subject=""
    assert_contains "$subject" "$needle" "$label"
}

# Nombre de commits d'une branche du remote depuis une reference de depart.
assert_remote_commit_count_since() {
    local branch="$1"
    local base="$2"
    local expected="$3"
    local actual

    actual=$(origin_git rev-list --count "refs/heads/$base..refs/heads/$branch" 2>/dev/null) || actual="?"
    assert_equals "$expected" "$actual" "nombre de commits de $branch depuis $base"
}

assert_local_commit_count_since() {
    local branch="$1"
    local base="$2"
    local expected="$3"
    local actual

    actual=$(repo_git rev-list --count "$base..$branch" 2>/dev/null) || actual="?"
    assert_equals "$expected" "$actual" "nombre de commits locaux de $branch depuis $base"
}

###############################################
#            Etat memorise du remote
###############################################

assert_remote_branch_unchanged() {
    local branch="$1"
    local label="${2:-branche distante $branch inchangee}"
    local expected actual

    expected=$(remote_snapshot_read "$branch")
    if [[ -z "$expected" ]]; then
        assert_failed "$label" "aucun etat memorise pour $branch" \
            "utilisez l'etape « je note l'etat de la branche distante » avant l'action"
    fi
    actual=$(origin_git rev-parse "refs/heads/$branch" 2>/dev/null) || actual="(branche absente)"
    assert_equals "$expected" "$actual" "$label"
}

assert_remote_branch_changed() {
    local branch="$1"
    local label="${2:-la branche distante $branch a bien ete modifiee}"
    local expected actual

    expected=$(remote_snapshot_read "$branch")
    if [[ -z "$expected" ]]; then
        assert_failed "$label" "aucun etat memorise pour $branch"
    fi
    actual=$(origin_git rev-parse "refs/heads/$branch" 2>/dev/null) || actual="(branche absente)"
    assert_not_equals "$expected" "$actual" "$label"
}

assert_remote_log_not_contains() {
    local ref="$1"
    local needle="$2"
    local label="${3:-historique de $ref ne contient pas [$needle]}"
    local history

    history=$(origin_git log --pretty=%s "$ref" 2>/dev/null) || history=""
    assert_not_contains "$history" "$needle" "$label"
}

###############################################
#            Espace de travail
###############################################

assert_worktree_file_content() {
    local path="$1"
    local expected="$2"
    local label="${3:-contenu du fichier de travail $path}"
    local actual

    if [[ ! -f "$SANDBOX/repo/$path" ]]; then
        assert_failed "$label" "fichier absent du depot de travail : $path"
    fi
    actual=$(cat "$SANDBOX/repo/$path")
    assert_equals "$expected" "$actual" "$label"
}

assert_worktree_clean() {
    local label="${1:-espace de travail propre}"
    local status

    status=$(repo_git status --porcelain)
    if [[ -z "$status" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "modifications restantes :" "$status"
    fi
}

assert_worktree_dirty() {
    local label="${1:-modifications locales conservees}"
    local status

    status=$(repo_git status --porcelain)
    if [[ -n "$status" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "aucune modification locale"
    fi
}
