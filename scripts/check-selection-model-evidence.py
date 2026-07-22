#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "docs/evidence/selection-model-foundation/measurements.json"
data = json.loads(path.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0402-00{i}" for i in range(1, 9)]
assert data["environment"]["hardware"] and data["environment"]["os"]
assert len(data["measurements"]) == 4
assert {(item["name"], item["objectCount"]) for item in data["measurements"]} == {
    ("selection-command", 100), ("selection-command", 10_000),
    ("selection-overlay-plan", 100), ("selection-overlay-plan", 10_000),
}
for item in data["measurements"]:
    assert len(item["samples"]) == 15
    assert item["p95"] >= 0
assert data["maximumResidentBytes"] > 0
assert len(data["stableDigests"]) == 2 and all(data["stableDigests"])
assert len(data["limitations"]) >= 3
print("Selection-model evidence checks passed for four measurements.")
