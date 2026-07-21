#!/usr/bin/env python3
"""Validate retained SF-AUTHORING-000 evidence without rerunning measurements."""

from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs/evidence/authoring-engine-runway/raw-results.json"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


try:
    raw = RESULTS.read_text()
    report = json.loads(raw)
except (OSError, json.JSONDecodeError) as error:
    fail(f"Authoring runway results are missing or corrupt: {error}")

if report.get("schemaVersion") != 1:
    fail("Authoring runway result schema must remain version 1.")
if "/Users/" in raw or "file://" in raw:
    fail("Authoring runway evidence contains a machine-specific absolute path.")

environment = report.get("environment", {})
for key in [
    "hardwareModel", "architecture", "physicalMemoryBytes", "macOSVersion",
    "xcodeVersion", "sdkVersion", "swiftVersion", "buildConfiguration",
]:
    if not environment.get(key):
        fail(f"Authoring runway environment is missing {key}.")

correctness = report.get("correctness", {})
for key in [
    "overlayContentDigestUnchanged", "nativeMaterialPassThrough",
    "repeatedLayoutDigestStable", "invalidInputRejected", "unsupportedInputRejected",
    "cancellationObserved", "staleResultRejected",
]:
    if correctness.get(key) is not True:
        fail(f"Authoring runway correctness gate failed: {key}")
for key in [
    "coordinateMaximumRoundTripError", "zoomAnchorMaximumError", "panDeltaMaximumError",
]:
    if correctness.get(key, 1) > 1e-9:
        fail(f"Authoring runway coordinate tolerance failed: {key}")
if correctness.get("browserParityMaximumPointError", 1) > 0.51:
    fail("Authoring runway responsive browser parity exceeds 0.51 point.")
large_parity = correctness.get("largeFixtureBrowserParityMaximumPointError", {})
if set(large_parity) != {"100", "10000"} or any(value > 0.51 for value in large_parity.values()):
    fail("Authoring runway large-fixture browser parity is incomplete or outside tolerance.")

measurements = report.get("measurements", [])
required = {
    ("canvas", "AppKit immediate drawing", "full bitmap raster", count)
    for count in (100, 10_000)
} | {
    ("canvas", "SwiftUI Canvas", "full ImageRenderer raster", count)
    for count in (100, 10_000)
} | {
    ("canvas", "Core Animation layer per object", "full layer-tree raster", count)
    for count in (100, 10_000)
} | {
    ("canvas", "Metal data/command runway", "single-buffer-update command round trip", count)
    for count in (100, 10_000)
} | {
    ("layout", "SiteForge deterministic subset", "complete layout", count)
    for count in (100, 10_000)
} | {
    ("layout", "WebKit HTML/CSS oracle", "load DOM and read all frames", count)
    for count in (100, 10_000)
}
actual = {
    (item.get("domain"), item.get("alternative"), item.get("operation"), item.get("fixtureCount"))
    for item in measurements
}
missing = required - actual
if missing:
    fail(f"Authoring runway measurements are incomplete: {sorted(missing)}")
for item in measurements:
    timing = item.get("timing", {})
    if item.get("repetitionCount", 0) <= 0 or timing.get("p50Milliseconds", -1) < 0:
        fail("Authoring runway measurement has invalid repetitions or timing.")
    if len(item.get("samplesMilliseconds", [])) != item.get("repetitionCount"):
        fail("Authoring runway measurement does not retain every raw timing sample.")
    if timing.get("p95Milliseconds", -1) < timing.get("p50Milliseconds", 0):
        fail("Authoring runway measurement has invalid percentile ordering.")
    for key in ["residentBytesBefore", "residentBytesAfter", "processPeakResidentBytes"]:
        if item.get(key, 0) <= 0:
            fail(f"Authoring runway measurement is missing memory evidence: {key}")

resources = report.get("resourceEvidence", {})
if resources.get("resourceCount") != 500 or resources.get("bytesPerResource", 0) < 32 * 1024:
    fail("Authoring runway does not retain a representative 500-asset fixture.")
if resources.get("totalResourceBytes", 0) <= resources.get("packageParserLimitBytes", 0):
    fail("Authoring runway resource evidence does not exceed inline package capacity.")
for key in [
    "deterministicIndex", "lazyReadMatched", "fixtureConstructionExcludedFromCanvasAndLayoutMeasurements",
]:
    if resources.get(key) is not True:
        fail(f"Authoring runway resource gate failed: {key}")

if len(report.get("limitations", [])) < 6:
    fail("Authoring runway limitations are incomplete.")

print(f"Authoring runway evidence checks passed for {len(measurements)} measurements.")
