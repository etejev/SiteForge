#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
BUILD_ROOT="$ROOT/.build/authoring-engine-runway"
OUTPUT=${1:-$ROOT/docs/evidence/authoring-engine-runway/raw-results.json}
EXECUTABLE="$BUILD_ROOT/siteforge-authoring-runway"

mkdir -p "$BUILD_ROOT" "${OUTPUT:h}"

sources=(
  Benchmarks/AuthoringEngineRunway/RunwayCore.swift
  Benchmarks/AuthoringEngineRunway/RunwayHTMLExport.swift
  Benchmarks/AuthoringEngineRunway/RunwayBenchmarkSupport.swift
  Benchmarks/AuthoringEngineRunway/RunwayCanvasBenchmarks.swift
  Benchmarks/AuthoringEngineRunway/RunwayBrowserOracle.swift
  SiteForge/StrictDecoding.swift
  SiteForge/DocumentModel.swift
  SiteForge/CommandKernel.swift
  SiteForge/IdentityBoundFileSystem.swift
  SiteForge/ProjectPackage.swift
  SiteForge/ProjectResources.swift
  SiteForge/PersistedHistory.swift
  Benchmarks/AuthoringEngineRunway/main.swift
)

cd "$ROOT"
xcrun swiftc -parse-as-library -O -swift-version 6 \
  -framework AppKit -framework SwiftUI -framework QuartzCore -framework Metal -framework WebKit \
  "${sources[@]}" -o "$EXECUTABLE"
"$EXECUTABLE" --output "$OUTPUT"
