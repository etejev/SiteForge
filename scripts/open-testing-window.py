#!/usr/bin/env python3
"""Prepare a local CLI request for the native Testing window; never start tests."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

def main():
    root = Path(__file__).resolve().parents[1]
    args = sys.argv[1:]
    affected_base = None
    if len(args) >= 2 and args[0] == "test" and args[1] in {"changed", "impacted"}:
        if len(args) > 3:
            print("Use sf test changed [base].", file=sys.stderr); return 2
        affected_base = (args[2] if len(args) == 3 and args[2] else os.environ.get("SITEFORGE_TEST_BASE")) or "origin/main"
        mode, selectors = "full", []
    elif args == ["verify"]:
        mode, selectors = "full", []
    elif args[:1] == ["testing"]:
        mode = args[1] if len(args) == 2 else "full"
        if mode not in {"code", "ui", "full"}:
            print("Testing scope must be code, ui or full.", file=sys.stderr); return 2
        selectors = []
    else:
        with tempfile.TemporaryDirectory(prefix="siteforge-testing-request-") as folder:
            plan = Path(folder) / "plan.json"
            env = dict(os.environ, SITEFORGE_MONITOR_CHILD="1", SITEFORGE_TEST_PLAN=str(plan))
            result = subprocess.run([str(root / "sf")] + args, env=env)
            if result.returncode: return result.returncode
            command = json.loads(plan.read_text())
        selectors = [item.removeprefix("-only-testing:") for item in command if item.startswith("-only-testing:")]
        targets = {item.split("/")[0] for item in selectors}
        mode = "code" if targets == {"SiteForgeTests"} else "ui" if targets == {"SiteForgeUITests"} else "full"
    app = Path("/Applications/SiteForge.app")
    if not app.is_dir():
        print("Install the current owner-local SiteForge app to open Testing.", file=sys.stderr); return 2
    opened = subprocess.run(["/usr/bin/open", "-a", str(app)])
    if opened.returncode: return opened.returncode
    request = {"mode": mode, "selectors": selectors}
    if affected_base is not None:
        request.update(policy="affected", base=affected_base)
    payload = json.dumps(request)
    return subprocess.run(["xcrun", "swift", str(root / "scripts/open-testing-window.swift"), payload]).returncode

if __name__ == "__main__":
    sys.exit(main())
