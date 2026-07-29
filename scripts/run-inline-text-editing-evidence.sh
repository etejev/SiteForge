#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
LOG=$(mktemp "${TMPDIR%/}/siteforge-inline-text-evidence.XXXXXX")
trap 'rm -f "$LOG"' EXIT INT TERM

xcodebuild -project "$ROOT/SiteForge.xcodeproj" -scheme SiteForge -destination platform=macOS \
  -derivedDataPath "${TMPDIR%/}/SiteForge/DerivedData" test \
  -only-testing:SiteForgeTests/InlineTextEditingModelTests/testPreparationCapacityAt100And10000ObjectsIsDeterministicAndBounded \
  2>&1 | tee "$LOG"
python3 "$ROOT/scripts/check-inline-text-editing-evidence.py" --record "$LOG"
