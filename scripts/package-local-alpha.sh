#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
DERIVED_DATA=${SITEFORGE_DERIVED_DATA:-${TMPDIR%/}/SiteForge/DerivedData}
OUT="$ROOT/.build/local-alpha"

cd "$ROOT"
./sf verify

app=$(find "$DERIVED_DATA/Build/Products" -type d -name 'SiteForge.app' -print -quit)
[[ -n "$app" ]] || { print -u2 "SiteForge.app was not produced."; exit 1; }

mkdir -p "$OUT"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || print dev)
archive="$OUT/SiteForge-$version-unsigned-alpha.zip"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"

print "Created local unsigned alpha:"
print "$archive"
print "This artifact was not published, Developer ID signed, or notarized."
