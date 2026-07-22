#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
OUTPUT="$ROOT/docs/evidence/selection-model-foundation/measurements.json"
BINARY="${TMPDIR%/}/SiteForge/selection-model-evidence"

xcrun swiftc -O -swift-version 6 \
  "$ROOT/SiteForge/DocumentModel.swift" \
  "$ROOT/SiteForge/CanvasViewport.swift" \
  "$ROOT/SiteForge/CanvasRendererCore.swift" \
  "$ROOT/SiteForge/SelectionModel.swift" \
  "$ROOT/Benchmarks/SelectionModelFoundation/main.swift" \
  -o "$BINARY"
"$BINARY" > "$OUTPUT"
python3 "$ROOT/scripts/check-selection-model-evidence.py"
