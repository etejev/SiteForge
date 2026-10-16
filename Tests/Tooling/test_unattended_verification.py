"""Source acceptance for the Prompt-10 gate; not executed during the pause."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import sys

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

class UnattendedVerificationTests(unittest.TestCase):
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
    def test_completed_event_is_a_completion_not_a_start(self):
        self.assertIsNone(runner.completed_event("Test Case '-[Example testOne]' started."))
        self.assertEqual(runner.completed_event("Test Case '-[Example testOne]' failed (1.0 seconds)."),
                         {"id": "Example/testOne", "outcome": "failed"})

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
            (root / "cancel.request").touch()
            collector = runner.Collector(root, root, "full")
            with patch.object(runner.subprocess, "Popen", return_value=Child()) as launch, patch.object(runner.os, "killpg") as kill:
                collector.command("ui", ["xcodebuild", "test-without-building"], track=True)
            self.assertTrue(launch.call_args.kwargs["start_new_session"])
            kill.assert_called_once_with(654321, runner.signal.SIGTERM)
            self.assertEqual(collector.state["stages"]["ui"]["status"], "cancelled")
            self.assertEqual(collector.state["stages"]["ui"]["failed"], 1)

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

    def _collect_with_fake_tools(self, build_fails=False, blocked=False, mode="full"):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        run = root / "run"
        run.mkdir()
        fixture = root / ".siteforge-test-fixtures"
        fixture.mkdir()
        collector = runner.Collector(root, run, mode)
        calls = []
        def preflight():
            collector.finish("preflight", "blocked" if blocked else "passed")
            return not blocked
        def command(name, args, track=False):
            calls.append((name, args))
            fails = name == "repository" or (name == "build" and build_fails) or (name == "code" and track)
            if "-test-enumeration-output-path" in args:
                path = Path(args[args.index("-test-enumeration-output-path") + 1])
                path.write_text('{"name":"SiteForgeTests","children":[{"nodeType":"Test Case","nodeIdentifier":"Suite/testBad"}]}')
            collector.finish(name, "failed" if fails else "passed", code=65 if fails else 0)
            return 65 if fails else 0
        def tool(args, **kwargs):
            if args[0] == "git":
                return SimpleNamespace(stdout="revision" if "rev-parse" in args else b"", returncode=0)
            if args[0] == "xcodebuild": return SimpleNamespace(stdout="Xcode fixture", returncode=0)
            if "test-results" in args:
                section = "code" if "code.xcresult" in args[args.index("--path") + 1] else "ui"
                summary = {"totalTestCount": 1, "passedTests": int(section == "ui"), "failedTests": int(section == "code"), "skippedTests": 0,
                           "testFailures": [{"testIdentifierString": "Suite/testBad()", "failureText": "assertion"}] if section == "code" else []}
                kwargs["stdout"].write(runner.json.dumps(summary))
            return SimpleNamespace(returncode=0)
        awake = SimpleNamespace(terminate=lambda: None, wait=lambda: 0)
        with patch.object(collector, "preflight", side_effect=preflight), patch.object(collector, "command", side_effect=command), \
             patch.object(runner.subprocess, "run", side_effect=tool), patch.object(runner.subprocess, "Popen", return_value=awake):
            code = collector.collect()
        self.assertFalse(fixture.exists(), "Established fixture cleanup remains active")
        for name in ("state.json", "report.json", "REPORT.md", "failures.json", "failed-selectors.json"):
            self.assertTrue((run / name).exists(), name)
        return code, collector.state, calls

    def test_collection_continues_after_repository_and_code_failures_and_retains_reports(self):
        code, state, calls = self._collect_with_fake_tools()
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["code"]["status"], "failed")
        self.assertEqual(state["stages"]["ui"]["status"], "passed")
        self.assertTrue(any(name == "ui" and "test-without-building" in args for name, args in calls))
        self.assertEqual(state["stages"]["ui"]["completed"], 1)

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

    def test_owner_local_runs_use_both_complete_targets_and_isolated_app_identity(self):
        _, _, calls = self._collect_with_fake_tools()
        for section, target in (("code", "SiteForgeTests"), ("ui", "SiteForgeUITests")):
            commands = [args for name, args in calls if name == section and "-resultBundlePath" in args]
            self.assertEqual(len(commands), 1)
            self.assertIn("-only-testing:" + target, commands[0])
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
