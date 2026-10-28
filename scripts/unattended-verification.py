#!/usr/bin/env python3
"""Detached, staged local collector. Direct sf verify keeps its CI semantics."""
import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
from pathlib import Path
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import tempfile
import time
import uuid

TERMINAL = {"passed", "failed", "blocked", "cancelled", "skipped"}
EVENT = re.compile(r"Test Case '-\[([^ ]+) ([^]]+)\]' (passed|failed|skipped)")

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def source_fingerprint(root):
    listing = subprocess.run(["git", "ls-files", "-z", "-c", "-o", "--exclude-standard", "--",
                              "SiteForge", "SiteForge.xcodeproj", "scripts", "Tests", "sf"],
                             cwd=root, check=True, capture_output=True).stdout
    digest = hashlib.sha256()
    # Git lists untracked and tracked groups separately. Staging a previously
    # untracked source must not invalidate an otherwise identical installation.
    for raw in sorted(set(listing.split(b"\0"))):
        if not raw: continue
        source = root / os.fsdecode(raw)
        if not source.is_file(): continue
        digest.update(raw + b"\0")
        digest.update((hashlib.sha256(source.read_bytes()).hexdigest() + "  -\n").encode())
    return digest.hexdigest()

def test_application_info(source):
    values = plistlib.loads(source.read_bytes())
    for document in values.get("CFBundleDocumentTypes", []):
        document["LSHandlerRank"] = "None"
    return values

def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)

def completed_event(line):
    match = EVENT.search(line)
    return {"id": f"{match[1]}/{match[2]}", "outcome": match[3]} if match else None

def inventory_ids(value, target):
    """Only Xcode-enumerated test leaves; no counting Swift source methods."""
    found = set()
    if isinstance(value, dict) and value.get("errors"): return []
    def visit(item, ancestry=()):
        if isinstance(item, list):
            for child in item: visit(child, ancestry)
        elif isinstance(item, dict):
            scope = ancestry + (str(item.get("name", item.get("nodeIdentifier", ""))),)
            identifier = item.get("testIdentifier", item.get("nodeIdentifier"))
            kind = str(item.get("nodeType", item.get("kind", item.get("type", "")))).lower().replace(" ", "")
            if kind == "test" and not identifier and target in scope:
                position = scope.index(target)
                identifier = "/".join(scope[position:]).removesuffix("()")
            if kind in {"testcase", "testmethod", "test"} and identifier:
                if target in str(identifier) or target in scope: found.add(str(identifier))
            for child in item.values():
                if isinstance(child, (dict, list)): visit(child, scope)
    visit(value)
    return sorted(found)

def aggregate(stages):
    values = [stage["status"] for stage in stages.values()]
    for result in ("cancelled", "failed", "blocked"):
        if result in values: return result
    return "passed" if all(value in {"passed", "skipped"} for value in values) else "running"

def failed_selectors(stages):
    failures = []
    for section, stage in stages.items():
        target = "SiteForgeUITests" if section == "ui" else "SiteForgeTests"
        recorded = set()
        for item in stage.get("testFailures", []):
            raw = item.get("testIdentifierString", item.get("testName", ""))
            if not raw: continue
            selector = raw.removesuffix("()")
            if not selector.startswith(target + "/"): selector = target + "/" + selector
            recorded.add(selector)
            failures.append({"section": section, "selector": selector, "failureText": item.get("failureText", ""), "source": "xcresult"})
        for identifier, outcome in stage.get("events", {}).items():
            if outcome != "failed": continue
            parts = identifier.split("/", 1)
            selector = target + "/" + parts[0].split(".")[-1] + ("/" + parts[1] if len(parts) == 2 else "")
            if selector not in recorded:
                failures.append({"section": section, "selector": selector, "source": "XCTest completion event"})
    return failures

class Collector:
    def __init__(self, root, run, mode):
        self.root, self.run, self.mode = root, run, mode
        self.cancelled = False
        self.state = {"version": 1, "runID": run.name, "mode": mode, "startedAt": now(),
                      "status": "running", "stages": {name: {"status": "waiting", "total": None,
                      "completed": 0, "passed": 0, "failed": 0, "skipped": 0, "events": {}}
                      for name in ("preflight", "repository", "build", "code", "ui")}}
        info = Path(__file__).resolve().parents[2] / "Info.plist"
        if info.is_file():
            try:
                values = plistlib.loads(info.read_bytes())
                keys = ("CFBundleIdentifier", "CFBundleVersion", "SiteForgeSourceRevision",
                        "SiteForgeSourceFingerprint", "SiteForgeSourceDirty", "SiteForgeLocalBuildTimestamp")
                self.state["installedArtifact"] = {key: values[key] for key in keys if key in values}
            except (OSError, ValueError):
                self.state["installedArtifact"] = {"status": "unavailable"}
        derived = Path(tempfile.gettempdir()) / "SiteForge" / "Unattended" / run.name / "DerivedData"
        self.state["derivedDataPath"] = str(derived)
        self.env = dict(os.environ, SITEFORGE_DERIVED_DATA=str(derived),
                        SITEFORGE_TEST_RESULTS_ROOT=str(run / "results"), SITEFORGE_TEST_RUN_ID=run.name)

    def publish(self): atomic_json(self.run / "state.json", self.state)

    def finish(self, name, status, detail="", code=None):
        self.state["stages"][name].update(status=status, detail=detail, exitCode=code, finishedAt=now())
        self.publish()

    def command(self, name, args, track=False):
        stage = self.state["stages"][name]
        stage.update(status="running", startedAt=now())
        self.publish()
        try:
            child = subprocess.Popen(args, cwd=self.root, env=self.env, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1, start_new_session=True)
        except OSError as error:
            self.finish(name, "blocked", type(error).__name__, 127)
            return 127
        stage["processID"] = child.pid
        self.publish()
        lines = queue.Queue()
        def read():
            for line in child.stdout: lines.put(line)
            lines.put(None)
        threading.Thread(target=read, daemon=True).start()
        termination_at = None
        with (self.run / f"{name}.log").open("a") as log, (self.run / "events.jsonl").open("a") as events:
            while True:
                if (self.run / "cancel.request").exists() or self.cancelled:
                    self.cancelled = True
                    if termination_at is None or (time.monotonic() - termination_at > 10 and child.poll() is None):
                        try: os.killpg(child.pid, signal.SIGTERM if termination_at is None else signal.SIGKILL)
                        except ProcessLookupError: pass
                        termination_at = termination_at or time.monotonic()
                try: line = lines.get(timeout=0.2)
                except queue.Empty: continue
                if line is None: break
                log.write(line)
                log.flush()
                event = completed_event(line) if track else None
                if event:
                    stage["events"][event["id"]] = event["outcome"]
                    values = list(stage["events"].values())
                    stage.update(completed=len(values), passed=values.count("passed"),
                                 failed=values.count("failed"), skipped=values.count("skipped"))
                    events.write(json.dumps(dict(event, section=name, time=now())) + "\n")
                    events.flush()
                    self.publish()
        code = child.wait()
        category = "cancelled" if self.cancelled else "passed" if code == 0 else "failed"
        if track and code != 0 and stage["completed"] == 0:
            text = (self.run / f"{name}.log").read_text(errors="replace")
            if any(message in text.lower() for message in ("failed to enable automation mode", "not authorized", "authorization denied", "failed to connect to testmanagerd", "screen is locked")):
                category = "blocked"
                stage["detail"] = "XCTest host/automation unavailable; inspect retained lifecycle log."
        self.finish(name, category, stage.get("detail", ""), code=code)
        return code

    def preflight(self):
        problems = [f"missing-tool:{name}" for name in ("xcodebuild", "xcrun", "caffeinate", "swift", "git")
                    if not shutil.which(name)]
        runtime = subprocess.run(["/bin/zsh", str(self.root / "scripts/verification-python.sh"), "--check"],
                                 capture_output=True, text=True)
        if runtime.returncode:
            problems.append("verification-image-runtime-missing: run /bin/zsh scripts/setup-verification-runtime.sh")
        if not (self.root / "SiteForge.xcodeproj").is_dir() or not (self.root / "sf").is_file():
            problems.append("invalid-workspace")
        if not os.access(self.root, os.R_OK | os.W_OK | os.X_OK): problems.append("workspace-permission-denied")
        if shutil.disk_usage(self.run).free < 8 * 1024**3: problems.append("disk-space-below-8GiB")
        try:
            if Path("/dev/console").stat().st_uid != os.getuid(): problems.append("console-user-not-active")
            screen = subprocess.run(["ioreg", "-n", "Root", "-d", "1"], capture_output=True, text=True)
            if '"CGSSessionScreenIsLocked" = Yes' in screen.stdout: problems.append("screen-locked")
            selected = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
            if selected.returncode or "CommandLineTools" in selected.stdout: problems.append("full-xcode-not-selected")
            setup = subprocess.run(["xcodebuild", "-checkFirstLaunchStatus"], capture_output=True, text=True)
            if setup.returncode: problems.append("xcode-first-launch-setup-required")
            # The dedicated test application ID and derived-data directory
            # keep the installed controller and its unsaved documents separate.
        except OSError: problems.append("host-readiness-unavailable")
        self.finish("preflight", "blocked" if problems else "passed", "; ".join(problems))
        return not problems

    def collect(self):
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root, capture_output=True, text=True)
        diff = subprocess.run(["git", "diff", "HEAD", "--binary"], cwd=self.root, capture_output=True)
        untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=self.root, capture_output=True)
        digest = hashlib.sha256(diff.stdout)
        for raw in sorted(untracked.stdout.split(b"\0")):
            if raw:
                path = self.root / os.fsdecode(raw)
                digest.update(raw)
                if path.is_file(): digest.update(path.read_bytes())
        self.state.update(sourceRevision=revision.stdout.strip(), dirtyFingerprint=digest.hexdigest(),
                          sourceFingerprint=source_fingerprint(self.root))
        if self.mode == "ui": self.finish("code", "skipped", "UI-only run; code target not requested")
        ready = self.preflight()
        expected = self.state.get("installedHarnessFingerprint")
        if ready and expected and expected != self.state["sourceFingerprint"]:
            self.finish("preflight", "blocked", "stale-source: reinstall the current owner-local build", 2)
            self.state["failureCategory"] = "stale-source"
            ready = False
        if ready:
            toolchain = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True)
            self.state["toolchain"] = toolchain.stdout.strip()
        fixture = self.root / ".siteforge-test-fixtures"
        if ready and fixture.is_dir() and not fixture.is_symlink(): shutil.rmtree(fixture)
        awake = subprocess.Popen(["caffeinate", "-di", "-w", str(os.getpid())]) if ready else None
        try:
            if ready:
                test_info = self.run / "test-application-info.plist"
                if (self.root / "SiteForge/Info.plist").is_file():
                    test_info.write_bytes(plistlib.dumps(test_application_info(self.root / "SiteForge/Info.plist")))
                if self.mode == "full": self.command("repository", ["/bin/zsh", "scripts/check-repository.sh"])
                else: self.finish("repository", "skipped", "UI-only run")
                base = ["xcodebuild", "-project", "SiteForge.xcodeproj", "-scheme", "SiteForge", "-destination",
                        "platform=macOS", "-derivedDataPath", self.env["SITEFORGE_DERIVED_DATA"], "-parallel-testing-enabled", "NO",
                        "SITEFORGE_APP_BUNDLE_IDENTIFIER=app.siteforge.SiteForge.OwnerTesting",
                        "SITEFORGE_APP_INFO_PLIST=" + str(test_info),
                        "INFOPLIST_KEY_SiteForgeTestApplicationIdentifier=app.siteforge.SiteForge.OwnerTesting"]
                prepared = not self.cancelled and self.command("build", base + ["build-for-testing"]) == 0
                if prepared and source_fingerprint(self.root) != self.state["sourceFingerprint"]:
                    self.finish("build", "blocked", "Source changed during preparation; no tests were launched.", 2)
                    self.state["failureCategory"] = "source-changed-during-build"
                    prepared = False
                if prepared:
                    artifact = Path(self.env["SITEFORGE_DERIVED_DATA"]) / "Build/Products/Debug/SiteForge.app/Contents/Info.plist"
                    if artifact.is_file():
                        values = plistlib.loads(artifact.read_bytes())
                        self.state["testArtifact"] = {key: values[key] for key in ("CFBundleIdentifier", "CFBundleVersion") if key in values}
                    for name, target in (("code", "SiteForgeTests"), ("ui", "SiteForgeUITests")):
                        if name == "code" and self.mode == "ui":
                            self.finish(name, "skipped", "UI-only run")
                            continue
                        if self.cancelled: self.finish(name, "cancelled"); continue
                        inventory = self.run / f"{name}-inventory.json"
                        inventory_code = self.command(name, base + ["test-without-building", f"-only-testing:{target}",
                            "-enumerate-tests", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(inventory)])
                        try: identifiers = inventory_ids(json.loads(inventory.read_text()), target) if inventory_code == 0 else []
                        except (OSError, ValueError): identifiers = []
                        self.state["stages"][name].update(total=len(identifiers) or None, inventory=identifiers)
                        if self.cancelled: self.finish(name, "cancelled"); continue
                        bundle = self.run / "results" / f"{name}.xcresult"
                        bundle.parent.mkdir(exist_ok=True)
                        self.command(name, base + ["test-without-building", f"-only-testing:{target}",
                                                   "-resultBundlePath", str(bundle)], track=True)
                        for kind in ("summary", "tests"):
                            with (self.run / f"{name}-{kind}.json").open("w") as output, (self.run / f"{name}-{kind}-export.log").open("w") as error_log:
                                exported = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind,
                                                "--path", str(bundle)], stdout=output, stderr=error_log)
                                self.state["stages"][name].setdefault("artifactExportExitCodes", {})[kind] = exported.returncode
                        try:
                            summary = json.loads((self.run / f"{name}-summary.json").read_text())
                            total = summary.get("totalTestCount")
                            if isinstance(total, int) and total > 0:
                                stage = self.state["stages"][name]
                                stage.update(total=total, completed=min(total, sum(summary.get(key, 0) for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures"))),
                                             passed=summary.get("passedTests", 0), failed=summary.get("failedTests", 0), skipped=summary.get("skippedTests", 0),
                                             expectedFailures=summary.get("expectedFailures", 0), testFailures=summary.get("testFailures", []),
                                             runtimeWarnings=summary.get("runtimeWarnings", []))
                                if stage["failed"] > 0 and stage["status"] == "passed": stage["status"] = "failed"
                                self.publish()
                        except (OSError, ValueError, TypeError): pass
                        stage = self.state["stages"][name]
                        if stage["status"] == "passed" and stage["completed"] == 0:
                            self.finish(name, "blocked", "No completed-test evidence; inspect XCTest lifecycle logs.")
                        elif stage["status"] == "passed" and stage["total"] is not None and stage["completed"] < stage["total"]:
                            self.finish(name, "blocked", "Not all enumerated tests have completion evidence.")
            for name, stage in self.state["stages"].items():
                if stage["status"] not in TERMINAL:
                    self.finish(name, "cancelled" if self.cancelled else "blocked", "Prerequisite unavailable")
            result = aggregate(self.state["stages"])
            self.state.update(status=result, finishedAt=now(), exitCode=0 if result == "passed" else 130 if result == "cancelled" else 1)
            self.publish()
            atomic_json(self.run / "report.json", self.state)
            atomic_json(self.run / "failures.json", {name: stage for name, stage in self.state["stages"].items()
                        if stage["status"] in {"failed", "blocked", "cancelled"}})
            atomic_json(self.run / "failed-selectors.json", failed_selectors(self.state["stages"]))
            (self.run / "REPORT.md").write_text("# SiteForge local testing\n\nResult: " + self.state["status"]
                + "\nSource: " + self.state["sourceRevision"] + "\n\n"
                + "\n".join(f"- {name}: {stage['status']} — {stage['completed']} completed tests; exit {stage.get('exitCode')}"
                            for name, stage in self.state["stages"].items())
                + "\n\nLogs, failures.json and xcresult bundles contain diagnostics. Unknown inventory is indeterminate.\n")
            return 0 if self.state["status"] == "passed" else 130 if self.cancelled else 1
        finally:
            if awake: awake.terminate(); awake.wait()
            if fixture.is_dir() and not fixture.is_symlink(): shutil.rmtree(fixture)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--mode", choices=("full", "ui"), default="full")
    parser.add_argument("--collect", type=Path)
    parser.add_argument("--progress", type=Path)
    parser.add_argument("--reports-root", type=Path)
    parser.add_argument("--expected-source-fingerprint")
    args = parser.parse_args()
    root = args.root.resolve()
    parent = args.reports_root.resolve() if args.reports_root else root / ".codex-loop" / "full-verification"
    if not args.collect and (parent / "active.json").exists():
        print("A testing run is already active. Open its progress or report.", file=sys.stderr)
        return 2
    if not args.collect and args.expected_source_fingerprint and source_fingerprint(root) != args.expected_source_fingerprint:
        parent.mkdir(parents=True, exist_ok=True)
        run = parent / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        run.mkdir()
        collector = Collector(root, run, args.mode)
        for stage in collector.state["stages"]:
            collector.finish(stage, "blocked", "stale-source: reinstall the current owner-local build", 2)
        collector.state.update(status="blocked", failureCategory="stale-source", finishedAt=now(), exitCode=2,
                               installedHarnessFingerprint=args.expected_source_fingerprint,
                               sourceFingerprint=source_fingerprint(root))
        collector.publish()
        atomic_json(run / "report.json", collector.state)
        atomic_json(parent / "current.json", {"run": str(run)})
        (run / "REPORT.md").write_text("# SiteForge testing\n\nBlocked: provisioned source changed. Reinstall the current owner-local app. No tests launched.\n")
        print("stale-source: reinstall the current owner-local app; no test targets were launched.", file=sys.stderr)
        return 2
    parent.mkdir(parents=True, exist_ok=True)
    lock = parent / "active.json"
    if args.collect:
        if args.collect.resolve().parent != parent.resolve():
            print("Collector run directory must belong to this workspace's ignored testing root.", file=sys.stderr)
            return 2
        collector = Collector(root, args.collect, args.mode)
        collector.state["sourceFingerprint"] = source_fingerprint(root)
        collector.state["installedHarnessFingerprint"] = args.expected_source_fingerprint
        collector.state["collectorPID"] = os.getpid()
        collector.publish()
        signal.signal(signal.SIGTERM, lambda *_: setattr(collector, "cancelled", True))
        signal.signal(signal.SIGINT, lambda *_: setattr(collector, "cancelled", True))
        try: return collector.collect()
        except Exception as error:
            for name, stage in collector.state["stages"].items():
                if stage["status"] not in TERMINAL: collector.finish(name, "blocked", type(error).__name__)
            collector.state.update(status="blocked", finishedAt=now(), exitCode=1, collectorFailure=type(error).__name__)
            collector.publish()
            atomic_json(args.collect / "report.json", collector.state)
            atomic_json(args.collect / "failures.json", {"collectorFailure": type(error).__name__})
            (args.collect / "REPORT.md").write_text("# SiteForge local testing\n\nBlocked: collector failure.\n"
                                                  + "See report.json and collector.log; this is not a testing pass.\n")
            return 1
        finally:
            try:
                if json.loads(lock.read_text())["run"] == str(args.collect): lock.unlink()
            except (OSError, ValueError, KeyError): pass
    progress = args.progress or root / "scripts" / "full-verification-progress.swift"
    if progress.suffix == ".swift":
        checked = subprocess.run(["xcrun", "swiftc", "-typecheck", str(progress)], capture_output=True, text=True)
        if checked.returncode:
            print("Testing progress helper does not compile; no collector launched.\n" + checked.stderr, file=sys.stderr)
            return 2
    try: descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        print(f"A run already owns {lock}. Inspect its report; do not launch a duplicate.", file=sys.stderr)
        return 2
    run = parent / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    run.mkdir()
    atomic_json(parent / "current.json", {"run": str(run)})
    with (run / "collector.log").open("w") as log:
        command = [sys.executable, str(Path(__file__).resolve()), "--root", str(root), "--mode",
                   args.mode, "--collect", str(run), "--reports-root", str(parent)]
        if args.expected_source_fingerprint:
            command.extend(["--expected-source-fingerprint", args.expected_source_fingerprint])
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    with os.fdopen(descriptor, "w") as file: json.dump({"run": str(run), "pid": child.pid}, file)
    with (run / "progress.log").open("w") as log:
        command = [str(progress), str(run)] if progress.suffix != ".swift" else ["xcrun", "swift", str(progress), str(run)]
        viewer = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        atomic_json(run / "progress-owner.json", {"pid": viewer.pid, "command": command})
    print(run)
    return 0

if __name__ == "__main__": sys.exit(main())
