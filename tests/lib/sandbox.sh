#!/bin/bash
#
# Bac a sable : un vrai depot git local, un "GitHub" local (remote bare) et un
# mock du client gh.
#
# Arborescence creee par sandbox_create :
#
#   $SANDBOX/
#     home/          HOME isole (aucune config git de la machine n'est lue)
#     origin.git/    le remote (joue le role de GitHub cote git)
#     repo/          le depot de travail, ou jgit est execute
#     github/        clone technique pour simuler les actions faites sur GitHub
#     bin/gh         mock du client GitHub CLI
#     gh-calls.log   journal des appels au mock

SANDBOX=""
JGIT_OUTPUT=""
JGIT_STATUS=0

sandbox_create() {
    SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/jgit-test.XXXXXX")

    mkdir -p "$SANDBOX/home" "$SANDBOX/bin"
    ln -s "$JGIT_TESTS_DIR/mocks/bin/gh" "$SANDBOX/bin/gh"

    # Isolation complete : ni la config globale de la machine, ni le vrai gh.
    export HOME="$SANDBOX/home"
    export PATH="$SANDBOX/bin:$PATH"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$SANDBOX/home/.gitconfig"
    export GIT_AUTHOR_NAME="jgit tests"
    export GIT_AUTHOR_EMAIL="jgit-tests@example.invalid"
    export GIT_COMMITTER_NAME="jgit tests"
    export GIT_COMMITTER_EMAIL="jgit-tests@example.invalid"
    export TERM="${TERM:-xterm}"
    export JGIT_GH_LOG="$SANDBOX/gh-calls.log"
    : > "$JGIT_GH_LOG"
    # Les scenarios d'un meme fichier partagent le processus : une panne gh
    # simulee ne doit pas deborder sur le scenario suivant.
    unset JGIT_GH_FAIL

    cat > "$GIT_CONFIG_GLOBAL" <<'GITCONFIG'
[user]
	name = jgit tests
	email = jgit-tests@example.invalid
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[tag]
	gpgsign = false
[pull]
	rebase = false
[push]
	default = simple
[core]
	pager = cat
[advice]
	detachedHead = false
GITCONFIG

    git -c init.defaultBranch=main init --bare --quiet "$SANDBOX/origin.git"
    git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/repo" 2>/dev/null

    # Contenu initial du projet fictif.
    mkdir -p "$SANDBOX/repo/src"
    printf '# Projet de test jgit\n' > "$SANDBOX/repo/README.md"
    printf '.jgit/\n' > "$SANDBOX/repo/.gitignore"
    printf 'version 1.0.0\n' > "$SANDBOX/repo/src/app.txt"
    repo_git add .
    repo_git commit --quiet -m "Initialisation du projet"
    repo_git push --quiet --set-upstream origin main

    # Branche de preprod.
    repo_git checkout --quiet -b develop
    repo_git push --quiet --set-upstream origin develop

    # jgit release start exige un tag x.y.z existant.
    repo_git tag 1.0.0 main
    repo_git push --quiet origin 1.0.0

    # Configuration locale du projet, chargee par jgit.sh.
    mkdir -p "$SANDBOX/repo/.jgit"
    cat > "$SANDBOX/repo/.jgit/conf_local.sh" <<'CONF'
#!/bin/bash

j2s_remote="origin"
branch_prod="main"
branch_preprod="develop"
squash_threshold=8
CONF

    repo_git checkout --quiet develop

    # Clone technique utilise pour simuler ce que fait GitHub (merge de PR...).
    git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/github"

    info "bac a sable : $SANDBOX"
}

sandbox_cleanup() {
    local status=$?
    if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
        if [[ "${JGIT_TEST_KEEP:-0}" == "1" ]]; then
            printf '\n(bac a sable conserve : %s)\n' "$SANDBOX"
        else
            rm -rf "$SANDBOX"
        fi
    fi
    return $status
}

###############################################
#            Raccourcis git
###############################################

repo_git() {
    git -C "$SANDBOX/repo" "$@"
}

origin_git() {
    git -C "$SANDBOX/origin.git" "$@"
}

github_git() {
    git -C "$SANDBOX/github" "$@"
}

repo_current_branch() {
    repo_git rev-parse --abbrev-ref HEAD
}

# Cree (ou modifie) un fichier puis le commite sur la branche courante.
repo_commit_file() {
    local path="$1"
    local content="$2"
    local message="$3"

    mkdir -p "$(dirname "$SANDBOX/repo/$path")"
    printf '%s\n' "$content" > "$SANDBOX/repo/$path"
    repo_git add "$path"
    repo_git commit --quiet -m "$message"
    info "commit sur $(repo_current_branch) : $message"
}

repo_push_current_branch() {
    local branch
    branch=$(repo_current_branch)
    repo_git push --quiet origin "$branch"
}

###############################################
#            Simulation de GitHub
###############################################

# Simule le "Squash and merge" d'une PR : le contenu de la branche de travail
# est ecrase en un commit unique sur la branche __PR__ correspondante.
github_squash_merge_pr() {
    local branch="$1"
    local message="${2:-$branch (#1)}"
    local pr_branch="${JGIT_PREFIX_PR:-__PR__}$branch"

    github_git fetch --quiet origin
    github_git checkout --quiet -B "$pr_branch" "origin/$pr_branch"
    github_git merge --squash --quiet "origin/$branch"
    github_git commit --quiet -m "$message"
    github_git push --quiet origin "$pr_branch"
    info "GitHub : PR $branch squash-mergee dans $pr_branch"
}

# Simule la suppression d'une branche cote GitHub (case "delete branch").
github_delete_branch() {
    local branch="$1"
    github_git push --quiet origin --delete "$branch"
    info "GitHub : branche $branch supprimee"
}

gh_calls() {
    cat "$JGIT_GH_LOG"
}

###############################################
#            Execution de jgit
###############################################

# Lance jgit dans le depot de travail. La sortie complete est rangee dans
# $JGIT_OUTPUT et le code de sortie dans $JGIT_STATUS.
run_jgit() {
    local status=0
    local output

    printf '%s$ jgit %s\n' "$ASSERT_INDENT" "$*"
    # $JGIT_LAUNCHER est vide dans le cas nominal : jgit.sh est lance via son shebang.
    # shellcheck disable=SC2086
    output=$(cd "$SANDBOX/repo" && $JGIT_LAUNCHER "$JGIT_BIN" "$@" < /dev/null 2>&1) || status=$?

    JGIT_OUTPUT="$output"
    JGIT_STATUS=$status

    printf '%s\n' "$output" | sed "s/^/${ASSERT_INDENT}| /"
    printf '%s(code de sortie : %s)\n' "$ASSERT_INDENT" "$status"
    return 0
}

# Ecrit un fichier dans le depot de travail SANS le commiter : sert a simuler
# un espace de travail sale (stash, refus de release start...).
repo_write_file() {
    local path="$1"
    local content="$2"

    mkdir -p "$(dirname "$SANDBOX/repo/$path")"
    printf '%s\n' "$content" > "$SANDBOX/repo/$path"
    info "fichier $path modifie sans commit"
}

# Cree une branche locale sans y basculer.
repo_create_local_branch() {
    local branch="$1"
    local start_point="${2:-HEAD}"
    repo_git branch "$branch" "$start_point"
    info "branche locale $branch creee depuis $start_point"
}

repo_delete_local_branch() {
    repo_git branch -D "$1" >/dev/null 2>&1
    info "branche locale $1 supprimee"
}

# Fusionne une branche dans la branche courante en creant un commit de fusion.
repo_merge_branch() {
    local branch="$1"
    repo_git merge --no-ff --quiet "$branch" -m "Merge $branch" || \
        assert_failed "merge de $branch" "le merge a echoue dans le depot de test"
    info "merge de $branch dans $(repo_current_branch)"
}

# Retire le remote : permet de verifier le garde-fou ensure_remote.
repo_remove_remote() {
    repo_git remote remove origin
    info "remote origin retire du depot de travail"
}

# Supprime un tag en local et sur le remote.
repo_delete_tag() {
    local tag="$1"
    repo_git tag -d "$tag" >/dev/null 2>&1
    repo_git push --quiet origin ":refs/tags/$tag" >/dev/null 2>&1
    info "tag $tag supprime en local et sur le remote"
}

###############################################
#            Simulation de GitHub (suite)
###############################################

# Simule le travail d'un autre developpeur : un commit pousse directement sur
# une branche du remote, sans passer par le depot de travail.
github_commit_file() {
    local branch="$1"
    local path="$2"
    local content="$3"
    local message="$4"

    github_git fetch --quiet origin
    github_git checkout --quiet -B "$branch" "origin/$branch"
    mkdir -p "$(dirname "$SANDBOX/github/$path")"
    printf '%s\n' "$content" > "$SANDBOX/github/$path"
    github_git add "$path"
    github_git commit --quiet -m "$message"
    github_git push --quiet origin "$branch"
    info "GitHub : $message pousse sur $branch"
}

###############################################
#            Photos de l'etat du remote
###############################################

# Memorise le commit pointe par une branche du remote, pour verifier plus tard
# qu'une commande interrompue ne l'a pas modifie.
remote_snapshot_save() {
    local branch="$1"
    mkdir -p "$SANDBOX/snapshots"
    origin_git rev-parse "refs/heads/$branch" > "$SANDBOX/snapshots/$(printf '%s' "$branch" | tr '/' '_')"
    info "etat de $branch (remote) memorise"
}

remote_snapshot_read() {
    local branch="$1"
    cat "$SANDBOX/snapshots/$(printf '%s' "$branch" | tr '/' '_')" 2>/dev/null
}
