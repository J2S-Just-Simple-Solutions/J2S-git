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
#     gh-prs.tsv     les PR ouvertes connues du mock (branche, titre)

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
    export JGIT_GH_PRS="$SANDBOX/gh-prs.tsv"
    : > "$JGIT_GH_PRS"
    # Les scenarios d'un meme fichier partagent le processus : une panne gh
    # simulee, un lien d'appel ou un terminal retire ne doivent pas deborder sur
    # le scenario suivant.
    unset JGIT_GH_FAIL
    JGIT_BIN_ALIAS=""

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
# Remplace develop et main par une branche au nom non standard, cote serveur et
# cote developpeur. C'est la seule facon realiste de n'avoir aucune branche de
# reference : un depot GitHub a toujours une branche par defaut, et on ne peut
# pas la supprimer — le bare repo la refuse, exactement comme GitHub.
repo_use_non_standard_branches() {
    local trunk="$1"

    origin_git branch "$trunk" main
    origin_git symbolic-ref HEAD "refs/heads/$trunk"
    origin_git branch -D main
    origin_git branch -D develop

    repo_git fetch --quiet --prune origin
    repo_git checkout --quiet -B "$trunk" "origin/$trunk"
    repo_git branch -D main >/dev/null 2>&1
    repo_git branch -D develop >/dev/null 2>&1
    info "le projet n'a plus que la branche $trunk"
}

# Simule la livraison d'un ticket dans une branche de base : sa branche de PR
# y est fusionnee avec le message de traçabilite d'une release jgit. C'est ce
# que la base recoit quand la release qui contient le ticket y est reportee.
github_deliver_pr() {
    local branch="$1"
    local base="$2"
    local pr_branch="${JGIT_PREFIX_PR:-__PR__}$branch"

    github_git fetch --quiet origin
    github_git checkout --quiet -B "$base" "origin/$base"
    github_git merge --no-ff --quiet "origin/$pr_branch" \
        -m "[jgit] Release merge feature branch : $pr_branch" || \
        assert_failed "livraison de $branch" "le merge de $pr_branch dans $base a echoue"
    github_git push --quiet origin "$base"
    info "GitHub : $pr_branch livree dans $base"
}

# Reproduit une demo telle que la fabriquait la premiere version de jgit
# (branche demo_<nom>) : commit d'init, puis pour chaque ticket un marqueur
# « [jgit] DEMO merge » suivi d'un rebase de la demo PAR-DESSUS le ticket.
# Ces demos existent sur les depots : jgit doit savoir les lire et les migrer.
#
#   github_create_legacy_demo <nom> <base> <base enregistree : true|false> <ticket>...
github_create_legacy_demo() {
    local name="$1"
    local base="$2"
    local record="$3"
    shift 3
    local branch="demo_$name"
    local ticket

    github_git fetch --quiet origin
    github_git checkout --quiet -B "$branch" "origin/$base"
    if [[ "$record" == true ]]; then
        github_git commit --quiet --allow-empty -m "[jgit] INIT demo $branch [empty_commit]" \
            -m "jgit-branch: $branch
jgit-based-on: $base"
    else
        github_git commit --quiet --allow-empty -m "[jgit] INIT demo $branch [empty_commit]"
    fi
    for ticket in "$@"; do
        github_git commit --quiet --allow-empty -m "[jgit] DEMO merge ${ticket%%/*} $ticket [empty_commit]"
        github_git rebase --quiet "origin/$ticket" >/dev/null 2>&1 || \
            assert_failed "demo a l'ancien format" "le rebase sur $ticket a echoue"
    done
    github_git push --quiet origin "$branch"
    info "GitHub : demo a l'ancien format $branch ($*)"
}

# Tickets d'une demo, dans l'ordre, lus directement sur le remote a partir des
# reperes qui closent chaque segment.
remote_demo_tickets() {
    local branch="$1"

    origin_git log --first-parent --reverse --format=%s "refs/heads/$branch" 2>/dev/null \
        | sed -n 's/^\[jgit\] DEMO ticket \([^ ]*\) \[empty_commit\]$/\1/p' \
        | awk '!seen[$0]++'
}

# Simule le titre d'une PR sur GitHub, que gh pr list rendra : la PR est
# renommée, ou ouverte à la main avec ce titre si jgit ne l'a pas ouverte
# (--no-open).
github_rename_pr() {
    local branch="$1"
    local title="$2"

    awk -F '\t' -v b="$branch" 'BEGIN { OFS = "\t" } $1 != b { print }' \
        "$JGIT_GH_PRS" > "$JGIT_GH_PRS.tmp" && mv "$JGIT_GH_PRS.tmp" "$JGIT_GH_PRS"
    printf '%s\t%s\n' "$branch" "$title" >> "$JGIT_GH_PRS"
    info "GitHub : la PR de $branch s'intitule « $title »"
}

# Simule un ticket créé par une version de jgit d'avant la branche d'origine :
# même structure (branche de PR et son commit d'init, branche de travail et son
# commit de démarrage), mais aucun trailer ne dit de quelle branche il part.
github_create_old_ticket() {
    local ticket="$1"
    local base="$2"
    local path="$3"
    local content="$4"
    local pr_branch="${JGIT_PREFIX_PR:-__PR__}$ticket"

    github_git fetch --quiet origin
    github_git checkout --quiet -B "$pr_branch" "origin/$base"
    github_git commit --quiet --allow-empty -m "[jgit] INIT $ticket [empty_commit]"
    github_git checkout --quiet -B "$ticket"
    github_git commit --quiet --allow-empty \
        -m "[jgit] commit for automatic PR creation - this commit will be deleted by squash and merge - START $ticket [empty_commit]"
    mkdir -p "$(dirname "$SANDBOX/github/$path")"
    printf '%s\n' "$content" > "$SANDBOX/github/$path"
    github_git add "$path"
    github_git commit --quiet -m "Ajoute $path"
    github_git push --quiet origin "$pr_branch" "$ticket"
    info "GitHub : ancien ticket $ticket parti de $base, sans branche d'origine enregistree"
}

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

# Chemin par lequel jgit est appele : jgit.sh lui-meme, ou un lien symbolique
# vers lui (installation dans le PATH, image Docker).
jgit_invoked_path() {
    printf '%s' "${JGIT_BIN_ALIAS:-$JGIT_BIN}"
}

# Installe un lien symbolique vers jgit.sh hors du depot jgit, et l'utilise pour
# les appels suivants du scenario.
jgit_use_symlink() {
    mkdir -p "$SANDBOX/install/bin"
    ln -s "$JGIT_BIN" "$SANDBOX/install/bin/jgit"
    JGIT_BIN_ALIAS="$SANDBOX/install/bin/jgit"
    info "jgit appele via le lien $JGIT_BIN_ALIAS"
}

# Lance jgit dans le depot de travail. La sortie complete est rangee dans
# $JGIT_OUTPUT et le code de sortie dans $JGIT_STATUS.
run_jgit() {
    local status=0
    local output

    printf '%s$ jgit %s\n' "$ASSERT_INDENT" "$*"
    # $JGIT_LAUNCHER est vide dans le cas nominal : jgit.sh est lance via son shebang.
    # shellcheck disable=SC2086
    output=$(cd "$SANDBOX/repo" && $JGIT_LAUNCHER "$(jgit_invoked_path)" "$@" < /dev/null 2>&1) || status=$?

    JGIT_OUTPUT="$output"
    JGIT_STATUS=$status

    printf '%s\n' "$output" | sed "s/^/${ASSERT_INDENT}| /"
    printf '%s(code de sortie : %s)\n' "$ASSERT_INDENT" "$status"
    return 0
}

# Variante de run_jgit qui garde separees la sortie standard (le document JSON,
# dans $SANDBOX/stdout.json) et la sortie d'erreur. $JGIT_OUTPUT contient les
# deux, pour que les verifications habituelles sur la sortie restent valables.
run_jgit_json() {
    local status=0

    printf '%s$ jgit %s   (sortie standard capturee a part)\n' "$ASSERT_INDENT" "$*"
    # shellcheck disable=SC2086
    (cd "$SANDBOX/repo" && $JGIT_LAUNCHER "$(jgit_invoked_path)" "$@" \
        < /dev/null > "$SANDBOX/stdout.json" 2> "$SANDBOX/stderr.txt") || status=$?

    JGIT_STDOUT=$(cat "$SANDBOX/stdout.json")
    JGIT_STDERR=$(cat "$SANDBOX/stderr.txt")
    JGIT_OUTPUT="$JGIT_STDERR
$JGIT_STDOUT"
    JGIT_STATUS=$status

    printf '%s\n' "$JGIT_STDERR" | sed "s/^/${ASSERT_INDENT}| /"
    printf '%s\n' "$JGIT_STDOUT" | sed "s/^/${ASSERT_INDENT}> /"
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

# Resout un conflit comme le ferait un developpeur (ou une IA) : ecrit la
# version retenue du fichier, puis le marque resolu.
repo_resolve_file() {
    local path="$1"
    local content="$2"

    printf '%s\n' "$content" > "$SANDBOX/repo/$path"
    repo_git add "$path"
    info "conflit resolu sur $path"
}

# Marque un fichier resolu tel quel, marqueurs de conflit compris.
repo_mark_resolved() {
    repo_git add "$1"
    info "$1 marque resolu tel quel"
}

repo_operation_state_file() {
    printf '%s/.git/jgit/operation.state' "$SANDBOX/repo"
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

# Remplace le depot de travail par un nouveau clone du remote, avec les options
# donnees (--depth, --single-branch…). C'est ainsi qu'arrive un agent de CI.
repo_reclone() {
    local conf="$SANDBOX/conf_local.sh.saved"

    cp "$SANDBOX/repo/.jgit/conf_local.sh" "$conf"
    rm -rf "$SANDBOX/repo"
    # file:// : --depth est ignore pour un chemin local.
    git clone --quiet "$@" "file://$SANDBOX/origin.git" "$SANDBOX/repo" 2>/dev/null || \
        assert_failed "clone du remote" "options : $*"
    mkdir -p "$SANDBOX/repo/.jgit"
    cp "$conf" "$SANDBOX/repo/.jgit/conf_local.sh"
    info "depot de travail reclone ($*)"
}

# Retire toute identite git : ni variables d'environnement, ni configuration,
# et interdiction a git d'en deviner une (nom d'hote, utilisateur systeme).
repo_remove_git_identity() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL
    git config --global --remove-section user 2>/dev/null
    git config --global user.useConfigOnly true
    info "aucune identite git configuree"
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

# Meme chose, au nom d'une personne : son nom est l'auteur du commit, son
# adresse <prenom en minuscules>@example.invalid.
github_commit_file_as() {
    local person="$1"
    shift
    local email
    email="$(printf '%s' "$person" | tr '[:upper:]' '[:lower:]')@example.invalid"
    GIT_AUTHOR_NAME="$person" GIT_AUTHOR_EMAIL="$email" github_commit_file "$@"
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
