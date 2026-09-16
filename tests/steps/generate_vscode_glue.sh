#!/bin/bash
#
# Genere tests/steps/vscode_glue.py a partir des phrases declarees par step_def
# dans tests/steps/*.steps.sh.
#
# Pourquoi : l'extension Cucumber de VS Code souligne toute etape dont elle ne
# trouve pas la definition, et elle ne sait pas lire du bash. Ce fichier lui
# redeclare les memes phrases dans un format qu'elle comprend (decorateurs a la
# behave). Il n'est jamais execute par les tests.
#
#   ./tests/steps/generate_vscode_glue.sh           regenere le fichier
#   ./tests/steps/generate_vscode_glue.sh --check   verifie qu'il est a jour

set -uo pipefail

STEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$STEPS_DIR/vscode_glue.py"

mode="write"
if [[ "${1:-}" == "--check" ]]; then
    mode="check"
elif [[ $# -gt 0 ]]; then
    printf "Usage : %s [--check]\n" "$0" >&2
    exit 1
fi

generate() {
    cat <<'HEADER'
# Fichier généré par tests/steps/generate_vscode_glue.sh — ne pas éditer.
#
# Ce module n'est jamais exécuté. Il existe uniquement pour l'extension Cucumber
# de VS Code, qui ne sait pas lire les définitions d'étapes écrites en bash : il
# lui redéclare les phrases de tests/steps/*.steps.sh dans un format qu'elle
# comprend, ce qui supprime les avertissements « Undefined step » et active
# l'autocomplétion des étapes.
#
# Les vraies définitions sont dans tests/steps/*.steps.sh.
# Après y avoir ajouté une phrase : ./tests/steps/generate_vscode_glue.sh


def given(expression):
    """Décorateur factice : seule l'extension Cucumber lit ce fichier."""

    def decorate(function):
        return function

    return decorate

HEADER

    local steps_file
    for steps_file in "$STEPS_DIR"/*.steps.sh; do
        [[ -e "$steps_file" ]] || continue
        awk -v source="tests/steps/$(basename "$steps_file")" '
            /^step_def "/ {
                line = $0
                sub(/^step_def "/, "", line)
                split(line, parts, /" /)
                phrase = parts[1]
                handler = parts[2]

                # Les marqueurs de step_def deviennent des Cucumber Expressions.
                gsub(/\{chaine\}/, "{string}", phrase)
                gsub(/\{texte\}/, "{string}", phrase)
                gsub(/\{nombre\}/, "{int}", phrase)

                printf "\n@given(\"%s\")\ndef %s(context):\n    \"\"\"Définie dans %s.\"\"\"\n", phrase, handler, source
            }
        ' "$steps_file"
    done
}

if [[ "$mode" == "check" ]]; then
    if [[ ! -f "$TARGET" ]]; then
        printf "%s est absent : lancez ./tests/steps/generate_vscode_glue.sh\n" "$TARGET" >&2
        exit 1
    fi
    if ! generate | diff -q - "$TARGET" >/dev/null; then
        printf "vscode_glue.py n'est plus a jour : lancez ./tests/steps/generate_vscode_glue.sh\n" >&2
        exit 1
    fi
    printf "vscode_glue.py est a jour.\n"
    exit 0
fi

generate > "$TARGET"
printf "Ecrit : %s (%s étapes)\n" "$TARGET" "$(grep -c '^@given' "$TARGET")"
