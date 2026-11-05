#!/bin/bash
# Le script reste autonome ; le pilote Python fournit un vrai terminal.
set -uo pipefail
exec python3 "$(dirname "$0")/../migration.py" "${BASH:-/bin/bash}"
