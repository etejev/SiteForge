#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

WATCH_ROOTS=(SiteForge Tests Package.swift)
existing=()
for watch_root in "${WATCH_ROOTS[@]}"; do
  [[ -e "$watch_root" ]] && existing+=("$watch_root")
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
./sf build || true

while true; do
  sleep 1
  current=$(fingerprint)
  if [[ "$current" != "$last" ]]; then
    last="$current"
    print "\nChange detected — building…"
    if ./sf build; then
      print "Build passed."
    else
      print -u2 "Build failed. Waiting for the next change."
    fi
  fi
done

