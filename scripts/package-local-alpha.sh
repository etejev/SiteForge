#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
DERIVED_DATA=${SITEFORGE_DERIVED_DATA:-${TMPDIR%/}/SiteForge/DerivedData}
OUT="$ROOT/.build/local-alpha"

cd "$ROOT"
if [[ ${SITEFORGE_LOCAL_ALPHA_BUILD_ONLY:-0} == 1 ]]; then
  print "Creating a source-review local alpha without running the deferred test gate."
  ./sf build
else
  ./sf verify
fi

app=$(find "$DERIVED_DATA/Build/Products" -type d -name 'SiteForge.app' -print -quit)
[[ -n "$app" ]] || { print -u2 "SiteForge.app was not produced."; exit 1; }

# Official/local-alpha packaging must never accidentally reuse experimental products.
if [[ -d "$app/Contents/Resources/ExperimentalTesting" ]] || \
   [[ $(/usr/libexec/PlistBuddy -c 'Print :SiteForgeExperimentalBuild' "$app/Contents/Info.plist" 2>/dev/null || print false) == true ]]; then
  print -u2 "Refusing to package experimental testing resources as an ordinary alpha."
  exit 1
fi

mkdir -p "$OUT"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || print dev)
archive="$OUT/SiteForge-$version-unsigned-alpha.zip"
ditto -c -k --keepParent "$app" "$archive"
/bin/zsh "$ROOT/scripts/write-portable-checksum.sh" "$archive"

print "Created local unsigned alpha:"
print "$archive"
print "This artifact was not published, Developer ID signed, or notarized."
