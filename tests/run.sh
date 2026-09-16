#!/bin/bash
#
# Lanceur de la suite de tests jgit.
#
#   ./tests/run.sh                    lance tous les scenarios
#   ./tests/run.sh feature_release    ne lance que les scenarios correspondants
#   ./tests/run.sh -v                 affiche la sortie complete de chaque test
#   ./tests/run.sh -k                 conserve les bacs a sable (debug)
#   ./tests/run.sh -l                 liste les scenarios disponibles

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURES_DIR="$TESTS_DIR/features"
CASES_DIR="$TESTS_DIR/cases"

verbose=0
keep=0
list_only=0
filters=()
filter_count=0

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) verbose=1; shift ;;
        -k|--keep)    keep=1; shift ;;
        -l|--list)    list_only=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           printf 'Option inconnue : %s\n' "$1" >&2; usage >&2; exit 1 ;;
        *)            filters[$filter_count]="$1"; filter_count=$((filter_count + 1)); shift ;;
    esac
done

# Nom affiche d'un fichier de test.
test_display_name() {
    local file="$1"
    local name
    name=$(basename "$file")
    name="${name%.feature}"
    name="${name%.test.sh}"
    printf '%s' "$name"
}

selected=()
selected_count=0
for test_file in "$FEATURES_DIR"/*.feature "$CASES_DIR"/*.test.sh; do
    [[ -e "$test_file" ]] || continue
    name=$(test_display_name "$test_file")
    if [[ $filter_count -gt 0 ]]; then
        keep_it=0
        for filter in "${filters[@]}"; do
            case "$name" in
                *"$filter"*) keep_it=1 ;;
            esac
        done
        [[ $keep_it -eq 1 ]] || continue
    fi
    selected[$selected_count]="$test_file"
    selected_count=$((selected_count + 1))
done

if [[ $selected_count -eq 0 ]]; then
    printf 'Aucun scenario a executer.\n' >&2
    exit 1
fi

if [[ $list_only -eq 1 ]]; then
    for test_file in "${selected[@]}"; do
        printf '%s\n' "$(test_display_name "$test_file")"
    done
    exit 0
fi

# Prerequis : jgit s'appuie sur git et le pilote interactif sur python3.
for binary in git python3; do
    if ! command -v "$binary" >/dev/null 2>&1; then
        printf '%s est requis pour lancer les tests.\n' "$binary" >&2
        exit 1
    fi
done

log_dir=$(mktemp -d "${TMPDIR:-/tmp}/jgit-test-logs.XXXXXX")
failures=0
passed=0

printf '\n=== Suite de tests jgit (%s scenario(s)) ===\n\n' "$selected_count"

for test_file in "${selected[@]}"; do
    name=$(test_display_name "$test_file")
    log_file="$log_dir/$name.log"
    start=$(date +%s)

    # Un .feature passe par le moteur Gherkin, un .test.sh est un script bash.
    case "$test_file" in
        *.feature) runner=("${BASH:-bash}" "$TESTS_DIR/lib/run_feature.sh" "$test_file") ;;
        *)         runner=("${BASH:-bash}" "$test_file") ;;
    esac

    printf '%-52s ' "$name"

    status=0
    if [[ $verbose -eq 1 ]]; then
        printf '\n'
        JGIT_TEST_KEEP="$keep" "${runner[@]}" 2>&1 | tee "$log_file"
        status=${PIPESTATUS[0]}
        printf '%-52s ' "$name"
    else
        JGIT_TEST_KEEP="$keep" "${runner[@]}" > "$log_file" 2>&1 || status=$?
    fi

    duration=$(( $(date +%s) - start ))

    if [[ $status -eq 0 ]]; then
        printf 'OK   (%ss)\n' "$duration"
        passed=$((passed + 1))
    else
        printf 'ECHEC (%ss)\n' "$duration"
        failures=$((failures + 1))
        if [[ $verbose -eq 0 ]]; then
            printf '\n----- sortie de %s -----\n' "$name"
            cat "$log_file"
            printf -- '----- fin de %s -----\n\n' "$name"
        fi
    fi
done

printf '\n=== Resultat : %s reussi(s), %s echec(s) ===\n' "$passed" "$failures"
printf 'Journaux : %s\n\n' "$log_dir"

[[ $failures -eq 0 ]]
