#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

failed=0
required=(
  AGENTS.md
  docs/CODEX_QUEUE.md
  docs/IMPLEMENTATION_STATUS.md
  docs/OPEN_DECISIONS.md
  docs/OWNER_ACTIONS.md
  docs/CHANGELOG.md
)

for required_path in "${required[@]}"; do
  if [[ ! -s "$required_path" ]]; then
    print -u2 "Required project-control file is missing or empty: $required_path"
    failed=1
  fi
done

if rg -n --hidden \
  -g '!**/.git/**' -g '!**/.build/**' \
  '(BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|APPLE_ID_PASSWORD\s*=|NOTARY_PASSWORD\s*=|ghp_[A-Za-z0-9]{20,})' .; then
  print -u2 "Potential credential material was found. Remove it before continuing."
  failed=1
fi

if rg -n --hidden -g '!**/.git/**' -g '!**/.build/**' \
  '(TODO|FIXME):?\s*$' SiteForge Tests 2>/dev/null; then
  print -u2 "Empty TODO/FIXME markers are not allowed; include an issue or requirement ID."
  failed=1
fi

if [[ -d .git ]] && ! git diff --check; then
  failed=1
fi

(( failed == 0 )) || exit 1
print "Repository checks passed."
