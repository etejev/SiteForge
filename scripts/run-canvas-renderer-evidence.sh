#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
BUILD_ROOT="$ROOT/.build/canvas-renderer-foundation"
OUTPUT=${1:-$ROOT/docs/evidence/canvas-renderer-foundation/raw-results.json}
EXECUTABLE="$BUILD_ROOT/siteforge-canvas-renderer-evidence"

mkdir -p "$BUILD_ROOT" "${OUTPUT:h}"
cd "$ROOT"
xcrun swiftc -parse-as-library -O -swift-version 6 \
  -framework CoreVideo \
  SiteForge/StrictDecoding.swift \
  SiteForge/DiagnosticSupport.swift \
  SiteForge/DocumentModel.swift \
  SiteForge/CanvasViewport.swift \
  SiteForge/CanvasRendererCore.swift \
  Benchmarks/AuthoringEngineRunway/RunwayBenchmarkSupport.swift \
  Benchmarks/CanvasRendererFoundation/main.swift \
  -o "$EXECUTABLE"
"$EXECUTABLE" --output "$OUTPUT"
