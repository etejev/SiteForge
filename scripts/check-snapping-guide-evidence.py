#!/usr/bin/env python3
import ast
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/evidence/snapping-guide-foundation/measurements.json"


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def record(log_path: Path) -> None:
    text = log_path.read_text()
    pattern = re.compile(
        r"SNAP_EVIDENCE count=(\d+) resolve_ms=(\[[^\n]+?\]) "
        r"resident_before=(\d+) resident_after=(\d+)"
    )
    values = []
    maximum_resident = 0
    for match in pattern.finditer(text):
        samples = [float(value) for value in ast.literal_eval(match.group(2))]
        values.append({
            "name": "snap-resolve",
            "objectCount": int(match.group(1)),
            "unit": "milliseconds",
            "samples": samples,
            "p95": max(samples),
        })
        maximum_resident = max(maximum_resident, int(match.group(3)), int(match.group(4)))
    if len(values) != 2 or "** TEST SUCCEEDED **" not in text:
        raise SystemExit("Snapping evidence test did not produce a complete successful record.")
    data = {
        "schemaVersion": 1,
        "requirementIDs": [f"SF-0404-00{i}" for i in range(1, 9)],
        "environment": {
            "hardware": command("/usr/sbin/sysctl", "-n", "hw.model"),
            "processor": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
            "os": platform.mac_ver()[0],
            "xcode": command("xcodebuild", "-version").replace("\n", "; "),
            "configuration": "SiteForgeTests optimized test bundle (-O)",
        },
        "methodology": [
            "The production SnapResolver evaluates stable object and authored-guide candidates.",
            "Four monotonic-clock samples are retained for 100- and 10,000-object fixtures.",
            "Fixtures exercise real finite frames, stable typed identities, filtering, candidate sorting, smart guides, and bounded measurements.",
            "Behavioral tests separately prove transform preview/commit parity and guide transactions.",
        ],
        "measurements": values,
        "maximumResidentBytes": maximum_resident,
        "limitations": [
            "These are local engineering measurements, not owner-approved cross-hardware budgets.",
            "The resolver currently performs a bounded full scan; 10,000-object results do not prove 60 Hz interaction.",
            "Renderer, layout, and AppKit presentation costs are measured by their own evidence suites.",
            "Text baselines, distribution snapping, rotation, skew, breakpoints, and export are excluded.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


if len(sys.argv) == 3 and sys.argv[1] == "--record":
    record(Path(sys.argv[2]))

data = json.loads(OUTPUT.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0404-00{i}" for i in range(1, 9)]
assert {(item["name"], item["objectCount"]) for item in data["measurements"]} == {
    ("snap-resolve", 100), ("snap-resolve", 10_000)
}
assert all(len(item["samples"]) == 4 and item["p95"] == max(item["samples"]) for item in data["measurements"])
assert data["maximumResidentBytes"] > 0
assert len(data["methodology"]) >= 4 and len(data["limitations"]) >= 4
serialized = json.dumps(data)
assert "/Users/" not in serialized and "content.text" not in serialized
print("Snapping-guide evidence checks passed for two measurements.")
