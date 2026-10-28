#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
scratch=$(mktemp -d)
trap 'rmdir "$scratch"' EXIT
set +e
message=$(SITEFORGE_VERIFICATION_RUNTIME="$scratch/missing" /bin/zsh "$ROOT/scripts/verification-python.sh" --check 2>&1)
runtime_status=$?
set -e
[[ $runtime_status == 2 && $message == *scripts/setup-verification-runtime.sh* ]] || exit 1
/bin/zsh "$ROOT/scripts/verification-python.sh" --check
print 'Verification runtime checks passed (missing prerequisite, isolated pinned runtime).'
