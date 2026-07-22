#!/usr/bin/env python3
import ast
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/evidence/frame-text-insertion-foundation/measurements.json"


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def record(log_path: Path) -> None:
    text = log_path.read_text()
    pattern = re.compile(r"INSERTION_EVIDENCE count=(\d+) command=(\[[^\n]+?\]) layout=(\[[^\n]+?\]) render=(\[[^\n]+?\])")
    measurements = []
    for match in pattern.finditer(text):
        count = int(match.group(1))
        for name, raw in zip(("insertion-command", "layout-pass", "renderer-prepare"), match.groups()[1:]):
            samples = [float(value) for value in ast.literal_eval(raw)]
            measurements.append({"name": name, "objectCount": count, "unit": "milliseconds", "samples": samples, "p95": max(samples)})
    memory = re.search(r"INSERTION_EVIDENCE maximumResidentBytes=(\d+)", text)
    if len(measurements) != 6 or memory is None or "** TEST SUCCEEDED **" not in text:
        raise SystemExit("Insertion evidence test did not produce a complete successful record.")
    data = {
        "schemaVersion": 1,
        "requirementIDs": [f"SF-0405-00{i}" for i in range(1, 9)],
        "environment": {
            "hardware": command("/usr/sbin/sysctl", "-n", "hw.model"),
            "processor": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
            "os": platform.mac_ver()[0],
            "xcode": command("xcodebuild", "-version").replace("\n", "; "),
            "configuration": "SiteForgeTests optimized test bundle (-O)",
        },
        "methodology": [
            "The production InsertionCommandRegistry, DeterministicLayoutEngine, and CanvasRendererCore execute inside the optimized SiteForgeTests bundle.",
            "Each 100- and 10,000-object operation records five monotonic-clock samples; P95 is nearest-rank and therefore the maximum of five samples.",
            "The insertion fixture uses real typed identities, a valid canonical ownership tree, exact command validation, and the production command registry validation path.",
            "The layout and renderer fixtures contain non-empty stable objects; renderer work includes tiles, hit-test data, accessibility snapshots, and deterministic digesting.",
        ],
        "measurements": measurements,
        "maximumResidentBytes": int(memory.group(1)),
        "limitations": [
            "These local measurements are engineering evidence, not owner-approved cross-hardware release budgets.",
            "The command measurement prepares and validates one insertion; UI transaction adoption remains main-actor coordinated and should continue moving expensive future authoring work off actor boundaries.",
            "Text uses bounded intrinsic placeholder geometry and does not measure production shaping, font fallback, rich text, export generation, or incremental layout.",
            "The 10,000-object full layout and renderer results exceed a 60 Hz frame interval and do not prove final interactive or incremental-update performance.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


if len(sys.argv) == 3 and sys.argv[1] == "--record":
    record(Path(sys.argv[2]))

data = json.loads(OUTPUT.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0405-00{i}" for i in range(1, 9)]
assert data["environment"]["hardware"] and data["environment"]["os"] and data["environment"]["xcode"]
assert {(item["name"], item["objectCount"]) for item in data["measurements"]} == {
    (name, count) for name in ("insertion-command", "layout-pass", "renderer-prepare") for count in (100, 10_000)
}
assert all(len(item["samples"]) == 5 and item["p95"] == max(item["samples"]) for item in data["measurements"])
assert data["maximumResidentBytes"] > 0
assert len(data["methodology"]) >= 4 and len(data["limitations"]) >= 4
serialized = json.dumps(data)
assert "/Users/" not in serialized and "content.text" not in serialized
print("Insertion-foundation evidence checks passed for six measurements.")
