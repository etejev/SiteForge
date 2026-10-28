#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
RUNTIME=${SITEFORGE_VERIFICATION_RUNTIME:-"$ROOT/.build/verification-python"}
PYTHON="$RUNTIME/bin/python3"
if [[ ! -x "$PYTHON" ]] || ! "$PYTHON" -I - "$ROOT/scripts/verification-requirements.txt" <<'PY'
import sys
from pathlib import Path
try:
    import PIL
    pin = next(line.strip().split("==", 1)[1] for line in Path(sys.argv[1]).read_text().splitlines()
               if line.startswith("Pillow=="))
    assert sys.prefix != sys.base_prefix and PIL.__version__ == pin
except (ImportError, AssertionError, StopIteration):
    raise SystemExit(2)
PY
then
  print -u2 'Verification image runtime missing or outdated. Run: /bin/zsh scripts/setup-verification-runtime.sh'
  exit 2
fi
[[ ${1:-} == --check ]] && exit 0
exec "$PYTHON" -I "$@"
