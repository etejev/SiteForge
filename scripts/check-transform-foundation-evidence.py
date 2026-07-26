#!/usr/bin/env python3
import ast
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/evidence/geometry-transform-foundation/measurements.json"


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def record(log_path: Path) -> None:
    text = log_path.read_text()
    pattern = re.compile(r"TRANSFORM_EVIDENCE count=(\d+) prepare=(\[[^\n]+?\])")
    measurements = []
    for match in pattern.finditer(text):
        samples = [float(value) for value in ast.literal_eval(match.group(2))]
        measurements.append({
            "name": "transform-prepare",
            "objectCount": int(match.group(1)),
            "unit": "milliseconds",
            "samples": samples,
            "p95": max(samples),
        })
    memory = re.search(r"TRANSFORM_EVIDENCE maximumResidentBytes=(\d+)", text)
    if len(measurements) != 2 or memory is None or "** TEST SUCCEEDED **" not in text:
        raise SystemExit("Transform evidence test did not produce a complete successful record.")
    data = {
        "schemaVersion": 1,
        "requirementIDs": [f"SF-0403-00{i}" for i in range(1, 9)],
        "environment": {
            "hardware": command("/usr/sbin/sysctl", "-n", "hw.model"),
            "processor": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
            "os": platform.mac_ver()[0],
            "xcode": command("xcodebuild", "-version").replace("\n", "; "),
            "configuration": "SiteForgeTests optimized test bundle (-O)",
        },
        "methodology": [
            "The production TransformCommandRegistry executes inside the optimized SiteForgeTests bundle.",
            "Each valid 100- and 10,000-object canonical fixture transforms one selected authored frame through stable identity, scene, revision, availability, geometry, and command validation.",
            "Five monotonic-clock samples are retained per capacity; P95 is nearest-rank and therefore the maximum of five samples.",
            "The same prepared command is committed atomically by DocumentSession in behavioral tests, while separate renderer tests prove exact old/new dirty regions and hit-test adoption.",
        ],
        "measurements": measurements,
        "maximumResidentBytes": int(memory.group(1)),
        "limitations": [
            "These local measurements are engineering evidence, not owner-approved cross-hardware release budgets.",
            "The capacity fixture measures one selected object inside representative projects; it does not claim interactive transformation of 10,000 simultaneously selected objects.",
            "Command adoption remains main-actor coordinated; the 10,000-object preparation result does not prove a 60 Hz interaction budget or final incremental-layout performance.",
            "This bounded slice excludes snapping, guides, rotation, skew, responsive breakpoint editing, rich-text transforms, and export generation.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


if len(sys.argv) == 3 and sys.argv[1] == "--record":
    record(Path(sys.argv[2]))

data = json.loads(OUTPUT.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0403-00{i}" for i in range(1, 9)]
assert data["environment"]["hardware"] and data["environment"]["os"] and data["environment"]["xcode"]
assert {(item["name"], item["objectCount"]) for item in data["measurements"]} == {
    ("transform-prepare", 100), ("transform-prepare", 10_000)
}
assert all(len(item["samples"]) == 5 and item["p95"] == max(item["samples"]) for item in data["measurements"])
assert data["maximumResidentBytes"] > 0
assert len(data["methodology"]) >= 4 and len(data["limitations"]) >= 4
serialized = json.dumps(data)
assert "/Users/" not in serialized and "content.text" not in serialized
print("Transform-foundation evidence checks passed for two measurements.")
