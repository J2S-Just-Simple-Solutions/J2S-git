#!/bin/bash
#
# Scenarios interactifs : jgit est lance dans un vrai pseudo-terminal, ce qui
# permet de verifier que chaque question est bien posee et d'y repondre comme le
# ferait un developpeur.
#
# Usage :
#   expect_reset
#   expect_wait "Souhaitez-vous continuer"   # attend le texte (regex)
#   expect_answer "y"                        # tape la reponse + Entree
#   run_jgit_interactive feature start TEST-1

EXPECT_STEPS_FILE=""
EXPECT_TIMEOUT="${EXPECT_TIMEOUT:-60}"

expect_reset() {
    EXPECT_STEPS_FILE="$SANDBOX/expect-steps.txt"
    : > "$EXPECT_STEPS_FILE"
}

# Attend une expression reguliere dans la sortie du process.
expect_wait() {
    if [[ -z "$EXPECT_STEPS_FILE" ]]; then
        expect_reset
    fi
    printf 'expect\t%s\n' "$1" >> "$EXPECT_STEPS_FILE"
}

# Repond a la question courante (le retour chariot est ajoute).
expect_answer() {
    if [[ -z "$EXPECT_STEPS_FILE" ]]; then
        expect_reset
    fi
    printf 'send\t%s\n' "$1" >> "$EXPECT_STEPS_FILE"
}

# Lance jgit en mode interactif et deroule le scenario accumule.
#
# Codes de sortie particuliers :
#   90  une question attendue n'a jamais ete posee
#   91  timeout (jgit attend probablement une reponse non prevue au scenario)
run_jgit_interactive() {
    local status=0
    local output_file="$SANDBOX/expect-output.txt"

    if [[ -z "$EXPECT_STEPS_FILE" ]]; then
        expect_reset
    fi

    printf '%s$ jgit %s   (mode interactif)\n' "$ASSERT_INDENT" "$*"
    (
        cd "$SANDBOX/repo" || exit 92
        # shellcheck disable=SC2086
        python3 "$JGIT_TESTS_DIR/lib/expect.py" \
            --steps "$EXPECT_STEPS_FILE" \
            --timeout "$EXPECT_TIMEOUT" \
            --output "$output_file" \
            -- $JGIT_LAUNCHER "$JGIT_BIN" "$@"
    ) || status=$?

    if [[ -f "$output_file" ]]; then
        JGIT_OUTPUT=$(cat "$output_file")
    else
        JGIT_OUTPUT=""
    fi
    JGIT_STATUS=$status

    printf '%s\n' "$JGIT_OUTPUT" | sed "s/^/${ASSERT_INDENT}| /"
    printf '%s(code de sortie : %s)\n' "$ASSERT_INDENT" "$status"

    case $status in
        90) assert_failed "scenario interactif" "une question attendue n'a jamais ete posee" ;;
        91) assert_failed "scenario interactif" "timeout : jgit attend une reponse non prevue au scenario" ;;
        92) assert_failed "scenario interactif" "erreur du pilote de pseudo-terminal" ;;
    esac

    return 0
}
