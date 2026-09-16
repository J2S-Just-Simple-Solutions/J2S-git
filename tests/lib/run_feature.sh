#!/bin/bash
#
# Joue un fichier .feature. Utilise par tests/run.sh, mais appelable directement :
#
#   ./tests/lib/run_feature.sh tests/features/01_feature_vers_release.feature

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/bootstrap.sh"

if [[ $# -ne 1 ]]; then
    printf 'Usage : %s <fichier.feature>\n' "$0" >&2
    exit 1
fi

run_feature "$1"
