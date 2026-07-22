#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
LOG=$(mktemp "${TMPDIR%/}/siteforge-insertion-evidence.XXXXXX")
trap 'rm -f "$LOG"' EXIT INT TERM

xcodebuild -project "$ROOT/SiteForge.xcodeproj" -scheme SiteForge -destination platform=macOS \
  -derivedDataPath "${TMPDIR%/}/SiteForge/DerivedData" test \
  -only-testing:SiteForgeTests/InsertionModelTests/testProductionCapacityForHundredAndTenThousandObjects \
  2>&1 | tee "$LOG"
python3 "$ROOT/scripts/check-insertion-foundation-evidence.py" --record "$LOG"
