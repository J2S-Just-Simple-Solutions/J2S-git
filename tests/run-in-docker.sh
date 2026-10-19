#!/bin/bash
#
# Joue la suite de tests jgit sous Linux (Debian, bash 5.2), dans Docker.
#
#   ./tests/run-in-docker.sh                 toute la suite
#   ./tests/run-in-docker.sh demo -v         mêmes arguments que tests/run.sh
#
# Le dépôt est monté en lecture seule : les tests travaillent dans des bacs à
# sable créés sous /tmp, dans le conteneur.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
IMAGE="${JGIT_TEST_IMAGE:-jgit-tests:bookworm}"

if ! command -v docker >/dev/null 2>&1; then
    printf 'docker est requis pour jouer les tests sous Linux.\n' >&2
    exit 1
fi

docker build --quiet -t "$IMAGE" -f "$TESTS_DIR/docker/Dockerfile" "$TESTS_DIR/docker" >/dev/null || exit 1

tty_flag=()
if [[ -t 1 ]]; then
    tty_flag=(-t)
fi

exec docker run --rm ${tty_flag[@]+"${tty_flag[@]}"} -v "$ROOT_DIR:/jgit:ro" "$IMAGE" ./tests/run.sh "$@"
