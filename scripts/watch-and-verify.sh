#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

WATCH_ROOTS=(SiteForge Tests Package.swift)
existing=()
for path in "${WATCH_ROOTS[@]}"; do
  [[ -e "$path" ]] && existing+=("$path")
done

if (( ${#existing[@]} == 0 )); then
  print -u2 "No SiteForge source tree exists yet. Create the Xcode project first."
  exit 2
fi

fingerprint() {
  find "${existing[@]}" -type f \( -name '*.swift' -o -name '*.plist' -o -name '*.entitlements' -o -name '*.xcconfig' \) \
    -exec stat -f '%m %z %N' {} + 2>/dev/null | sort | shasum | awk '{print $1}'
}

last=$(fingerprint)
print "Watching SiteForge sources. Press Control-C to stop."
./sf verify || true

while true; do
  sleep 1
  current=$(fingerprint)
  if [[ "$current" != "$last" ]]; then
    last="$current"
    print "\nChange detected — verifying…"
    if ./sf verify; then
      print "Verification passed."
    else
      print -u2 "Verification failed. Waiting for the next change."
    fi
  fi
done

