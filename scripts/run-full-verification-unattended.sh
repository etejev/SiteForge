#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
# Launch once; the collector owns its lifetime after this command returns.
exec /usr/bin/env python3 "$ROOT/scripts/unattended-verification.py" --root "$ROOT" "$@"
