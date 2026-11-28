#!/usr/bin/env python3
"""Run a local sf test plan with the shared native progress and controls."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import shutil
import uuid

spec = importlib.util.spec_from_file_location("siteforge_collector", Path(__file__).with_name("unattended-verification.py"))
collector_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector_module)


selected_inventory = collector_module.selected_inventory


def execute_plan(collector, command, verify=False):
    """Enumerate and execute the resolved scope against one prepared build."""
    index = command.index("test") if "test" in command else command.index("test-without-building")
    base, selection = command[:index], command[index + 1:]
    result_index = base.index("-resultBundlePath")
    del base[result_index:result_index + 2]
    requested = sorted(item.removeprefix("-only-testing:") for item in selection if item.startswith("-only-testing:"))
    requested_targets = {item.split("/")[0] for item in requested}
    mode = "code" if requested_targets == {"SiteForgeTests"} else "ui" if requested_targets == {"SiteForgeUITests"} else "full"
    collector.state["scope"] = {"mode": mode, "selectors": requested}
    targets = ("SiteForgeTests", "SiteForgeUITests")
    if verify:
        if collector.command("repository", ["/bin/zsh", "scripts/check-repository.sh"]):
            return 1
    else:
        collector.finish("repository", "skipped", "Focused testing")
    built = collector.command("build", base + ["build-for-testing"])
    if built:
        return built
    if collector_module.source_fingerprint(collector.root) != collector.state["sourceFingerprint"]:
        collector.finish("build", "blocked", "Source changed during preparation; no tests launched.", 2)
        return 2
    for section, target in zip(("code", "ui"), targets):
        inventory = collector.run / (section + "-inventory.json")
        selected = selection + ["-only-testing:" + target]
        # Intersect target selection with the already resolved scope.
        restrictions = [item for item in selection if item.startswith("-only-testing:")]
        if restrictions and not any(item.removeprefix("-only-testing:").split("/")[0] == target for item in restrictions):
            collector.finish(section, "skipped", "Outside selected scope")
            collector.state["stages"][section].update(total=0, inventory=[])
            continue
        selected = [item for item in selection if not item.startswith("-only-testing:")]
        selected += [item for item in restrictions if item.removeprefix("-only-testing:").split("/")[0] == target] or ["-only-testing:" + target]
        discovered = collector.command(section, base + ["test-without-building"] + selected + [
            "-enumerate-tests", "-test-enumeration-format", "json",
            "-test-enumeration-output-path", str(inventory)])
        try:
            enumeration = json.loads(inventory.read_text())
            raw = collector_module.inventory_ids(enumeration, target) if discovered == 0 else []
            execution, missing = collector_module.executable_selection(raw, selected, target)
            ids = selected_inventory(raw, selection, target)
        except (OSError, ValueError):
            enumeration, ids, execution, missing = {}, [], [], [target]
        if collector.cancelled:
            collector.finish(section, "cancelled", code=130)
            continue
        stage = collector.state["stages"][section]
        stage.update(inventory=ids, total=len(ids) or None)
        if discovered or enumeration.get("errors"):
            collector.finish(section, "blocked", "Built test inventory unavailable; inspect enumeration log.", 1)
            continue
        if missing:
            stage["unresolvedSelectors"] = missing
            collector.state["failureCategory"] = "scope-unresolved"
            collector.finish(section, "blocked", "Scope unresolved in the freshly built inventory. Choose exact selectors or explicit full verification.", 2)
            continue
        stage.update(status="waiting", executionSelectors=execution)
        for key in ("phase", "startedAt", "finishedAt", "exitCode"):
            stage.pop(key, None)
    collector.publish()
    for section, target in zip(("code", "ui"), targets):
        stage = collector.state["stages"][section]
        if stage["status"] in {"skipped", "blocked", "cancelled"}:
            continue
        if collector.cancelled:
            collector.finish(section, "cancelled")
            continue
        if collector.state.get("failureCategory") == "scope-unresolved":
            collector.finish(section, "blocked", "Another requested selector is unresolved; no cases launched.", 2)
            continue
        bundle = collector.run / "results" / (section + ".xcresult")
        bundle.parent.mkdir(exist_ok=True)
        restrictions = [item for item in selection if item.startswith("-only-testing:" + target)]
        chosen = [item for item in selection if not item.startswith("-only-testing:")]
        chosen += stage["executionSelectors"]
        collector.command(section, base + ["test-without-building"] + chosen + [
            "-parallel-testing-enabled", "NO", "-resultBundlePath", str(bundle)], track=True)
        if stage["status"] == "passed" and (not stage["total"] or stage["completed"] != stage["total"]):
            collector.finish(section, "blocked", "Selected inventory lacks complete terminal evidence.", 1)
    if collector.cancelled:
        return 130
    return next((stage.get("exitCode") or 1 for stage in collector.state["stages"].values()
                 if stage["status"] in {"failed", "blocked"}), 0)


def run_owned(root, arguments, run, show_progress=True):
    collector = collector_module.Collector(root, run, "full")
    signal.signal(signal.SIGTERM, lambda *_: setattr(collector, "cancelled", True))
    signal.signal(signal.SIGINT, lambda *_: setattr(collector, "cancelled", True))
    collector.env.update(SITEFORGE_MONITOR_CHILD="1")
    collector.env["SITEFORGE_DERIVED_DATA"] = os.environ.get("SITEFORGE_DERIVED_DATA", collector.env["SITEFORGE_DERIVED_DATA"])
    collector.state["derivedDataPath"] = collector.env["SITEFORGE_DERIVED_DATA"]
    collector.state["sourceFingerprint"] = collector_module.source_fingerprint(root)
    collector.env["SITEFORGE_APP_BUNDLE_IDENTIFIER"] = "app.siteforge.SiteForge.OwnerTesting"
    metadata = run / "test-application-info.plist"
    values = collector_module.test_application_info(root / "SiteForge/Info.plist")
    values["SiteForgeTestToolingRoot"] = str(collector.prepare_tooling_inputs())
    metadata.write_bytes(collector_module.plistlib.dumps(values))
    collector.env["SITEFORGE_APP_INFO_PLIST"] = str(metadata)
    collector.env["SITEFORGE_STREAM_TEST_LOG"] = "1"
    collector.publish()
    viewer_log = (run / "progress.log").open("w")
    awake = None
    code = 1
    fixture = root / ".siteforge-test-fixtures"
    try:
        if fixture.is_dir() and not fixture.is_symlink():
            shutil.rmtree(fixture)
        if show_progress:
            try:
                viewer_command = ["xcrun", "swift", str(root / "scripts/full-verification-progress.swift"), str(run), "--monitor"]
                viewer = subprocess.Popen(viewer_command, stdout=viewer_log, stderr=subprocess.STDOUT, start_new_session=True)
                collector_module.atomic_json(run / "progress-owner.json", {"pid": viewer.pid, "command": viewer_command})
            except OSError as error:
                print("Progress window unavailable: " + type(error).__name__, file=sys.stderr)
        awake = subprocess.Popen(["caffeinate", "-di", "-w", str(os.getpid())])
        plan = run / "plan.json"
        environment = dict(collector.env, SITEFORGE_TEST_PLAN=str(plan))
        scope = ["test", "full"] if arguments == ["verify"] else arguments
        resolved = subprocess.run([str(root / "sf")] + scope, cwd=root, env=environment)
        if resolved.returncode:
            code = resolved.returncode
            collector.finish("preflight", "failed", "Test scope could not be resolved.", code)
            return code
        collector.finish("preflight", "passed")
        code = execute_plan(collector, json.loads(plan.read_text()), arguments == ["verify"])
        return code
    except Exception as error:
        collector.state["collectorFailure"] = type(error).__name__
        print("Testing stopped: " + type(error).__name__ + ". See " + str(run), file=sys.stderr)
        return 1
    finally:
        if awake:
            awake.terminate()
            awake.wait()
        for name, stage in collector.state["stages"].items():
            if stage["status"] not in collector_module.TERMINAL:
                collector.finish(name, "cancelled" if collector.cancelled else "blocked")
        result = collector_module.aggregate(collector.state["stages"])
        collector.state.update(status=result, finishedAt=collector_module.now(), exitCode=code)
        collector.publish()
        collector_module.atomic_json(run / "report.json", collector.state)
        (run / "REPORT.md").write_text("# SiteForge local testing\n\nResult " + result + "\n")
        if fixture.is_dir() and not fixture.is_symlink():
            shutil.rmtree(fixture)
        viewer_log.close()
        print("Testing report " + str(run))


def main():
    root = Path(__file__).resolve().parents[1]
    arguments = sys.argv[1:]
    headless = arguments[:1] == ["--headless"]
    if headless: arguments = arguments[1:]
    parent = Path.home() / "Library/Application Support/SiteForge/TestingReports"
    parent.mkdir(parents=True, exist_ok=True)
    lock = parent / "active.json"
    try:
        descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        print("A SiteForge testing run is already active. Inspect its report before starting another.", file=sys.stderr)
        return 2
    run = parent / uuid.uuid4().hex
    def interrupted(*_):
        raise InterruptedError("Testing launch interrupted")
    previous_term = signal.signal(signal.SIGTERM, interrupted)
    previous_int = signal.getsignal(signal.SIGINT)
    try:
        run.mkdir()
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"run": str(run), "pid": os.getpid()}, stream)
        collector_module.atomic_json(parent / "current.json", {"run": str(run)})
        return run_owned(root, arguments, run, show_progress=not headless)
    except (Exception, KeyboardInterrupt) as error:
        # Even failures before the collector is initialized leave a terminal
        # receipt and release ownership so the next invocation can start.
        state = {"status": "blocked", "mode": "full", "stages": {},
                 "collectorFailure": type(error).__name__, "finishedAt": collector_module.now(), "exitCode": 1}
        collector_module.atomic_json(run / "state.json", state)
        collector_module.atomic_json(run / "report.json", state)
        (run / "REPORT.md").write_text("# SiteForge local testing\n\nBlocked during launch. See report.json.\n")
        return 1
    finally:
        signal.signal(signal.SIGTERM, previous_term)
        signal.signal(signal.SIGINT, previous_int)
        try:
            if json.loads(lock.read_text()).get("run") == str(run):
                lock.unlink()
        except (OSError, ValueError):
            # A failure before the ownership record was written still owns
            # the exclusive file; no other run can have acquired it.
            if lock.exists() and not lock.stat().st_size:
                lock.unlink()


if __name__ == "__main__":
    sys.exit(main())
