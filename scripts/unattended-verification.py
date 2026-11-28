#!/usr/bin/env python3
"""Run-owned local test accounting and controls, shared by app and CLI."""
import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import platform
import statistics
from pathlib import Path
import queue
import re
import runpy
import shutil
import signal
import subprocess
import sys
import threading
import tempfile
import time
import uuid

TERMINAL = {"passed", "failed", "blocked", "cancelled", "skipped"}
EVENT = re.compile(r"^Test Case '-\[([^ ]+) ([^]]+)\]' (started|passed|failed|skipped)\b")
CASE_DURATION = re.compile(r" \(([0-9]+(?:\.[0-9]+)?) seconds?\)\.")

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def source_fingerprint(root):
    try:
        listing = subprocess.run(["git", "ls-files", "-z", "-c", "-o", "--exclude-standard", "--",
                                  "SiteForge", "SiteForge.xcodeproj", "scripts", "Tests", "Samples", "sf"],
                                 cwd=root, check=True, capture_output=True, timeout=120).stdout
    except subprocess.CalledProcessError as error:
        # Preserve the real filesystem/permission diagnosis in the owned log.
        if error.stderr: print(error.stderr.decode(errors="replace"), file=sys.stderr)
        raise
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

def test_event(line):
    match = EVENT.search(line)
    if not match: return None
    event = {"id": f"{match[1]}/{match[2]}", "outcome": match[3]}
    duration = CASE_DURATION.search(line, match.end())
    if duration and event["outcome"] in {"passed", "failed"}:
        event["durationSeconds"] = float(duration[1])
    return event

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

def inventory_failure(output, target):
    text = output.lower()
    if any(message in text for message in (
        "timed out while enabling automation mode", "failed to enable automation mode",
        "failed to initialize for ui testing", "failed to connect to testmanagerd",
        "authorization denied", "not authorized", "screen is locked",
    )):
        return ("xctest-host-unavailable",
                "Xcode could not initialize UI automation. Keep the Mac unlocked and approve the macOS Enable UI Automation prompt when retrying. See the UI log.")
    return ("test-inventory-unavailable",
            f"Xcode did not discover any executable methods for {target}. Check the retained discovery log and rebuild.")

def test_case_key(identifier):
    # XCTest logs use Module.Suite/method. The Xcode inventory uses
    # Target/Suite/method (or Suite/method) and may include parentheses.
    owner, separator, method = identifier.rpartition("/")
    if not separator or not owner or not method: return None
    suite = owner.rsplit("/", 1)[-1].rsplit(".", 1)[-1]
    return suite, method.removesuffix("()")

def build_activity(line):
    if line.startswith("SwiftCompile"):
        files = list(dict.fromkeys(re.findall(r"([A-Za-z0-9_]+\.swift)", line)))
        return "Compiling " + ", ".join(files[:3]) if files else None
    for prefix, detail in (("ComputePackage", "Resolving package dependencies"), ("CreateBuildDescription", "Planning compilation and test products"),
                           ("SwiftEmitModule", "Preparing Swift modules"),
                           ("Ld ", "Linking test products"), ("CodeSign ", "Signing local test products"),
                           ("CompileAssetCatalog", "Preparing application assets"),
                           ("Test Suite", "Loading prepared test suites")):
        if line.startswith(prefix): return detail
    return None

def stage_seconds(stage):
    value = stage.get("commandSeconds")
    if isinstance(value, (int, float)) and value >= 0: return value
    try:
        return max(0, (dt.datetime.fromisoformat(stage["finishedAt"].replace("Z", "+00:00")) -
                       dt.datetime.fromisoformat(stage["startedAt"].replace("Z", "+00:00"))).total_seconds())
    except (KeyError, TypeError, ValueError): return None

def selected_inventory(identifiers, selection, target):
    # Xcode's enumeration can return every method even when -only-testing
    # limits execution. Intersect built leaves with the resolved CLI scope.
    included = [item.removeprefix("-only-testing:").removesuffix("()")
                for item in selection if item.startswith("-only-testing:")]
    excluded = [item.removeprefix("-skip-testing:").removesuffix("()")
                for item in selection if item.startswith("-skip-testing:")]
    def matches(identifier, prefix):
        return identifier == prefix or identifier.startswith(prefix + "/")
    result = []
    for identifier in identifiers:
        full = identifier if identifier.startswith(target + "/") else target + "/" + identifier
        full = full.removesuffix("()")
        if (not included or any(matches(full, item) for item in included)) and not any(matches(full, item) for item in excluded):
            result.append(identifier)
    return result


def executable_selection(identifiers, selection, target):
    """Resolve every requested prefix against this build, or reject all of it."""
    requests = [item.removeprefix("-only-testing:").removesuffix("()") for item in selection
                if item.startswith("-only-testing:" + target) and item.removeprefix("-only-testing:").split("/")[0] == target]
    missing = [item for item in requests if not selected_inventory(identifiers, ["-only-testing:" + item], target)]
    selected = selected_inventory(identifiers, selection, target)
    if missing or not selected:
        return [], missing or requests or [target]
    exact = sorted({(item if item.startswith(target + "/") else target + "/" + item).removesuffix("()") for item in selected})
    return ["-only-testing:" + item for item in exact], []


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
        for item in stage.get("unexpectedOutcomes", []):
            selector = item["selector"]
            if selector not in recorded:
                recorded.add(selector)
                failures.append({"section": section, "selector": selector,
                                 "failureText": f"{item['outcome']}: {'; '.join(item['reasons'])}", "source": "xcresult"})
        for identifier, outcome in stage.get("events", {}).items():
            if outcome != "failed": continue
            parts = identifier.split("/", 1)
            selector = target + "/" + parts[0].split(".")[-1] + ("/" + parts[1] if len(parts) == 2 else "")
            if selector not in recorded:
                failures.append({"section": section, "selector": selector, "source": "XCTest completion event"})
    return failures

class Collector:
    def __init__(self, root, run, mode, selectors=()):
        self.root, self.run, self.mode = root, run, mode
        self.selectors = tuple(selectors)
        self.cancelled = False
        self.preparation_history = {}
        self.case_history = {"code": {}, "ui": {}}
        self.state = {"version": 1, "runID": run.name, "mode": mode, "startedAt": now(),
                      "scope": {"mode": mode, "selectors": list(selectors)},
                      "status": "running", "pauseAvailable": True, "pausedSeconds": 0, "stages": {name: {"status": "waiting", "total": None,
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

    def prepare_tooling_inputs(self):
        # XCTest hosts have a separate macOS Documents identity. Prepare exact
        # source inputs beside the products rather than requesting host access.
        destination = self.run / "tooling-inputs"
        listed = subprocess.run(["git", "ls-files", "-z", "-c", "-o", "--exclude-standard", "--",
                                 "scripts", "Tests/Tooling", "sf"], cwd=self.root, check=True, capture_output=True)
        entries = []
        for raw in sorted(set(listed.stdout.split(b"\0"))):
            if not raw: continue
            relative = os.fsdecode(raw)
            source, target = self.root / relative, destination / relative
            if not source.is_file(): continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            if digest != hashlib.sha256(source.read_bytes()).hexdigest():
                raise RuntimeError("Tooling input changed while preparing products")
            entries.append(dict(path=relative, sha256=digest))
        receipt = dict(sourceFingerprint=self.state["sourceFingerprint"], files=entries)
        atomic_json(self.run / "tooling-inputs.json", receipt)
        self.state["toolingInputs"] = dict(root=str(destination), manifest="tooling-inputs.json", fileCount=len(entries))
        return destination

    def load_timing_history(self):
        environment = {"machine": platform.machine(), "system": platform.mac_ver()[0],
                       "toolchain": self.state.get("toolchain", ""), "preparation": "fresh-isolated"}
        self.state["timingEnvironment"] = environment
        build_scope = {"project": "SiteForge.xcodeproj", "scheme": "SiteForge", "destination": "platform=macOS",
                       "identity": "app.siteforge.SiteForge.OwnerTesting", "action": "build-for-testing"}
        self.state["buildScope"] = build_scope
        preparation, cases, matched = {}, {"code": {}, "ui": {}}, []
        scope = self.state["scope"]
        try: candidates = sorted(self.run.parent.iterdir(), key=lambda path: path.stat().st_mtime, reverse=True)
        except OSError: candidates = []
        for path in candidates:
            if path == self.run or not path.is_dir(): continue
            try: receipt = json.loads((path / "report.json").read_text())
            except (OSError, ValueError): continue
            if receipt.get("toolchain") != self.state.get("toolchain"): continue
            if receipt.get("timingEnvironment", environment) != environment: continue
            prior_scope = receipt.get("scope", {"mode": receipt.get("mode"), "selectors": []})
            same_selection = prior_scope.get("mode") == scope["mode"] and sorted(prior_scope.get("selectors", [])) == sorted(scope["selectors"])
            compatible_build = receipt.get("buildScope") == build_scope or (
                not receipt.get("buildScope") and receipt.get("testArtifact", {}).get("CFBundleIdentifier") == build_scope["identity"])
            if receipt.get("status") not in TERMINAL: continue
            matched.append(path.name)
            fresh = "/Unattended/" + receipt.get("runID", path.name) + "/DerivedData" in receipt.get("derivedDataPath", "")
            for name, stage in receipt.get("stages", {}).items():
                if fresh and stage.get("status") == "passed" and (same_selection or (name == "build" and compatible_build)) and (not receipt.get("pausedSeconds") or stage.get("commandSeconds") is not None):
                    seconds = stage_seconds(stage)
                    if seconds is not None: preparation.setdefault(name, []).append(seconds)
                if stage.get("discoverySeconds") is not None:
                    preparation.setdefault(name + "-discovery", []).append(stage["discoverySeconds"])
                if name in cases:
                    for identifier, seconds in stage.get("durations", {}).items():
                        key = test_case_key(identifier)
                        if key and isinstance(seconds, (int, float)) and seconds >= 0:
                            cases[name].setdefault(key, []).append(seconds)
            if len(matched) == 20: break
        self.preparation_history = {name: statistics.median(values) for name, values in preparation.items()}
        self.case_history = {name: {key: statistics.median(values) for key, values in entries.items()} for name, entries in cases.items()}
        self.state["timingHistory"] = {"runs": matched, "compatibility": "same local environment/toolchain; preparation matches selected scope or identical build products; case timings match fresh selectors"}
        self.publish()

    def update_case_estimate(self, name):
        stage = self.state["stages"][name]
        for key in ("estimatedRemainingSeconds", "estimatedCurrentCaseSeconds"):
            stage.pop(key, None)
        if not stage.get("inventory") or stage.get("inventoryMismatch"): return
        completed = {test_case_key(item) for item in stage["events"]}
        measured = list(stage.get("durations", {}).values())
        average = sum(measured) / len(measured) if len(measured) >= 2 else None
        timings = self.case_history.get(name, {})
        remaining = []
        for identifier in stage["inventory"]:
            key = test_case_key(identifier)
            if key in completed: continue
            seconds = timings.get(key, average)
            if seconds is None: return
            remaining.append(seconds)
        stage["estimatedRemainingSeconds"] = sum(remaining)
        active = test_case_key(stage.get("currentTest", ""))
        if active:
            estimate = timings.get(active, average)
            if estimate is not None: stage["estimatedCurrentCaseSeconds"] = estimate
        stage["estimateBasis"] = "Matched case history; fresh measurements take precedence" if timings else "Measured average from this target"

    def selection(self, target):
        if not self.selectors:
            return ["-only-testing:" + target]
        return ["-only-testing:" + item for item in self.selectors if item.split("/")[0] == target]

    def test_processes(self):
        """Only this run's prepared app/runner can own desktop automation."""
        result = subprocess.run(["/bin/ps", "-axo", "pid=,command="], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Cannot verify XCTest desktop release")
        owned = []
        derived = self.env["SITEFORGE_DERIVED_DATA"]
        # Launch Services reports canonical /private/var paths even when
        # xcodebuild was given /var. Both spellings own the same products.
        prefixes = {derived.rstrip("/") + "/", str(Path(derived).resolve()).rstrip("/") + "/"}
        for line in result.stdout.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) != 2 or not any(parts[1].startswith(prefix) for prefix in prefixes):
                continue
            command = parts[1]
            if "SiteForgeUITests-Runner" in command or (
                    "SiteForge.app/Contents/MacOS/SiteForge" in command and "-SiteForgeUITestMode" in command):
                owned.append(int(parts[0]))
        return owned

    def release_desktop(self, terminate):
        try:
            owned = self.test_processes()
            if terminate:
                for pid in owned:
                    try: os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError: pass
            deadline = time.monotonic() + 10
            while owned and time.monotonic() < deadline:
                time.sleep(0.1)
                owned = self.test_processes()
            return not owned
        except (OSError, RuntimeError, ValueError):
            return False

    def control_checkpoint(self):
        if (self.run / "cancel.request").exists():
            self.cancelled = True
        pause = self.run / "pause.request"
        if pause.exists() and not self.cancelled:
            pause.unlink(missing_ok=True)
            self.state.update(status="paused", pauseStartedAt=now())
            self.publish()
            started = time.monotonic()
            while not self.cancelled:
                if (self.run / "cancel.request").exists():
                    self.cancelled = True
                    break
                resume = self.run / "resume.request"
                if resume.exists():
                    resume.unlink(missing_ok=True)
                    break
                time.sleep(0.1)
            self.state["pausedSeconds"] = self.state.get("pausedSeconds", 0) + time.monotonic() - started
            self.state.pop("pauseStartedAt", None)
            self.state["status"] = "running"
            self.publish()
        return not self.cancelled

    def finish(self, name, status, detail="", code=None):
        stage = self.state["stages"][name]
        stage.pop("currentTest", None)
        stage.pop("currentTestStartedAt", None)
        stage.pop("phase", None)
        stage.update(status=status, detail=detail, exitCode=code, finishedAt=now())
        self.publish()

    def command(self, name, args, track=False):
        if not self.control_checkpoint():
            self.finish(name, "cancelled", code=130)
            return 130
        stage = self.state["stages"][name]
        self.state.pop("activity", None)
        started = time.monotonic()
        paused_at_start = self.state.get("pausedSeconds", 0)
        stage.update(status="running", startedAt=now(), pausedSecondsAtStart=paused_at_start)
        stage["phaseDetail"] = {"preflight": "Checking the provisioned source and permissions", "build": "Resolving build dependencies and products", "repository": "Checking repository policies"}.get(name, "Preparing the selected tests")
        stage.pop("estimatedSeconds", None)
        estimate_key = name + "-discovery" if "-enumerate-tests" in args else name
        if not track and estimate_key in self.preparation_history:
            stage["estimatedSeconds"] = self.preparation_history[estimate_key]
        inventory = stage.get("inventory", [])
        expected_cases = {test_case_key(identifier) for identifier in inventory}
        durations = stage.setdefault("durations", {})
        if len(expected_cases) != len(inventory) or None in expected_cases:
            stage["inventoryMismatch"] = True
        if "-enumerate-tests" in args:
            stage["phase"] = "discovering"
            stage["phaseDetail"] = "Reading exact methods from the prepared test products"
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
        pausing = False
        pause_termination = False
        with (self.run / f"{name}.log").open("a") as log, (self.run / "events.jsonl").open("a") as events:
            while True:
                if (self.run / "pause.request").exists() and not pausing:
                    pausing = True
                    self.state["status"] = "pausing"
                    self.publish()
                if pausing and track and not stage.get("currentTest") and not pause_termination:
                    try: os.killpg(child.pid, signal.SIGINT)
                    except ProcessLookupError: pass
                    pause_termination = True
                    termination_at = time.monotonic()
                if pause_termination and child.poll() is None and time.monotonic() - termination_at > 15:
                    try: os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                if (self.run / "cancel.request").exists() or self.cancelled:
                    self.cancelled = True
                    if self.state["status"] != "cancelling":
                        self.state["status"] = "cancelling"
                        self.publish()
                    if termination_at is None or (time.monotonic() - termination_at > 10 and child.poll() is None):
                        try: os.killpg(child.pid, signal.SIGTERM if termination_at is None else signal.SIGKILL)
                        except ProcessLookupError: pass
                        termination_at = termination_at or time.monotonic()
                try: line = lines.get(timeout=0.2)
                except queue.Empty: continue
                if line is None: break
                log.write(line)
                log.flush()
                if self.env.get("SITEFORGE_STREAM_TEST_LOG") == "1":
                    print(line, end="", flush=True)
                if not track:
                    detail = build_activity(line)
                    if detail and detail != stage.get("phaseDetail"):
                        stage["phaseDetail"] = detail
                        self.publish()
                event = test_event(line) if track else None
                if event:
                    identifier, outcome = event["id"], event["outcome"]
                    if expected_cases and test_case_key(identifier) not in expected_cases:
                        stage["inventoryMismatch"] = True
                    if outcome == "started":
                        stage["currentTest"] = identifier
                        stage["currentTestStartedAt"] = now()
                    else:
                        if stage.get("currentTest") == identifier:
                            stage.pop("currentTest")
                            stage.pop("currentTestStartedAt", None)
                        # Normalize log spelling across continuation segments so one
                        # prepared selector contributes at most one terminal result.
                        recorded = next((item for item in stage["events"]
                                         if test_case_key(item) == test_case_key(identifier)), identifier)
                        previous = stage["events"].get(recorded)
                        stage["events"][recorded] = "failed" if previous == "failed" else outcome
                        if "durationSeconds" in event:
                            durations[recorded] = event["durationSeconds"]
                            stage.update(timedCases=len(durations), timedSeconds=sum(durations.values()))
                        values = list(stage["events"].values())
                        stage.update(completed=len(values), passed=values.count("passed"),
                                     failed=values.count("failed"), skipped=values.count("skipped"))
                    self.update_case_estimate(name)
                    events.write(json.dumps(dict(event, section=name, time=now())) + "\n")
                    events.flush()
                    self.publish()
        code = child.wait()
        duration = max(0, time.monotonic() - started)
        stage["discoverySeconds" if "-enumerate-tests" in args else "commandSeconds"] = duration
        close_output = getattr(child.stdout, "close", None)
        if close_output:
            close_output()
        if track:
            stage.setdefault("segments", []).append({"arguments": args, "exitCode": code,
                                                     "interruptedForPause": pause_termination})
        stage.pop("processID", None)
        if "test-without-building" in args and not self.release_desktop(terminate=pausing or self.cancelled):
            self.finish(name, "blocked", "XCTest desktop release could not be verified.", 2)
            return 2
        if pausing:
            # The owned process group has exited before desktop release is
            # acknowledged. A case without completion stays unresolved.
            stage.pop("currentTest", None)
            stage.pop("currentTestStartedAt", None)
            if not self.control_checkpoint():
                self.finish(name, "cancelled", code=130)
                return 130
            if pause_termination:
                if not expected_cases or stage.get("inventoryMismatch"):
                    self.finish(name, "blocked", "Cannot resume without an exact test inventory.", 2)
                    return 2
                completed = {test_case_key(item) for item in stage["events"]}
                remaining = [item.removesuffix("()") for item in inventory
                             if test_case_key(item) not in completed]
                if remaining:
                    continuation = [arg for arg in args if not arg.startswith("-only-testing:")]
                    continuation.extend("-only-testing:" + item for item in remaining)
                    if "-resultBundlePath" in continuation:
                        index = continuation.index("-resultBundlePath") + 1
                        original = Path(continuation[index])
                        continuation[index] = str(original.with_name(original.stem + "-resume-" + uuid.uuid4().hex[:8] + ".xcresult"))
                    return self.command(name, continuation, track=True)
                code = 1 if "failed" in stage["events"].values() else 0
        category = "cancelled" if self.cancelled else "passed" if code == 0 else "failed"
        if track and code != 0 and stage["completed"] == 0:
            text = (self.run / f"{name}.log").read_text(errors="replace")
            failure, detail = inventory_failure(text, name)
            if failure == "xctest-host-unavailable":
                category = "blocked"
                stage["detail"] = detail
        if track and "failed" in stage["events"].values() and category == "passed":
            category, code = "failed", 1
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
            if re.search(r'"CGSSessionScreenIsLocked"\s*=\s*Yes', screen.stdout): problems.append("screen-locked")
            selected = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
            developer = self.env.get("DEVELOPER_DIR", selected.stdout.strip())
            if "DEVELOPER_DIR" not in self.env and "CommandLineTools" in developer:
                local_xcode = Path("/Applications/Xcode.app/Contents/Developer")
                if local_xcode.is_dir():
                    self.env["DEVELOPER_DIR"] = developer = str(local_xcode)
            if not developer or "CommandLineTools" in developer: problems.append("full-xcode-not-selected")
            setup = subprocess.run(["xcodebuild", "-checkFirstLaunchStatus"], capture_output=True, text=True, env=self.env)
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
        if self.mode == "code": self.finish("ui", "skipped", "Regular testing; UI target not requested")
        ready = self.preflight()
        expected = self.state.get("installedHarnessFingerprint")
        if ready and expected and expected != self.state["sourceFingerprint"]:
            self.finish("preflight", "blocked", "stale-source: reinstall the current owner-local build", 2)
            self.state["failureCategory"] = "stale-source"
            ready = False
        if ready:
            toolchain = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, env=self.env)
            self.state["toolchain"] = toolchain.stdout.strip()
            self.load_timing_history()
        fixture = self.root / ".siteforge-test-fixtures"
        if ready and fixture.is_dir() and not fixture.is_symlink(): shutil.rmtree(fixture)
        awake = subprocess.Popen(["caffeinate", "-di", "-w", str(os.getpid())]) if ready else None
        try:
            if ready:
                test_info = self.run / "test-application-info.plist"
                if (self.root / "SiteForge/Info.plist").is_file():
                    values = test_application_info(self.root / "SiteForge/Info.plist")
                    values["SiteForgeTestToolingRoot"] = str(self.prepare_tooling_inputs())
                    test_info.write_bytes(plistlib.dumps(values))
                if self.mode == "full": self.command("repository", ["/bin/zsh", "scripts/check-repository.sh"])
                else: self.finish("repository", "skipped", "Selected target testing; full repository verification not requested")
                base = ["xcodebuild", "-project", "SiteForge.xcodeproj", "-scheme", "SiteForge", "-destination",
                        f"platform=macOS,arch={platform.machine()}", "-derivedDataPath", self.env["SITEFORGE_DERIVED_DATA"],
                        "-parallel-testing-enabled", "NO", "ONLY_ACTIVE_ARCH=YES",
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
                    targets = ([("code", "SiteForgeTests")] if self.mode == "code" else [("ui", "SiteForgeUITests")])
                    if self.mode == "full":
                        targets.insert(0, ("code", "SiteForgeTests"))
                    independent_targets = self.mode == "full" and not self.selectors
                    # Enumerate both selected targets before executing either so full-run
                    # progress can show the exact remaining count across the stage change.
                    for name, target in targets:
                        if self.cancelled: self.finish(name, "cancelled"); continue
                        if not self.selection(target):
                            self.finish(name, "skipped", "Outside selected scope")
                            self.state["stages"][name].update(total=0, inventory=[])
                            continue
                        inventory = self.run / f"{name}-inventory.json"
                        inventory_code = self.command(name, base + ["test-without-building", f"-only-testing:{target}",
                            "-enumerate-tests", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(inventory)])
                        try: identifiers = inventory_ids(json.loads(inventory.read_text()), target) if inventory_code == 0 else []
                        except (OSError, ValueError): identifiers = []
                        execution, missing = executable_selection(identifiers, self.selection(target), target)
                        discovered_any = bool(identifiers)
                        identifiers = selected_inventory(identifiers, self.selection(target), target)
                        if not self.cancelled:
                            stage = self.state["stages"][name]
                            stage.update(status="waiting", total=len(identifiers) or None, inventory=identifiers,
                                         executionSelectors=execution)
                            if not discovered_any:
                                log = self.run / f"{name}.log"
                                failure, detail = inventory_failure(
                                    log.read_text(errors="replace") if log.is_file() else "", target)
                                self.state["failureCategory"] = failure
                                self.finish(name, "blocked", detail, 2)
                                continue
                            if missing:
                                stage["unresolvedSelectors"] = missing
                                self.state["failureCategory"] = "scope-unresolved"
                                self.finish(name, "blocked", "Scope unresolved in the freshly built inventory. Choose surviving exact selectors or explicit full verification.", 2)
                                continue
                            self.update_case_estimate(name)
                            for key in ("startedAt", "finishedAt", "exitCode", "detail"):
                                stage.pop(key, None)
                            self.publish()
                    for name, target in targets:
                        if self.cancelled: self.finish(name, "cancelled"); continue
                        if self.state["stages"][name]["status"] in {"skipped", "blocked"}: continue
                        # A full run can collect evidence from a ready target
                        # while another target is blocked. An explicit selector
                        # list must resolve in its entirety before execution.
                        if not independent_targets and self.state.get("failureCategory") in {
                            "scope-unresolved", "test-inventory-unavailable", "xctest-host-unavailable"
                        }:
                            self.finish(name, "blocked", "A required test inventory was unavailable or unresolved. See the other stage for the cause.", 2)
                            continue
                        bundle = self.run / "results" / f"{name}.xcresult"
                        bundle.parent.mkdir(exist_ok=True)
                        self.command(name, base + ["test-without-building", "-test-timeouts-enabled", "YES"] + self.state["stages"][name]["executionSelectors"] + [
                                                   "-resultBundlePath", str(bundle)], track=True)
                        self.state["activity"] = "Exporting " + name + " results and screenshots"
                        self.publish()
                        for kind in ("summary", "tests"):
                            with (self.run / f"{name}-{kind}.json").open("w") as output, (self.run / f"{name}-{kind}-export.log").open("w") as error_log:
                                exported = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind,
                                                "--path", str(bundle)], stdout=output, stderr=error_log, env=self.env)
                                self.state["stages"][name].setdefault("artifactExportExitCodes", {})[kind] = exported.returncode
                        # Every continuation remains independently inspectable; screenshots
                        # and structured diagnostics are retained beside its raw bundle.
                        segments = self.state["stages"][name].get("segments") or [{"arguments": ["-resultBundlePath", str(bundle)]}]
                        test_results = []
                        for index, segment in enumerate(segments):
                            arguments = segment["arguments"]
                            if "-resultBundlePath" not in arguments: continue
                            path = arguments[arguments.index("-resultBundlePath") + 1]
                            receipt = {"bundle": path, "segment": index}
                            if index:
                                for kind in ("summary", "tests"):
                                    destination = self.run / f"{name}-segment-{index}-{kind}.json"
                                    with destination.open("w") as output, destination.with_suffix(".log").open("w") as errors:
                                        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", path],
                                                                stdout=output, stderr=errors, env=self.env)
                                    receipt[kind + "ExitCode"] = result.returncode
                            test_results.append(self.run / (f"{name}-segment-{index}-tests.json" if index else f"{name}-tests.json"))
                            attachments = self.run / "attachments" / name / str(index)
                            attachments.mkdir(parents=True, exist_ok=True)
                            with (attachments / "export.log").open("w") as output:
                                result = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", path,
                                                         "--output-path", str(attachments)], stdout=output, stderr=subprocess.STDOUT, env=self.env)
                            receipt["attachmentsExitCode"] = result.returncode
                            # Nested tooling cases remain supplementary to the authoritative
                            # XCTest wrapper outcome/count, with their own exact ledger.
                            for artifact in attachments.glob("*.json"):
                                try:
                                    ledger = json.loads(artifact.read_text())
                                    if isinstance(ledger, dict) and ledger.get("kind") == "nested-tooling-checks":
                                        self.state["stages"][name].setdefault("toolingLedgers", []).append(
                                            dict(path=str(artifact.relative_to(self.run)), results=ledger))
                                except (OSError, ValueError): pass
                            self.state["stages"][name].setdefault("artifactExports", []).append(receipt)
                        try:
                            summary = json.loads((self.run / f"{name}-summary.json").read_text())
                            total = summary.get("totalTestCount")
                            if isinstance(total, int) and total > 0 and len(self.state["stages"][name].get("segments", [])) <= 1:
                                stage = self.state["stages"][name]
                                stage["reportedTotal"] = total
                                if stage["total"] != total:
                                    stage["inventoryMismatch"] = True
                                stage.update(completed=sum(summary.get(key, 0) for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures")),
                                             passed=summary.get("passedTests", 0), failed=summary.get("failedTests", 0), skipped=summary.get("skippedTests", 0),
                                             expectedFailures=summary.get("expectedFailures", 0), testFailures=summary.get("testFailures", []),
                                             runtimeWarnings=summary.get("runtimeWarnings", []))
                                if stage["failed"] > 0 and stage["status"] == "passed": stage["status"] = "failed"
                                self.publish()
                        except (OSError, ValueError, TypeError): pass
                        stage = self.state["stages"][name]
                        if stage["status"] == "passed":
                            try:
                                accounting = runpy.run_path(str(self.root / "scripts/ci-test-accounting.py"))
                                entries = [entry for result in test_results
                                           for entry in accounting["records"](json.loads(result.read_text()))]
                                expected = [accounting["selector"](identifier if identifier.startswith(target + "/")
                                                                    else f"{target}/{identifier}")
                                            for identifier in stage["inventory"]]
                                accounting["exact"]([entry["selector"] for entry in entries], expected, name)
                                if any(entry["outcome"] == "Skipped" and not entry["reasons"] for entry in entries):
                                    accounting["restore_skip_reasons"](entries, (self.run / f"{name}.log").read_text(errors="replace"))
                            except (OSError, ValueError, KeyError, TypeError) as error:
                                self.finish(name, "blocked", f"Exact XCTest evidence unavailable: {error}", 2)
                                continue
                            unexpected = [entry for entry in entries
                                          if entry["outcome"] != "Passed" and not accounting["approved_skip"](entry)]
                            stage.update(completed=len(entries),
                                         passed=sum(entry["outcome"] == "Passed" for entry in entries),
                                         failed=sum(entry["outcome"] == "Failed" for entry in entries),
                                         skipped=sum(entry["outcome"] == "Skipped" for entry in entries))
                            if unexpected:
                                stage["unexpectedOutcomes"] = unexpected
                                self.finish(name, "failed", "XCTest reported an unapproved outcome. See the retained per-test results.", 1)
                            else:
                                self.publish()
            for name, stage in self.state["stages"].items():
                if stage["status"] not in TERMINAL:
                    self.finish(name, "cancelled" if self.cancelled else "blocked", "Prerequisite unavailable")
            result = aggregate(self.state["stages"])
            self.state.pop("activity", None)
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
                + "\n" + "\n".join(f"- Nested tooling (separate from XCTest counts): {item['results'].get('passed')}/{item['results'].get('total')} passed; ledger: {item['path']}"
                    for stage in self.state["stages"].values() for item in stage.get("toolingLedgers", []))
                + "\n\nLogs, failures.json and xcresult bundles contain diagnostics. Unknown inventory is indeterminate.\n")
            return 0 if self.state["status"] == "passed" else 130 if self.cancelled else 1
        finally:
            if awake: awake.terminate(); awake.wait()
            if fixture.is_dir() and not fixture.is_symlink(): shutil.rmtree(fixture)

def open_progress(progress, run):
    with (run / "progress.log").open("a") as log:
        command = [str(progress)] if progress.suffix != ".swift" else ["xcrun", "swift", str(progress)]
        command.extend([str(run), "--monitor"])
        viewer = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        atomic_json(run / "progress-owner.json", {"pid": viewer.pid, "command": command})

def finish_startup(collector, parent, status, category, detail, code):
    for name in collector.state["stages"]:
        collector.finish(name, status, detail, code)
    collector.state.update(status=status, failureCategory=category, finishedAt=now(), exitCode=code)
    collector.publish()
    atomic_json(collector.run / "report.json", collector.state)
    atomic_json(collector.run / "failures.json", dict(collector.state["stages"]))
    (collector.run / "REPORT.md").write_text("# SiteForge testing\\n\\n" + status + ": " + detail + "\\nNo test targets launched.\\n")
    try:
        lock = parent / "active.json"
        if json.loads(lock.read_text()).get("run") == str(collector.run): lock.unlink()
    except (OSError, ValueError): pass
    return code

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--mode", choices=("full", "ui", "code"), default="full")
    parser.add_argument("--selector", action="append", default=[])
    parser.add_argument("--source-check-progress", action="store_true")
    parser.add_argument("--fingerprint-result", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--collect", type=Path)
    parser.add_argument("--progress", type=Path)
    parser.add_argument("--reports-root", type=Path)
    parser.add_argument("--expected-source-fingerprint")
    args = parser.parse_args()
    if any(not re.fullmatch(r"SiteForge(?:UI)?Tests/[A-Za-z_][A-Za-z0-9_]*(?:/test[A-Za-z0-9_]+)?", item) for item in args.selector):
        parser.error("Selectors must name an exact SiteForge test target/class or target/class/method.")
    requested = "SiteForgeTests" if args.mode == "code" else "SiteForgeUITests" if args.mode == "ui" else None
    if requested and args.selector and not any(item.startswith(requested + "/") for item in args.selector):
        parser.error("The prepared selectors do not include the requested target.")
    root = args.root.resolve()
    parent = args.reports_root.resolve() if args.reports_root else root / ".codex-loop" / "full-verification"
    if args.fingerprint_result:
        atomic_json(args.fingerprint_result, {"sourceFingerprint": source_fingerprint(root)})
        return 0
    if not args.collect and (parent / "active.json").exists():
        print("A testing run is already active. Open its progress or report.", file=sys.stderr)
        return 2
    if not args.collect and not args.source_check_progress and args.expected_source_fingerprint and source_fingerprint(root) != args.expected_source_fingerprint:
        parent.mkdir(parents=True, exist_ok=True)
        run = parent / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        run.mkdir()
        collector = Collector(root, run, args.mode, args.selector)
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
        collector = Collector(root, args.collect, args.mode, args.selector)
        try:
            initial = json.loads((args.collect / "state.json").read_text())
            collector.state["startedAt"] = initial.get("startedAt", collector.state["startedAt"])
            collector.state["sourceCheck"] = initial.get("stages", {}).get("preflight")
        except (OSError, ValueError): pass
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
    progress_started = False
    if args.source_check_progress:
        with os.fdopen(descriptor, "w") as ownership:
            json.dump({"run": str(run), "pid": os.getpid()}, ownership)
        descriptor = None
        checker = Collector(root, run, args.mode, args.selector)
        checker.state.update(pauseAvailable=False, installedHarnessFingerprint=args.expected_source_fingerprint)
        checker.publish()
        try:
            open_progress(progress, run)
            progress_started = True
        except OSError:
            # The report and source check remain functional without a viewer.
            checker.state["progressUnavailable"] = True
        previous = {item: signal.signal(item, lambda *_: setattr(checker, "cancelled", True))
                    for item in (signal.SIGINT, signal.SIGTERM)}
        receipt = run / "source-fingerprint.json"
        try:
            code = checker.command("preflight", [sys.executable, str(Path(__file__).resolve()), "--root", str(root),
                                    "--fingerprint-result", str(receipt)])
        finally:
            for item, handler in previous.items(): signal.signal(item, handler)
        if checker.cancelled:
            return finish_startup(checker, parent, "cancelled", "source-check-cancelled", "Source check cancelled.", 130)
        try: fingerprint = json.loads(receipt.read_text())["sourceFingerprint"] if code == 0 else None
        except (OSError, ValueError, KeyError): fingerprint = None
        if not fingerprint:
            return finish_startup(checker, parent, "blocked", "source-access-unavailable",
                                  "Source check unavailable. Check macOS source-folder permission and preflight.log.", 2)
        checker.state["sourceFingerprint"] = fingerprint
        if args.expected_source_fingerprint and fingerprint != args.expected_source_fingerprint:
            return finish_startup(checker, parent, "blocked", "stale-source",
                                  "stale-source: reinstall the current owner-local app.", 2)
    with (run / "collector.log").open("w") as log:
        command = [sys.executable, str(Path(__file__).resolve()), "--root", str(root), "--mode",
                   args.mode, "--collect", str(run), "--reports-root", str(parent)]
        for selector in args.selector:
            command.extend(["--selector", selector])
        if args.expected_source_fingerprint:
            command.extend(["--expected-source-fingerprint", args.expected_source_fingerprint])
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    if descriptor is None:
        atomic_json(lock, {"run": str(run), "pid": child.pid})
    else:
        with os.fdopen(descriptor, "w") as file: json.dump({"run": str(run), "pid": child.pid}, file)
    if not progress_started:
        open_progress(progress, run)
    print(run)
    return 0

if __name__ == "__main__": sys.exit(main())
