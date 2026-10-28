#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
RUNTIME="$ROOT/.build/verification-python"
PYTHON=${SITEFORGE_VERIFICATION_BOOTSTRAP_PYTHON:-/usr/bin/python3}
"$PYTHON" -m venv "$RUNTIME"
"$RUNTIME/bin/python3" -m pip install --disable-pip-version-check -r "$ROOT/scripts/verification-requirements.txt"
/bin/zsh "$ROOT/scripts/verification-python.sh" --check
