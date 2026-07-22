#!/usr/bin/env python3
"""Validate retained SF-AUTHORING-002 evidence without rerunning measurements."""

from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs/evidence/deterministic-layout-foundation/raw-results.json"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


try:
    raw = RESULTS.read_text()
    report = json.loads(raw)
except (OSError, json.JSONDecodeError) as error:
    fail(f"Deterministic layout evidence is missing or corrupt: {error}")

if report.get("schemaVersion") != 1:
    fail("Deterministic layout evidence schema must remain version 1.")
if "/Users/" in raw or "file://" in raw:
    fail("Deterministic layout evidence contains a machine-specific absolute path.")

environment = report.get("environment", {})
for key in [
    "hardwareModel", "architecture", "physicalMemoryBytes", "macOSVersion",
    "xcodeVersion", "sdkVersion", "swiftVersion", "buildConfiguration",
]:
    if not environment.get(key):
        fail(f"Deterministic layout environment is missing {key}.")

correctness = report.get("correctness", {})
for key in [
    "repeatedDigestsStable", "cancellationObserved", "staleResultRejected",
    "webKitExcludedFromProductionCore",
]:
    if correctness.get(key) is not True:
        fail(f"Deterministic layout correctness gate failed: {key}")
if correctness.get("browserParityWidths") != [320, 768, 1440]:
    fail("Responsive browser-parity widths are incomplete.")
if correctness.get("browserParityMaximumPointError", 1) > 0.51:
    fail("Responsive browser parity exceeds 0.51 point.")
large = correctness.get("largeFixtureBrowserParityMaximumPointError", {})
if set(large) != {"100", "10000"} or any(value > 0.51 for value in large.values()):
    fail("Large-fixture browser parity is incomplete or outside tolerance.")

measurements = report.get("measurements", [])
expected = {
    ("layout", "Production deterministic layout core", count)
    for count in (100, 10_000)
} | {
    ("layout-oracle", "Ephemeral WebKit HTML/CSS geometry oracle", count)
    for count in (100, 10_000)
}
actual = {(item.get("domain"), item.get("alternative"), item.get("fixtureCount")) for item in measurements}
if actual != expected:
    fail(f"Deterministic layout measurements are incomplete: {sorted(expected - actual)}")
for item in measurements:
    count = item.get("repetitionCount", 0)
    samples = item.get("samplesMilliseconds", [])
    timing = item.get("timing", {})
    if count <= 0 or len(samples) != count:
        fail("A deterministic layout measurement does not retain every raw sample.")
    if timing.get("p50Milliseconds", -1) < 0 or timing.get("p95Milliseconds", -1) < timing.get("p50Milliseconds", 0):
        fail("A deterministic layout measurement has invalid percentile ordering.")
    for key in ["residentBytesBefore", "residentBytesAfter", "processPeakResidentBytes"]:
        if item.get(key, 0) <= 0:
            fail(f"A deterministic layout measurement is missing memory evidence: {key}")
    if item.get("domain") == "layout" and not item.get("deterministicDigest"):
        fail("Production deterministic layout evidence is missing a stable digest.")

if len(report.get("limitations", [])) < 6:
    fail("Deterministic layout evidence limitations are incomplete.")

print(f"Deterministic layout evidence checks passed for {len(measurements)} measurements.")
