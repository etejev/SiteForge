#!/usr/bin/env python3
"""Validate retained SF-AUTHORING-003 evidence without rerunning measurements."""

from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs/evidence/canvas-renderer-foundation/raw-results.json"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


try:
    raw = RESULTS.read_text()
    report = json.loads(raw)
except (OSError, json.JSONDecodeError) as error:
    fail(f"Canvas renderer evidence is missing or corrupt: {error}")

if report.get("schemaVersion") != 1:
    fail("Canvas renderer evidence schema must remain version 1.")
if "/Users/" in raw or "file://" in raw:
    fail("Canvas renderer evidence contains a private absolute path.")
for key in ["hardwareModel", "architecture", "physicalMemoryBytes", "macOSVersion", "xcodeVersion", "sdkVersion", "swiftVersion", "buildConfiguration"]:
    if not report.get("environment", {}).get(key):
        fail(f"Canvas renderer environment is missing {key}.")

correctness = report.get("correctness", {})
for key in ["deterministicDigestsStable", "overlayExcludedFromPreview", "cancellationObserved", "staleResultRejected", "compositorOnlyHasNoDirtyRegions"]:
    if correctness.get(key) is not True:
        fail(f"Canvas renderer correctness gate failed: {key}")
if not 0 < correctness.get("maximumTileCount", 0) <= 512:
    fail("Canvas renderer tile evidence is missing or unbounded.")
if not 0 < correctness.get("maximumAccessibilityCount", 0) <= 256:
    fail("Canvas renderer accessibility evidence is missing or unbounded.")
if correctness.get("displayLinkFrames", 0) <= 0 or correctness.get("displayLinkStalls", -1) < 0:
    fail("Canvas renderer display-link evidence is incomplete.")

measurements = report.get("measurements", [])
expected = {(operation, count) for operation in ["full initial plan", "one-object dirty plan", "hit test"] for count in [100, 10_000]}
actual = {(item.get("operation"), item.get("fixtureCount")) for item in measurements}
if actual != expected:
    fail(f"Canvas renderer measurements are incomplete: {sorted(expected - actual)}")
for item in measurements:
    samples = item.get("samplesMilliseconds", [])
    if len(samples) != item.get("repetitionCount") or not samples:
        fail("Canvas renderer raw samples are incomplete.")
    timing = item.get("timing", {})
    if timing.get("p50Milliseconds", -1) < 0 or timing.get("p95Milliseconds", -1) < timing.get("p50Milliseconds", 0):
        fail("Canvas renderer percentile ordering is invalid.")
    for key in ["residentBytesBefore", "residentBytesAfter", "processPeakResidentBytes"]:
        if item.get(key, 0) <= 0:
            fail(f"Canvas renderer memory evidence is missing {key}.")
if len(report.get("limitations", [])) < 6:
    fail("Canvas renderer limitations are incomplete.")

print(f"Canvas renderer evidence checks passed for {len(measurements)} measurements.")
