#!/bin/bash
#
# A sourcer en tete de chaque test. Prepare les chemins, charge les helpers et
# installe le nettoyage automatique du bac a sable.

set -uo pipefail

JGIT_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JGIT_ROOT="$(cd "$JGIT_TESTS_DIR/.." && pwd)"
JGIT_BIN="$JGIT_ROOT/jgit.sh"

# jgit.sh est lance via son shebang, exactement comme le ferait l'alias jgit.
# Si le bit d'execution manque, on repasse par bash.
JGIT_LAUNCHER=""

if [[ ! -f "$JGIT_BIN" ]]; then
    printf 'jgit.sh introuvable dans %s\n' "$JGIT_ROOT" >&2
    exit 1
fi

if [[ ! -x "$JGIT_BIN" ]]; then
    JGIT_LAUNCHER="bash"
fi

export JGIT_TESTS_DIR JGIT_ROOT JGIT_BIN JGIT_LAUNCHER

# shellcheck source=assert.sh
source "$JGIT_TESTS_DIR/lib/assert.sh"
# shellcheck source=sandbox.sh
source "$JGIT_TESTS_DIR/lib/sandbox.sh"
# shellcheck source=git_assert.sh
source "$JGIT_TESTS_DIR/lib/git_assert.sh"
# shellcheck source=interactive.sh
source "$JGIT_TESTS_DIR/lib/interactive.sh"
# shellcheck source=gherkin.sh
source "$JGIT_TESTS_DIR/lib/gherkin.sh"

# Definitions d'etapes utilisees par les fichiers .feature.
for steps_file in "$JGIT_TESTS_DIR"/steps/*.steps.sh; do
    [[ -e "$steps_file" ]] || continue
    # shellcheck source=/dev/null
    source "$steps_file"
done
unset steps_file

trap sandbox_cleanup EXIT

# A appeler en fin de scenario : resume et code de sortie 0.
test_passed() {
    printf '\n=== %s : OK (%s assertions)\n' "${TEST_NAME:-test}" "$TEST_ASSERTIONS"
    exit 0
}
