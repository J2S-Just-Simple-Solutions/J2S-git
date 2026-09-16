#!/bin/bash
#
# Assertions generiques.
#
# Toute assertion en echec affiche son contexte puis interrompt immediatement le
# test courant (code 1), ce qui evite de derouler un scenario sur un etat deja
# invalide.

TEST_ASSERTIONS=0
TEST_NAME="${TEST_NAME:-}"

# Indentation des lignes de detail (le moteur Gherkin l'augmente sous chaque etape).
ASSERT_INDENT="${ASSERT_INDENT:-    }"

# Titre du test, affiche en tete de scenario.
test_name() {
    TEST_NAME="$1"
    printf '### %s\n' "$TEST_NAME"
}

# Etape narrative : sert a relire un scenario en echec.
step() {
    printf '\n--- %s\n' "$*"
}

# Information libre, affichee telle quelle.
info() {
    printf '%s%s\n' "$ASSERT_INDENT" "$*"
}

assert_ok() {
    TEST_ASSERTIONS=$((TEST_ASSERTIONS + 1))
    printf '%s[OK] %s\n' "$ASSERT_INDENT" "$1"
}

# Echec immediat du test.
assert_failed() {
    local label="$1"
    shift
    TEST_ASSERTIONS=$((TEST_ASSERTIONS + 1))
    printf '%s[KO] %s\n' "$ASSERT_INDENT" "$label" >&2
    local line
    for line in "$@"; do
        # sed : les details sur plusieurs lignes restent alignes.
        printf '%s\n' "$line" | sed "s/^/${ASSERT_INDENT}     /" >&2
    done
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="${3:-valeur attendue}"

    if [[ "$expected" == "$actual" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "attendu : $expected" "obtenu  : $actual"
    fi
}

assert_not_equals() {
    local unexpected="$1"
    local actual="$2"
    local label="${3:-valeur differente}"

    if [[ "$unexpected" != "$actual" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "valeur interdite : $unexpected"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-texte [$needle] present}"

    if [[ "$haystack" == *"$needle"* ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "texte introuvable : $needle" "--- contenu ---" "$haystack"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-texte [$needle] absent}"

    if [[ "$haystack" != *"$needle"* ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "texte present alors qu'il ne devrait pas : $needle" "--- contenu ---" "$haystack"
    fi
}

assert_matches() {
    local text="$1"
    local pattern="$2"
    local label="${3:-motif [$pattern] trouve}"

    if printf '%s' "$text" | grep -Eq "$pattern"; then
        assert_ok "$label"
    else
        assert_failed "$label" "motif introuvable : $pattern" "--- contenu ---" "$text"
    fi
}

assert_file_exists() {
    local path="$1"
    local label="${2:-le fichier $path existe}"

    if [[ -e "$path" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "chemin absent : $path"
    fi
}

assert_file_missing() {
    local path="$1"
    local label="${2:-absence du fichier $path}"

    if [[ ! -e "$path" ]]; then
        assert_ok "$label"
    else
        assert_failed "$label" "chemin present : $path"
    fi
}
