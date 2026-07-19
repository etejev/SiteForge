#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = (root / "docs/SiteForge-Specification.md").read_text()
decisions = (root / "docs/OPEN_DECISIONS.md").read_text()
index = json.loads((root / "docs/REQUIREMENT_EVIDENCE.json").read_text())
known = set(re.findall(r"^##### (SF-[0-9]{4}-[0-9]{3}) ", spec, re.MULTILINE))
seen = set()
errors = []

for entry in index.get("requirements", []):
    requirement = entry.get("id")
    if requirement in seen:
        errors.append(f"duplicate requirement evidence: {requirement}")
    seen.add(requirement)
    if requirement not in known:
        errors.append(f"unknown requirement: {requirement}")
    status = entry.get("status")
    if status not in {"verified-bounded", "partial", "deferred"}:
        errors.append(f"invalid status for {requirement}: {status}")
    evidence = entry.get("evidence", [])
    if not evidence:
        errors.append(f"missing evidence for {requirement}")
    if status == "partial" and not entry.get("uncovered"):
        errors.append(f"partial requirement lacks an uncovered boundary: {requirement}")
    if status == "verified-bounded" and entry.get("uncovered"):
        errors.append(f"verified bounded requirement has uncovered criteria: {requirement}")
    for item in evidence:
        path = root / item.get("path", "")
        if not path.is_file():
            errors.append(f"missing evidence path for {requirement}: {path.relative_to(root)}")
            continue
        symbol = item.get("symbol", "")
        if not symbol or symbol not in path.read_text(errors="ignore"):
            errors.append(f"stale evidence symbol for {requirement}: {symbol}")

headings = re.findall(r"^## (OD-[0-9]{3}) — (.+)$", decisions, re.MULTILINE)
decision_ids = [item[0] for item in headings]
if len(decision_ids) != len(set(decision_ids)):
    errors.append("duplicate IDs in OPEN_DECISIONS.md")
expected = {
    "OD-001": "Minimum supported macOS release and reference hardware tiers",
    "OD-002": "Persistence store and project package representation",
    "OD-012": "Publisher identity and bundle identifier",
    "OD-013": "Initial distribution trust level",
}
actual = dict(headings)
for decision_id, title in expected.items():
    if actual.get(decision_id) != title:
        errors.append(f"conflicting or missing decision {decision_id}")
    if not re.search(rf"^\| {decision_id} \|", spec, re.MULTILINE):
        errors.append(f"decision absent from specification register: {decision_id}")

if errors:
    print("Traceability checks failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
print(f"Traceability checks passed for {len(seen)} bounded requirement records.")
