"""Source acceptance for the Prompt-10 gate; not executed during the pause."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import sys
import threading
import time
import os
import shutil
import signal

SOURCE = Path(__file__).resolve().parents[2] / "scripts/unattended-verification.py"
SPEC = importlib.util.spec_from_file_location("collector", SOURCE)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class SourceFingerprintTests(unittest.TestCase):
    def test_staging_sources_does_not_change_fingerprint_but_content_does(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "SiteForge"
            source.mkdir()
            (source / "a.swift").write_text("struct A {}\n")
            (source / "z.swift").write_text("struct Z {}\n")
            runner.subprocess.run(["git", "init", "-q", directory], check=True, capture_output=True)
            runner.subprocess.run(["git", "add", "SiteForge/a.swift"], cwd=root, check=True, capture_output=True)
            before = runner.source_fingerprint(root)
            runner.subprocess.run(["git", "add", "SiteForge/z.swift"], cwd=root, check=True, capture_output=True)
            self.assertEqual(before, runner.source_fingerprint(root))
            (source / "z.swift").write_text("struct Changed {}\n")
            self.assertNotEqual(before, runner.source_fingerprint(root))

    def test_bundled_sample_bytes_additions_and_deletions_change_source_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner.subprocess.run(["git", "init", "-q", directory], check=True, capture_output=True)
            samples = root / "Samples" / "Example"
            samples.mkdir(parents=True)
            model = samples / "model.json"
            model.write_text("original")
            initial = runner.source_fingerprint(root)
            runner.subprocess.run(["git", "add", "Samples"], cwd=root, check=True, capture_output=True)
            self.assertEqual(initial, runner.source_fingerprint(root))
            model.write_text("changed")
            self.assertNotEqual(initial, runner.source_fingerprint(root))
            model.write_text("original")
            resource = samples / "image.png"
            resource.write_bytes(b"new bundled resource")
            self.assertNotEqual(initial, runner.source_fingerprint(root))
            resource.unlink()
            self.assertEqual(initial, runner.source_fingerprint(root))
            model.unlink()
            self.assertNotEqual(initial, runner.source_fingerprint(root))

class UnattendedVerificationTests(unittest.TestCase):
    def test_empty_ui_inventory_reports_automation_timeout_even_on_xcode_success(self):
        log = 'Failed to initialize for UI testing: Timed out while enabling automation mode.\n** TEST EXECUTE SUCCEEDED **'
        category, _ = runner.inventory_failure(log, "SiteForgeUITests")
        self.assertEqual(category, "xctest-host-unavailable")
        category, _ = runner.inventory_failure("No method inventory", "SiteForgeUITests")
        self.assertEqual(category, "test-inventory-unavailable")

    def test_progress_compile_failure_does_not_launch_or_claim_collector_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(sys, "argv", ["runner", "--root", directory]), \
                 patch.object(runner.subprocess, "run", return_value=SimpleNamespace(returncode=1, stderr="actor-isolation fixture")) as compile_check, \
                 patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 2)
            compile_check.assert_called_once_with(
                ["xcrun", "swiftc", "-typecheck", str(root.resolve() / "scripts/full-verification-progress.swift")],
                capture_output=True, text=True)
            launch.assert_not_called()
            self.assertFalse((root / ".codex-loop/full-verification/active.json").exists())

    def test_isolated_test_app_does_not_become_the_website_document_handler(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Info.plist"
            original = {"CFBundleDocumentTypes": [{"LSHandlerRank": "Owner", "LSItemContentTypes": ["app.siteforge.project-package"]}],
                        "SiteForgeTestApplicationIdentifier": "$(SITEFORGE_APP_BUNDLE_IDENTIFIER)"}
            source.write_bytes(runner.plistlib.dumps(original))
            adapted = runner.test_application_info(source)
            self.assertEqual(adapted["CFBundleDocumentTypes"][0]["LSHandlerRank"], "None")
            self.assertEqual(adapted["SiteForgeTestApplicationIdentifier"], original["SiteForgeTestApplicationIdentifier"])
            self.assertEqual(runner.plistlib.loads(source.read_bytes()), original)
    def test_test_event_distinguishes_start_completion_and_non_event_output(self):
        self.assertEqual(runner.test_event("Test Case '-[Example testOne]' started."),
                         {"id": "Example/testOne", "outcome": "started"})
        self.assertEqual(runner.test_event("Test Case '-[Example testOne]' failed (1.0 seconds)."),
                         {"id": "Example/testOne", "outcome": "failed", "durationSeconds": 1.0})
        self.assertEqual(runner.test_event("Test Case '-[Example testOne]' skipped (0.1 seconds)."),
                         {"id": "Example/testOne", "outcome": "skipped"})
        self.assertIsNone(runner.test_event("Log message mentioning Test Case '-[Example testOne]' started."))

    def test_live_case_clears_on_completion_and_duplicate_completion_counts_once(self):
        class Child:
            pid = 654321
            stdout = iter([
                "Test Case '-[SiteForgeUITests.Example testOne]' started.\n",
                "Test Case '-[SiteForgeUITests.Example testOne]' passed (1.0 seconds).\n",
                "Test Case '-[SiteForgeUITests.Example testOne]' passed (1.0 seconds).\n",
                "Test Case '-[SiteForgeUITests.Example testTwo]' started.\n",
            ])
            def wait(self): return -15
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector = runner.Collector(root, root, "full")
            snapshots = []
            def publish():
                stage = collector.state["stages"]["ui"]
                snapshots.append((stage.get("currentTest"), stage["completed"], stage["status"]))
            with patch.object(collector, "test_processes", return_value=[]), \
                 patch.object(runner.subprocess, "Popen", return_value=Child()), \
                 patch.object(collector, "publish", side_effect=publish):
                collector.command("ui", ["xcodebuild", "test-without-building"], track=True)
            self.assertIn(("SiteForgeUITests.Example/testOne", 0, "running"), snapshots)
            self.assertIn((None, 1, "running"), snapshots)
            self.assertEqual(snapshots[-2:], [
                ("SiteForgeUITests.Example/testTwo", 1, "running"), (None, 1, "failed")])
            self.assertNotIn("currentTestStartedAt", collector.state["stages"]["ui"])
            self.assertEqual(collector.state["stages"]["ui"]["timedCases"], 1)
            self.assertEqual(collector.state["stages"]["ui"]["timedSeconds"], 1.0)

    def test_unexpected_live_case_marks_remaining_count_unreliable_without_changing_inventory(self):
        class Child:
            pid = 654321
            stdout = iter([
                "Test Case '-[SiteForgeUITests.Example testRetained]' started.\n",
                "Test Case '-[SiteForgeUITests.Example testRetained]' passed (1.0 seconds).\n",
                "Test Case '-[SiteForgeUITests.Example testRenamed]' started.\n",
                "Test Case '-[SiteForgeUITests.Example testRenamed]' passed (1.0 seconds).\n",
            ])
            def wait(self): return 0
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector = runner.Collector(root, root, "ui")
            stage = collector.state["stages"]["ui"]
            stage.update(total=2, inventory=["SiteForgeUITests/Example/testRetained()", "Example/testOldName"])
            observations = []
            def publish():
                case = stage.get("currentTest")
                if case:
                    observations.append((case, stage.get("inventoryMismatch", False)))
            with patch.object(collector, "test_processes", return_value=[]), \
                 patch.object(runner.subprocess, "Popen", return_value=Child()), \
                 patch.object(collector, "publish", side_effect=publish):
                collector.command("ui", ["xcodebuild", "test-without-building"], track=True)
            self.assertEqual(observations, [
                ("SiteForgeUITests.Example/testRetained", False),
                ("SiteForgeUITests.Example/testRenamed", True),
            ])
            self.assertEqual(stage["total"], 2)
            self.assertEqual(stage["completed"], 2)
            self.assertTrue(stage["inventoryMismatch"])

    def test_authoritative_inventory_is_target_scoped_and_deduplicated(self):
        inventory = {"name": "SiteForgeTests", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": "Example/testOne"},
            {"nodeType": "Test Case", "nodeIdentifier": "Example/testOne"},
            {"nodeType": "Test Suite", "nodeIdentifier": "Example"}]}
        self.assertEqual(runner.inventory_ids(inventory, "SiteForgeTests"), ["Example/testOne"])
        self.assertEqual(runner.inventory_ids(inventory, "SiteForgeUITests"), [])
        self.assertEqual(runner.inventory_ids({"sourceMethodCount": 900}, "SiteForgeTests"), [])

    def test_failed_blocked_and_cancelled_are_never_success(self):
        for status in ("failed", "blocked", "cancelled"):
            self.assertEqual(runner.aggregate({"code": {"status": status}, "ui": {"status": "passed"}}), status)
        self.assertEqual(runner.aggregate({"code": {"status": "skipped"}, "ui": {"status": "passed"}}), "passed")

    def test_current_xcode_hierarchical_enumeration_has_exact_target_class_method_identifiers(self):
        inventory = {"errors": [], "values": [{"kind": "plan", "name": "SiteForge", "children": [
            {"kind": "target", "name": "SiteForgeTests", "children": [{"kind": "class", "name": "Suite", "children": [
                {"kind": "test", "name": "testOne()"}, {"kind": "test", "name": "testTwo()"}]}]}]}]}
        self.assertEqual(runner.inventory_ids(inventory, "SiteForgeTests"), ["SiteForgeTests/Suite/testOne", "SiteForgeTests/Suite/testTwo"])
        self.assertEqual(runner.inventory_ids(inventory, "SiteForgeUITests"), [])
        inventory["errors"] = ["Discovery unavailable"]
        self.assertEqual(runner.inventory_ids(inventory, "SiteForgeTests"), [])

    def test_state_is_atomic_and_unknown_inventory_remains_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector = runner.Collector(root, root, "full")
            collector.finish("code", "blocked", "Build unavailable")
            state = runner.json.loads((root / "state.json").read_text())
            self.assertIsNone(state["stages"]["code"]["total"])
            self.assertEqual(state["stages"]["code"]["completed"], 0)
            self.assertFalse((root / "state.json.tmp").exists())

    def test_failure_does_not_cancel_an_independent_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            collector = runner.Collector(Path(directory), Path(directory), "full")
            collector.finish("code", "failed", code=65)
            self.assertFalse(collector.cancelled)
            self.assertEqual(collector.state["stages"]["ui"]["status"], "waiting")
            collector.finish("ui", "passed", code=0)
            self.assertEqual(collector.state["stages"]["ui"]["status"], "passed")

    def test_confirmed_cancellation_targets_only_the_new_child_process_group(self):
        class Child:
            pid = 654321
            stdout = iter(["Test Case '-[Example testOne]' failed (0.1 seconds).\n"])
            def wait(self): return -15
            def poll(self): return None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector = runner.Collector(root, root, "full")
            original_publish = collector.publish
            def request_after_launch():
                original_publish()
                if collector.state["stages"]["ui"].get("processID"):
                    (root / "cancel.request").touch()
            with patch.object(collector, "test_processes", return_value=[]), \
                 patch.object(collector, "publish", side_effect=request_after_launch), \
                 patch.object(runner.subprocess, "Popen", return_value=Child()) as launch, patch.object(runner.os, "killpg") as kill:
                collector.command("ui", ["xcodebuild", "test-without-building"], track=True)
            self.assertTrue(launch.call_args.kwargs["start_new_session"])
            kill.assert_called_once_with(654321, runner.signal.SIGTERM)
            self.assertEqual(collector.state["stages"]["ui"]["status"], "cancelled")
            self.assertEqual(collector.state["stages"]["ui"]["failed"], 1)

    def test_cancel_before_launch_never_starts_a_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cancel.request").touch()
            collector = runner.Collector(root, root, "full")
            with patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(collector.command("code", ["unused"], track=True), 130)
            launch.assert_not_called()

    def test_desktop_release_only_terminates_the_owned_prepared_ui_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            collector = runner.Collector(Path(directory), Path(directory), "full")
            derived = collector.env["SITEFORGE_DERIVED_DATA"]
            listing = (f"100 {derived}/Build/SiteForgeUITests-Runner\n"
                       f"101 {derived}/Build/SiteForge.app/Contents/MacOS/SiteForge -SiteForgeUITestMode YES\n"
                       "102 /Applications/SiteForge.app/Contents/MacOS/SiteForge\n"
                       "103 /other/DerivedData/SiteForgeUITests-Runner\n")
            with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=listing)):
                self.assertEqual(collector.test_processes(), [100, 101])
            with patch.object(collector, "test_processes", side_effect=[[100, 101], []]), \
                 patch.object(runner.os, "kill") as kill:
                self.assertTrue(collector.release_desktop(True))
            self.assertEqual(kill.call_args_list, [unittest.mock.call(100, signal.SIGTERM), unittest.mock.call(101, signal.SIGTERM)])

    def test_canonical_runner_path_alias_cannot_escape_desktop_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = root / "actual"
            actual.mkdir()
            alias = root / "alias"
            alias.symlink_to(actual, target_is_directory=True)
            collector = runner.Collector(root, root, "full")
            collector.env["SITEFORGE_DERIVED_DATA"] = str(alias)
            listing = (f"100 {actual.resolve()}/Build/SiteForgeUITests-Runner\n"
                       f"101 {alias}/Build/SiteForgeUITests-Runner\n"
                       f"102 {actual.resolve()}-unrelated/Build/SiteForgeUITests-Runner\n")
            with patch.object(runner.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=listing)):
                self.assertEqual(collector.test_processes(), [100, 101])

    def exercise_pause(self, cancel=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "child.py"
            fixture.write_text("""import sys,time
if '-only-testing:SiteForgeTests/Example/testTwo' in sys.argv:
    print("Test Case '-[Example testTwo]' passed (0.2 seconds).", flush=True)
else:
    print("Test Case '-[Example testOne]' failed (0.1 seconds).", flush=True)
    time.sleep(20)
""")
            collector = runner.Collector(root, root, "full")
            stage = collector.state["stages"]["code"]
            stage.update(total=2, inventory=["SiteForgeTests/Example/testOne", "SiteForgeTests/Example/testTwo"])
            observations = []
            def controls():
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if stage["completed"] == 1:
                        (root / "pause.request").touch()
                        break
                    time.sleep(0.01)
                while time.monotonic() < deadline:
                    if collector.state["status"] == "paused":
                        observations.append((stage.get("processID"), stage["completed"], stage["failed"]))
                        time.sleep(0.12)
                        (root / ("cancel.request" if cancel else "resume.request")).touch()
                        return
                    time.sleep(0.01)
                collector.cancelled = True
            control = threading.Thread(target=controls)
            control.start()
            result = collector.command("code", [sys.executable, str(fixture), "-only-testing:SiteForgeTests",
                                       "-resultBundlePath", str(root / "first.xcresult")], track=True)
            control.join(timeout=10)
            self.assertFalse(control.is_alive())
            self.assertEqual(observations, [(None, 1, 1)])
            self.assertGreaterEqual(collector.state["pausedSeconds"], 0.1)
            self.assertNotIn("pauseStartedAt", collector.state)
            self.assertFalse((root / "pause.request").exists())
            if cancel:
                self.assertEqual(result, 130)
                self.assertEqual(stage["status"], "cancelled")
                self.assertEqual(len(stage["segments"]), 1)
            else:
                self.assertEqual(result, 1)  # A pre-pause failure survives a passing continuation.
                self.assertEqual(stage["status"], "failed")
                self.assertEqual(stage["completed"], 2)
                self.assertEqual(stage["failed"], 1)
                self.assertEqual(len(stage["segments"]), 2)
                resumed = stage["segments"][1]["arguments"]
                self.assertEqual([arg for arg in resumed if arg.startswith("-only-testing:")],
                                 ["-only-testing:SiteForgeTests/Example/testTwo"])
                self.assertNotEqual(resumed[resumed.index("-resultBundlePath") + 1], str(root / "first.xcresult"))
                self.assertFalse((root / "resume.request").exists())

    def test_pause_resumes_only_unresolved_selectors_and_preserves_failure(self):
        self.exercise_pause()

    def test_cancellation_while_paused_never_launches_a_continuation(self):
        self.exercise_pause(cancel=True)

    def test_duplicate_run_never_spawns_or_replaces_existing_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".codex-loop/full-verification"
            parent.mkdir(parents=True)
            lock = parent / "active.json"
            lock.write_text('{"run":"existing","pid":123}')
            with patch.object(sys, "argv", ["runner", "--root", str(root)]), patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 2)
            launch.assert_not_called()
            self.assertEqual(lock.read_text(), '{"run":"existing","pid":123}')

    def test_failed_selector_summary_preserves_authoritative_failure_and_deduplicates_events(self):
        stages = {"code": {"testFailures": [{"testIdentifierString": "Suite/testBad()", "failureText": "assertion"}],
                           "events": {"SiteForgeTests.Suite/testBad": "failed"}}, "ui": {"events": {"UISuite/testOther": "failed"}}}
        failures = runner.failed_selectors(stages)
        self.assertEqual([item["selector"] for item in failures], ["SiteForgeTests/Suite/testBad", "SiteForgeUITests/UISuite/testOther"])
        self.assertEqual(failures[0]["failureText"], "assertion")

    def _collect_with_fake_tools(self, build_fails=False, blocked=False, mode="full", root=None, ui_cases=None, selectors=(),
                                 fail_ready_stages=True, ui_results=None, split_ui_result=False):
        if root is None:
            folder = tempfile.TemporaryDirectory()
            self.addCleanup(folder.cleanup)
            root = Path(folder.name)
        run = Path(tempfile.mkdtemp(dir=root, prefix="run-"))
        (root / "scripts").mkdir(exist_ok=True)
        shutil.copyfile(SOURCE.with_name("ci-test-accounting.py"), root / "scripts/ci-test-accounting.py")
        cases = {"code": ["Suite/testBad"], "ui": ["Suite/testExample"] if ui_cases is None else ui_cases}
        fixture = root / ".siteforge-test-fixtures"
        fixture.mkdir()
        collector = runner.Collector(root, run, mode, selectors)
        calls = []
        def preflight():
            collector.finish("preflight", "blocked" if blocked else "passed")
            return not blocked
        def command(name, args, track=False):
            calls.append((name, args))
            fails = (name == "build" and build_fails) or (fail_ready_stages and (
                name == "repository" or (name == "code" and track)))
            if "-test-enumeration-output-path" in args:
                path = Path(args[args.index("-test-enumeration-output-path") + 1])
                target = "SiteForgeTests" if name == "code" else "SiteForgeUITests"
                path.write_text(runner.json.dumps({"name": target, "children": [
                    {"nodeType": "Test Case", "nodeIdentifier": selector} for selector in cases[name]
                ]}))
                if name == "ui" and not cases[name]:
                    (run / "ui.log").write_text("Timed out while enabling automation mode.")
            if track:
                selected = ("code", "ui") if mode == "full" else ("code",) if mode == "code" else ("ui",)
                for target in selected:
                    stage = collector.state["stages"][target]
                    self.assertEqual(stage["total"], len(cases[target]) or None)
                    self.assertEqual(stage["inventory"], sorted(cases[target]))
                if name == "ui" and split_ui_result:
                    continued = [argument.replace("ui.xcresult", "ui-resume.xcresult")
                                 if argument.endswith("/ui.xcresult") else argument for argument in args]
                    collector.state["stages"][name]["segments"] = [
                        {"arguments": args, "interruptedForPause": True},
                        {"arguments": continued, "interruptedForPause": False},
                    ]
            collector.finish(name, "failed" if fails else "passed", code=65 if fails else 0)
            return 65 if fails else 0
        def tool(args, **kwargs):
            if args[0] == "git":
                return SimpleNamespace(stdout="revision" if "rev-parse" in args else b"", returncode=0)
            if args[0] == "xcodebuild": return SimpleNamespace(stdout="Xcode fixture", returncode=0)
            if "test-results" in args:
                bundle_name = Path(args[args.index("--path") + 1]).name
                section = "code" if bundle_name == "code.xcresult" else "ui"
                count = len(cases[section])
                failed = section == "code" and fail_ready_stages
                summary = {"totalTestCount": count, "passedTests": 0 if failed else count,
                           "failedTests": count if failed else 0, "skippedTests": 0,
                           "testFailures": [{"testIdentifierString": "Suite/testBad()", "failureText": "assertion"}] if failed else []}
                outcomes = [(item, "Failed" if failed else "Passed", []) for item in cases[section]]
                if section == "ui" and ui_results is not None:
                    outcomes = ui_results
                if section == "ui" and split_ui_result:
                    outcomes = outcomes[1:] if bundle_name == "ui-resume.xcresult" else outcomes[:1]
                results = {"testNodes": [{
                    "nodeType": "Unit test bundle" if section == "code" else "UI test bundle",
                    "name": "SiteForgeTests" if section == "code" else "SiteForgeUITests",
                    "children": [{"nodeType": "Test Case", "nodeIdentifier": item, "result": outcome,
                                  "children": [{"nodeType": "Skip Message", "name": reason} for reason in reasons]}
                                 for item, outcome, reasons in outcomes],
                }]}
                kwargs["stdout"].write(runner.json.dumps(results if "tests" in args else summary))
            return SimpleNamespace(returncode=0)
        awake = SimpleNamespace(terminate=lambda: None, wait=lambda: 0)
        with patch.object(collector, "preflight", side_effect=preflight), patch.object(collector, "command", side_effect=command), \
             patch.object(runner.subprocess, "run", side_effect=tool), patch.object(runner.subprocess, "Popen", return_value=awake):
            code = collector.collect()
        self.assertFalse(fixture.exists(), "Established fixture cleanup remains active")
        for name in ("state.json", "report.json", "REPORT.md", "failures.json", "failed-selectors.json"):
            self.assertTrue((run / name).exists(), name)
        return code, collector.state, calls

    def test_equal_completion_count_cannot_hide_a_missing_selector(self):
        code, state, _ = self._collect_with_fake_tools(mode="ui", ui_results=[("Suite/testWrong", "Passed", [])])
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")
        self.assertIn("missing=['SiteForgeUITests/Suite/testExample']", state["stages"]["ui"]["detail"])

    def test_only_approved_skip_reason_can_pass(self):
        item = "SiteForgeLaunchTests/testOwnerDarkFlowNativeThemeAndFlow"
        reason = "Requires the owner-open independent Dark Flow project"
        for reported, expected_code in [(reason, 0), ("Unrelated skip", 1)]:
            with self.subTest(reported=reported):
                code, state, _ = self._collect_with_fake_tools(mode="ui", ui_cases=[item],
                                                               ui_results=[(item, "Skipped", [reported])])
                self.assertEqual(code, expected_code)
                self.assertEqual(state["stages"]["ui"]["skipped"], 1)
                self.assertEqual(len(runner.failed_selectors(state["stages"])), expected_code)

    def test_result_matches_xcode_inventory_with_bundle_prefix(self):
        method = "Suite/testExample"
        code, state, _ = self._collect_with_fake_tools(mode="ui", ui_cases=[f"SiteForgeUITests/{method}"],
                                                       ui_results=[(method + "()", "Passed", [])])
        self.assertEqual(code, 0)
        self.assertEqual(state["stages"]["ui"]["passed"], 1)

    def test_resumed_suite_requires_exact_results_across_both_segments(self):
        cases = ["Suite/testBeforePause", "Suite/testAfterPause"]
        code, state, _ = self._collect_with_fake_tools(mode="ui", ui_cases=cases, split_ui_result=True)
        self.assertEqual(code, 0)
        self.assertEqual(state["stages"]["ui"]["completed"], 2)
        self.assertEqual(len(state["stages"]["ui"]["artifactExports"]), 2)
        duplicate_results = [(cases[0], "Passed", [])] * 2
        code, state, _ = self._collect_with_fake_tools(mode="ui", ui_cases=cases, ui_results=duplicate_results,
                                                       split_ui_result=True)
        self.assertEqual(code, 1)
        self.assertIn("duplicates=['SiteForgeUITests/Suite/testBeforePause']", state["stages"]["ui"]["detail"])

    def test_collection_continues_after_repository_and_code_failures_and_retains_reports(self):
        code, state, calls = self._collect_with_fake_tools()
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["code"]["status"], "failed")
        self.assertEqual(state["stages"]["ui"]["status"], "passed")
        self.assertTrue(any(name == "ui" and "test-without-building" in args for name, args in calls))
        self.assertEqual(state["stages"]["ui"]["completed"], 1)
        for name, args in calls:
            if args[0] == "xcodebuild":
                self.assertIn("ONLY_ACTIVE_ARCH=YES", args, name)
                self.assertEqual(args[args.index("-destination") + 1], f"platform=macOS,arch={runner.platform.machine()}")
            if "-resultBundlePath" in args:
                self.assertEqual(args[args.index("-test-timeouts-enabled") + 1], "YES", name)

    def test_full_collection_retains_regular_results_on_ui_discovery_timeout(self):
        code, state, calls = self._collect_with_fake_tools(ui_cases=[], fail_ready_stages=False)
        self.assertEqual(code, 1)
        self.assertEqual(state["status"], "blocked")
        self.assertEqual(state["failureCategory"], "xctest-host-unavailable")
        self.assertEqual(state["stages"]["code"]["status"], "passed")
        self.assertEqual(state["stages"]["code"]["passed"], 1)
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")
        self.assertFalse(any(name == "ui" and "-resultBundlePath" in args for name, args in calls))

    def test_explicit_combined_scope_still_blocks_if_one_target_cannot_be_discovered(self):
        _, state, calls = self._collect_with_fake_tools(ui_cases=[], fail_ready_stages=False,
            selectors=("SiteForgeTests/Suite/testBad", "SiteForgeUITests/Suite/testExample"))
        self.assertEqual(state["stages"]["code"]["status"], "blocked")
        self.assertFalse(any("-resultBundlePath" in args for _, args in calls))

    def test_consecutive_runs_enumerate_added_deleted_and_renamed_cases_from_each_build(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = ["Suite/testKeep", "Suite/testDeleted", "Suite/testOldName"]
            revised = ["Suite/testKeep", "Suite/testNewName", "Suite/testAddedOne", "Suite/testAddedTwo"]
            _, before, _ = self._collect_with_fake_tools(root=root, mode="ui", ui_cases=original)
            _, after, _ = self._collect_with_fake_tools(root=root, mode="ui", ui_cases=revised)
            self.assertNotEqual(before["derivedDataPath"], after["derivedDataPath"])
            self.assertEqual(before["stages"]["ui"]["inventory"], sorted(original))
            self.assertEqual(after["stages"]["ui"]["inventory"], sorted(revised))
            self.assertEqual((before["stages"]["ui"]["total"], after["stages"]["ui"]["total"]), (3, 4))

    def test_build_failure_blocks_dependent_targets_without_faking_success(self):
        code, state, calls = self._collect_with_fake_tools(build_fails=True)
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["code"]["status"], "blocked")
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")
        self.assertFalse(any(name in ("code", "ui") for name, _ in calls))

    def test_ui_only_preparation_failure_keeps_unrequested_code_skipped(self):
        _, state, _ = self._collect_with_fake_tools(build_fails=True, mode="ui")
        self.assertEqual(state["stages"]["code"]["status"], "skipped")
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")

    def test_source_changed_during_build_blocks_test_execution(self):
        with patch.object(runner, "source_fingerprint", side_effect=["before", "after"]):
            _, state, calls = self._collect_with_fake_tools()
        self.assertEqual(state["stages"]["build"]["status"], "blocked")
        self.assertEqual(state["failureCategory"], "source-changed-during-build")
        self.assertFalse(any(name in ("code", "ui") for name, _ in calls))

    def test_preflight_block_retains_final_report_and_executes_no_test_stage(self):
        code, state, calls = self._collect_with_fake_tools(blocked=True)
        self.assertEqual(code, 1)
        self.assertEqual(state["status"], "blocked")
        self.assertEqual(calls, [])

    def test_ui_only_mode_is_explicitly_skipped_not_a_code_pass(self):
        code, state, calls = self._collect_with_fake_tools(mode="ui")
        self.assertEqual(code, 0)
        self.assertEqual(state["stages"]["code"]["status"], "skipped")
        self.assertEqual(state["stages"]["repository"]["status"], "skipped")
        self.assertFalse(any(name == "code" for name, _ in calls))

    def test_regular_scope_preserves_code_failure_and_never_runs_ui_or_repository(self):
        code, state, calls = self._collect_with_fake_tools(mode="code")
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["code"]["status"], "failed")
        self.assertEqual(state["stages"]["ui"]["status"], "skipped")
        self.assertEqual(state["stages"]["repository"]["status"], "skipped")
        self.assertFalse(any(name == "ui" for name, _ in calls))
        self.assertEqual(state["scope"], {"mode": "code", "selectors": []})

    def test_prepared_selectors_are_persisted_and_execution_remains_exact(self):
        selector = "SiteForgeTests/Suite/testBad"
        _, state, calls = self._collect_with_fake_tools(mode="code", selectors=[selector])
        self.assertEqual(state["scope"]["selectors"], [selector])
        execution = [args for name, args in calls if name == "code" and "-resultBundlePath" in args]
        self.assertEqual(len(execution), 1)
        self.assertEqual([arg for arg in execution[0] if arg.startswith("-only-testing:")], ["-only-testing:" + selector])
        self.assertEqual(state["stages"]["code"]["inventory"], ["Suite/testBad"])

    def test_build_activity_is_distinct_and_contains_only_current_product_names(self):
        line = r"SwiftCompile normal arm64 Compiling\\ TestingWindow.swift,\\ SupportSettings.swift /private/fixture/TestingWindow.swift"
        self.assertEqual(runner.build_activity(line), "Compiling TestingWindow.swift, SupportSettings.swift")
        self.assertEqual(runner.build_activity("CodeSign /private/fixture/Products/App.app"), "Signing local test products")
        self.assertIsNone(runner.build_activity("unrelated diagnostic"))

    def test_history_matches_fresh_case_identities_without_reusing_old_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); previous = root / "previous"; previous.mkdir()
            run = root / "current"; run.mkdir()
            receipt = {"runID": "previous", "mode": "code", "status": "failed", "toolchain": "Xcode fixture",
                       "scope": {"mode": "code", "selectors": ["SiteForgeTests/Suite"]},
                       "derivedDataPath": "/tmp/SiteForge/Unattended/previous/DerivedData",
                       "testArtifact": {"CFBundleIdentifier": "app.siteforge.SiteForge.OwnerTesting"},
                       "stages": {"build": {"status": "passed", "commandSeconds": 80},
                                  "code": {"status": "failed", "total": 999,
                                           "durations": {"Suite/testOld": 10, "Suite/testRemoved": 100}}}}
            runner.atomic_json(previous / "report.json", receipt)
            collector = runner.Collector(root, run, "code", ["SiteForgeTests/Suite"])
            collector.state["toolchain"] = "Xcode fixture"
            collector.load_timing_history()
            self.assertEqual(collector.preparation_history["build"], 80)
            stage = collector.state["stages"]["code"]
            stage.update(inventory=["SiteForgeTests/Suite/" + name for name in ("testOne", "testTwo", "testOld", "testAdded")], total=4)
            collector.update_case_estimate("code")
            self.assertNotIn("estimatedRemainingSeconds", stage, "New methods have no historical count or invented timing")
            stage.update(events={"Suite/testOne": "passed", "Suite/testTwo": "passed"}, completed=2,
                         durations={"Suite/testOne": 2, "Suite/testTwo": 4}, currentTest="Suite/testOld")
            collector.update_case_estimate("code")
            self.assertEqual(stage["total"], 4)
            self.assertEqual(stage["estimatedRemainingSeconds"], 13)
            self.assertEqual(stage["estimatedCurrentCaseSeconds"], 10)
            collector.state["toolchain"] = "Different Xcode"
            collector.load_timing_history()
            self.assertEqual(collector.preparation_history, {})
            self.assertEqual(collector.case_history["code"], {})

    def test_native_source_guard_has_ownership_and_retains_stale_receipt_without_test_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".codex-loop/full-verification"
            def fingerprint(collector, name, args, track=False):
                self.assertTrue((parent / "active.json").exists())
                self.assertEqual(runner.json.loads((parent / "current.json").read_text())["run"], str(collector.run))
                self.assertFalse(collector.state["pauseAvailable"])
                runner.atomic_json(Path(args[-1]), {"sourceFingerprint": "new"})
                collector.finish(name, "passed", code=0)
                return 0
            arguments = ["runner", "--root", directory, "--mode", "code", "--progress", str(root / "monitor"),
                         "--expected-source-fingerprint", "old", "--source-check-progress"]
            with patch.object(sys, "argv", arguments), patch.object(runner, "open_progress"), \
                 patch.object(runner.Collector, "command", fingerprint), patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 2)
            launch.assert_not_called()
            self.assertFalse((parent / "active.json").exists())
            run = Path(runner.json.loads((parent / "current.json").read_text())["run"])
            report = runner.json.loads((run / "report.json").read_text())
            self.assertEqual(report["failureCategory"], "stale-source")
            self.assertEqual(report["sourceFingerprint"], "new")

    def test_native_source_check_cancels_before_any_test_target_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".codex-loop/full-verification"
            def cancelled(collector, name, args, track=False):
                collector.cancelled = True
                return 130
            arguments = ["runner", "--root", directory, "--mode", "code", "--progress", str(root / "monitor"),
                         "--expected-source-fingerprint", "old", "--source-check-progress"]
            with patch.object(sys, "argv", arguments), patch.object(runner, "open_progress"), \
                 patch.object(runner.Collector, "command", cancelled), patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 130)
            launch.assert_not_called()
            self.assertFalse((parent / "active.json").exists())
            run = Path(runner.json.loads((parent / "current.json").read_text())["run"])
            report = runner.json.loads((run / "report.json").read_text())
            self.assertEqual(report["status"], "cancelled")
            self.assertEqual(report["failureCategory"], "source-check-cancelled")

    def test_owner_local_runs_use_both_complete_targets_and_isolated_app_identity(self):
        _, state, calls = self._collect_with_fake_tools()
        for section, target in (("code", "SiteForgeTests"), ("ui", "SiteForgeUITests")):
            commands = [args for name, args in calls if name == section and "-resultBundlePath" in args]
            self.assertEqual(len(commands), 1)
            expected = ["-only-testing:" + target + "/" + item.removesuffix("()") for item in state["stages"][section]["inventory"]]
            self.assertEqual([item for item in commands[0] if item.startswith("-only-testing:")], expected)
            enumerations = [args for name, args in calls if name == section and "-enumerate-tests" in args]
            self.assertIn("-only-testing:" + target, enumerations[0])
            self.assertIn("SITEFORGE_APP_BUNDLE_IDENTIFIER=app.siteforge.SiteForge.OwnerTesting", commands[0])

    def test_owner_local_persistent_reports_root_preserves_duplicate_lock_without_workspace_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reports = root / "application-support-reports"
            reports.mkdir()
            lock = reports / "active.json"
            lock.write_text('{"run":"retained","pid":123}')
            with patch.object(sys, "argv", ["runner", "--root", str(root), "--reports-root", str(reports)]), \
                 patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 2)
            launch.assert_not_called()
            self.assertEqual(lock.read_text(), '{"run":"retained","pid":123}')

    def test_stale_provisioned_source_never_launches_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, "argv", ["runner", "--root", directory, "--expected-source-fingerprint", "old"]), \
                 patch.object(runner, "source_fingerprint", return_value="new"), \
                 patch.object(runner.subprocess, "Popen") as launch:
                self.assertEqual(runner.main(), 2)
            launch.assert_not_called()
            report_root = Path(directory) / ".codex-loop/full-verification"
            current = runner.json.loads((report_root / "current.json").read_text())
            report = runner.json.loads((Path(current["run"]) / "report.json").read_text())
            self.assertEqual(report["status"], "blocked")
            self.assertEqual(report["failureCategory"], "stale-source")
            self.assertTrue((Path(current["run"]) / "REPORT.md").is_file())

if __name__ == "__main__": unittest.main()


class ExecutableScopeTests(unittest.TestCase):
    def test_renamed_class_hint_is_unresolved_in_current_build(self):
        exact, missing = runner.executable_selection(['SiteForgeTests/NewTests/testOne'],
            ['-only-testing:SiteForgeTests/OldTests'], 'SiteForgeTests')
        self.assertEqual(exact, [])
        self.assertEqual(missing, ['SiteForgeTests/OldTests'])

    def test_removed_method_prevents_partial_execution_of_mixed_request(self):
        exact, missing = runner.executable_selection(['SiteForgeTests/Suite/testSurviving'],
            ['-only-testing:SiteForgeTests/Suite/testRemoved', '-only-testing:SiteForgeTests/Suite/testSurviving'], 'SiteForgeTests')
        self.assertEqual(exact, [])
        self.assertEqual(missing, ['SiteForgeTests/Suite/testRemoved'])

    def test_class_scope_executes_only_fresh_renamed_methods(self):
        exact, missing = runner.executable_selection(['SiteForgeTests/Suite/testRenamed()', 'SiteForgeTests/Other/testOne'],
            ['-only-testing:SiteForgeTests/Suite'], 'SiteForgeTests')
        self.assertEqual(exact, ['-only-testing:SiteForgeTests/Suite/testRenamed'])
        self.assertEqual(missing, [])

    def test_existing_method_api_and_empty_inventory_remain_conservative(self):
        self.assertEqual(runner.executable_selection(['Suite/testOne()'],
            ['-only-testing:SiteForgeTests/Suite/testOne'], 'SiteForgeTests'),
            (['-only-testing:SiteForgeTests/Suite/testOne'], []))
        self.assertEqual(runner.executable_selection([], ['-only-testing:SiteForgeTests'], 'SiteForgeTests'),
            ([], ['SiteForgeTests']))


class PreparedToolingInputsTests(unittest.TestCase):
    def test_prepared_inputs_match_source_and_exclude_deleted_and_ignored_files(self):
        import json
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'source';root.mkdir()
            run = Path(directory) / 'report';run.mkdir()
            for name in ('sf', 'scripts/select-test-scope.py', 'Tests/Tooling/test_scope.py'):
                file = root / name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text(name)
            runner.subprocess.run(['git','init','-q'],cwd=root,check=True,capture_output=True)
            (root/'.gitignore').write_text('scripts/ignored.py\n')
            (root/'scripts/ignored.py').write_text('not a prepared input')
            collector = runner.Collector(root,run,'code')
            collector.state['sourceFingerprint'] = 'fixture-source'
            prepared = collector.prepare_tooling_inputs()
            self.assertEqual((prepared/'sf').read_bytes(),(root/'sf').read_bytes())
            self.assertFalse((prepared/'scripts/ignored.py').exists())
            ledger=json.loads((run/'tooling-inputs.json').read_text())
            self.assertEqual(ledger['sourceFingerprint'],'fixture-source')
            self.assertEqual(len(ledger['files']),3)
            for item in ledger['files']:
                self.assertEqual(hashlib.sha256((prepared/item['path']).read_bytes()).hexdigest(),item['sha256'])
