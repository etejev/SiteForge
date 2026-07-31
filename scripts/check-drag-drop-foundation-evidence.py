#!/usr/bin/env python3
import ast
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/evidence/drag-drop-foundation/measurements.json"

def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()

def record(log_path: Path) -> None:
    text = log_path.read_text()
    pattern = re.compile(r"DRAG_EVIDENCE count=(\d+) prepare=(\[[^\n]+?\])")
    measurements = [{
        "name": "drag-prepare", "objectCount": int(match.group(1)),
        "unit": "milliseconds", "samples": [float(v) for v in ast.literal_eval(match.group(2))],
    } for match in pattern.finditer(text)]
    for item in measurements: item["p95"] = max(item["samples"])
    memory = re.search(r"DRAG_EVIDENCE maximumResidentBytes=(\d+)", text)
    if len(measurements) != 2 or memory is None or "** TEST SUCCEEDED **" not in text:
        raise SystemExit("Drag-drop evidence test did not produce a complete successful record.")
    data = {
        "schemaVersion": 1,
        "requirementIDs": [f"SF-0408-00{i}" for i in range(1, 9)],
        "environment": {"hardware": command("/usr/sbin/sysctl", "-n", "hw.model"), "processor": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"), "os": platform.mac_ver()[0], "xcode": command("xcodebuild", "-version").replace("\n", "; "), "configuration": "SiteForgeTests optimized test bundle (-O)"},
        "methodology": [
            "The production Foundation-only DragDropCommandRegistry executes inside the optimized SiteForgeTests bundle.",
            "Each fixture has one frame root and 100 or 10,000 sibling frame nodes; validation prepares one same-parent move using stable document/page/revision/scene/renderer identities.",
            "Five monotonic-clock samples are retained per capacity; P95 is nearest-rank and therefore the maximum of five samples.",
            "Behavioral tests separately commit through DocumentSession and prove exact undo/redo plus deterministic document serialization.",
        ], "measurements": measurements, "maximumResidentBytes": int(memory.group(1)),
        "limitations": [
            "These local measurements are engineering evidence, not owner-approved cross-hardware release budgets.",
            "The benchmark measures preparation of one local hierarchy move, not pointer gesture processing, AppKit drag tracking, layout, rendering, package I/O, or autosave.",
            "The 10,000-node full hierarchy scan is capacity evidence and does not prove a 60 Hz interaction budget or incremental spatial indexing.",
            "External/Finder transfers, assets, cross-window/project transfer, responsive editing, components, and export generation are outside this bounded slice.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")

if len(sys.argv) == 3 and sys.argv[1] == "--record": record(Path(sys.argv[2]))
data = json.loads(OUTPUT.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0408-00{i}" for i in range(1, 9)]
assert {(v["name"], v["objectCount"]) for v in data["measurements"]} == {("drag-prepare", 100), ("drag-prepare", 10_000)}
assert all(len(v["samples"]) == 5 and v["p95"] == max(v["samples"]) for v in data["measurements"])
assert data["maximumResidentBytes"] > 0 and len(data["methodology"]) >= 4 and len(data["limitations"]) >= 4
serialized = json.dumps(data)
assert "/Users/" not in serialized and "content.text" not in serialized
print("Drag-drop-foundation evidence checks passed for two measurements.")
