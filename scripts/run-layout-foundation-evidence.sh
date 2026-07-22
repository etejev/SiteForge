#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
BUILD_ROOT="$ROOT/.build/deterministic-layout-foundation"
OUTPUT=${1:-$ROOT/docs/evidence/deterministic-layout-foundation/raw-results.json}
EXECUTABLE="$BUILD_ROOT/siteforge-layout-foundation-evidence"

mkdir -p "$BUILD_ROOT" "${OUTPUT:h}"
cd "$ROOT"
xcrun swiftc -parse-as-library -O -swift-version 6 \
  -framework WebKit \
  SiteForge/DocumentModel.swift \
  SiteForge/LayoutEngine.swift \
  Benchmarks/AuthoringEngineRunway/RunwayBenchmarkSupport.swift \
  Benchmarks/DeterministicLayoutFoundation/main.swift \
  -o "$EXECUTABLE"
"$EXECUTABLE" --output "$OUTPUT"
