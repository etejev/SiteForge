#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

print "SiteForge project status"
print ""
if [[ -d .git ]]; then
  git status --short
else
  print "Git repository: not initialized"
fi

print ""
print "Queue summary"
rg -n '^## (READY|IN PROGRESS|BLOCKED|DONE)|^- \[[ x]\]' docs/CODEX_QUEUE.md || true

print ""
print "Open decisions"
rg -n '^## OD-|^Status:' docs/OPEN_DECISIONS.md || true

print ""
print "Last Codex result"
if [[ -f .codex-loop/last-message.md ]]; then
  tail -20 .codex-loop/last-message.md
else
  print "No automated Codex iteration has run."
fi

