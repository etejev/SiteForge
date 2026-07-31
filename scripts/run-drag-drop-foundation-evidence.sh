#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
LOG=$(mktemp "${TMPDIR%/}/siteforge-drag-drop-evidence.XXXXXX")
trap 'rm -f "$LOG"' EXIT INT TERM

xcodebuild -project "$ROOT/SiteForge.xcodeproj" -scheme SiteForge -destination platform=macOS \
  -derivedDataPath "${TMPDIR%/}/SiteForge/DerivedData" test \
  -only-testing:SiteForgeTests/DragDropModelTests/testDragDropCapacityEvidence \
  2>&1 | tee "$LOG"
python3 "$ROOT/scripts/check-drag-drop-foundation-evidence.py" --record "$LOG"
