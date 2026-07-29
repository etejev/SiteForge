#!/usr/bin/env python3
import ast
import json
import platform
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/evidence/inline-text-editing-foundation/measurements.json"


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def record(log_path: Path) -> None:
    text = log_path.read_text()
    pattern = re.compile(
        r"TEXT_EDIT_EVIDENCE objects=(\d+) p95Milliseconds=([0-9.]+) "
        r"samples=(\[[^\n]+?\])"
    )
    measurements = []
    for match in pattern.finditer(text):
        samples = [float(value) for value in ast.literal_eval(match.group(3))]
        measurements.append({
            "name": "text-edit-command-preparation",
            "objectCount": int(match.group(1)),
            "unit": "milliseconds",
            "samples": samples,
            "p95": float(match.group(2)),
        })
    resident = re.search(r"TEXT_EDIT_EVIDENCE maximumResidentBytes=(\d+)", text)
    if len(measurements) != 2 or resident is None or "** TEST SUCCEEDED **" not in text:
        raise SystemExit("Inline-text evidence test did not produce a complete successful record.")
    data = {
        "schemaVersion": 1,
        "requirementIDs": [f"SF-0406-00{i}" for i in range(1, 9)],
        "environment": {
            "hardware": command("/usr/sbin/sysctl", "-n", "hw.model"),
            "processor": command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
            "os": platform.mac_ver()[0],
            "xcode": command("xcodebuild", "-version").replace("\n", "; "),
            "configuration": "SiteForgeTests Debug test bundle (-Onone)",
        },
        "methodology": [
            "The production InlineTextCommandRegistry validates an immutable canonical document snapshot and prepares the existing set-property command.",
            "Four monotonic-clock samples are retained for production-shaped 100- and 10,000-node documents.",
            "Each fixture contains stable typed node/property identities, finite geometry, ordered parent ownership, and a bounded authored plain-text property.",
            "Behavioral and running-app tests separately exercise native NSTextView input, atomic commit, history, rendering, cancellation, and accessibility.",
        ],
        "measurements": measurements,
        "maximumResidentBytes": int(resident.group(1)),
        "limitations": [
            "These are local engineering measurements, not owner-approved cross-hardware budgets.",
            "Preparation is measured independently of AppKit input handling, layout, rasterization, package I/O, and autosave.",
            "The 10,000-node fixture measures bounded full-document lookup; it does not prove final incremental indexing or 60 Hz editing.",
            "OS-level IME, VoiceOver speech, localization, rich text, and production typography remain exploratory or later-slice acceptance.",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


if len(sys.argv) == 3 and sys.argv[1] == "--record":
    record(Path(sys.argv[2]))

data = json.loads(OUTPUT.read_text())
assert data["schemaVersion"] == 1
assert data["requirementIDs"] == [f"SF-0406-00{i}" for i in range(1, 9)]
assert {(item["name"], item["objectCount"]) for item in data["measurements"]} == {
    ("text-edit-command-preparation", 100),
    ("text-edit-command-preparation", 10_000),
}
assert all(
    len(item["samples"]) == 4 and item["p95"] == max(item["samples"])
    for item in data["measurements"]
)
assert data["maximumResidentBytes"] > 0
assert len(data["methodology"]) >= 4 and len(data["limitations"]) >= 4
serialized = json.dumps(data)
assert "/Users/" not in serialized
assert "private authored" not in serialized
print("Inline-text editing evidence checks passed for two measurements.")
