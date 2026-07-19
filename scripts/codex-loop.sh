#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
LIMIT=${1:-5}
CODEX_BIN=${SITEFORGE_CODEX_BIN:-}
LOCK="$ROOT/.codex-loop/running"

[[ "$LIMIT" == <-> ]] && (( LIMIT > 0 )) || { print -u2 "Iteration count must be a positive integer."; exit 2; }

if [[ -z "$CODEX_BIN" ]]; then
  if command -v codex >/dev/null 2>&1; then
    CODEX_BIN=$(command -v codex)
  elif [[ -x /Applications/ChatGPT.app/Contents/Resources/codex ]]; then
    CODEX_BIN=/Applications/ChatGPT.app/Contents/Resources/codex
  else
    print -u2 "Codex CLI was not found."
    exit 2
  fi
fi

mkdir -p "$ROOT/.codex-loop"
if ! mkdir "$LOCK" 2>/dev/null; then
  print -u2 "Another SiteForge Codex loop appears to be running: $LOCK"
  exit 2
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

for (( i=1; i<=LIMIT; i++ )); do
  print "Codex iteration $i of $LIMIT"
  output="$ROOT/.codex-loop/iteration-$i.md"
  "$CODEX_BIN" exec -C "$ROOT" -s workspace-write -o "$output" - < "$ROOT/docs/CODEX_NEXT_PROMPT.md"

  if rg -q '^CODEX_LOOP_STATUS: (BLOCKED|DONE|VERIFY_FAILED)$' "$output"; then
    status=$(rg -o '^CODEX_LOOP_STATUS: [A-Z_]+' "$output" | tail -1)
    print "$status — stopping."
    exit 0
  fi

  if ! rg -q '^CODEX_LOOP_STATUS: CONTINUE$' "$output"; then
    print -u2 "Codex did not return a recognized loop status. Review $output."
    exit 1
  fi
done

print "Iteration limit reached. Review the queue and run ./sf loop again when ready."

