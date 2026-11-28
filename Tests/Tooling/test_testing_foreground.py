"""Exact-scope preparation and terminal accounting for the local CLI monitor."""
import importlib.util
import json
from pathlib import Path
import tempfile
import signal
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("foreground", Path(__file__).resolve().parents[2] / "scripts/testing-foreground.py")
foreground = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(foreground)


class ForegroundTests(unittest.TestCase):
    def exercise(self, selectors=(), missing_inventory=False, enumeration_error=False, changed_source=False, build_exit=0, test_exit=0, verify=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector = foreground.collector_module.Collector(root, root, "full")
            collector.state["sourceFingerprint"] = "before"
            collector.finish("preflight", "passed")
            calls = []
            def command(name, args, track=False):
                calls.append((name, args, track))
                if "-enumerate-tests" in args:
                    target = "SiteForgeTests" if name == "code" else "SiteForgeUITests"
                    leaves = [] if missing_inventory else [{"kind": "test", "name": "testOne()"}]
                    Path(args[args.index("-test-enumeration-output-path") + 1]).write_text(json.dumps({
                        "errors": ["automation unavailable"] if enumeration_error and name == "ui" else [],
                        "kind": "target", "name": target, "children": [{"kind": "class", "name": "Suite", "children": leaves}]}))
                code = build_exit if name == "build" else test_exit if track else 0
                collector.finish(name, "failed" if code else "passed", code=code)
                if track:
                    collector.state["stages"][name]["completed"] = 1
                return code
            plan = ["xcodebuild", "-scheme", "SiteForge", "-resultBundlePath", "planned.xcresult", "test"]
            plan += ["-only-testing:" + item for item in selectors]
            with patch.object(collector, "command", side_effect=command), patch.object(
                    foreground.collector_module, "source_fingerprint", return_value="changed" if changed_source else "before"):
                code = foreground.execute_plan(collector, plan, verify)
            return code, collector.state, calls

    def test_removed_method_blocks_all_requested_execution(self):
        code, state, calls = self.exercise(['SiteForgeTests/Suite/testOne', 'SiteForgeTests/Suite/testRemoved'])
        self.assertEqual(code, 2)
        self.assertEqual(state['failureCategory'], 'scope-unresolved')
        self.assertEqual(state['stages']['code']['unresolvedSelectors'], ['SiteForgeTests/Suite/testRemoved'])
        self.assertFalse(any(track for _, _, track in calls))

    def test_renamed_class_never_launches_old_selector(self):
        code, state, calls = self.exercise(['SiteForgeTests/OldSuite'])
        self.assertEqual(code, 2)
        self.assertFalse(any(track for _, _, track in calls))

    def test_headless_backend_retains_report_without_launching_viewer(self):
        from types import SimpleNamespace
        signals = {item: signal.getsignal(item) for item in (signal.SIGINT, signal.SIGTERM)}
        self.addCleanup(lambda: [signal.signal(item, handler) for item, handler in signals.items()])
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); run=root/'run';run.mkdir();(root/'SiteForge').mkdir()
            (root/'SiteForge/Info.plist').write_bytes(foreground.collector_module.plistlib.dumps({}))
            def plan(args,**kwargs):
                Path(kwargs['env']['SITEFORGE_TEST_PLAN']).write_text(json.dumps(['xcodebuild','-resultBundlePath','planned.xcresult','test']))
                return SimpleNamespace(returncode=0)
            def executed(collector,*args):
                for name in collector.state['stages']: collector.finish(name,'passed')
                return 0
            awake=SimpleNamespace(terminate=lambda:None,wait=lambda:0)
            with patch.object(foreground.collector_module,'source_fingerprint',return_value='fixture'), \
                 patch.object(foreground.collector_module.Collector,'prepare_tooling_inputs',return_value=root), \
                 patch.object(foreground.subprocess,'Popen',return_value=awake) as started, \
                 patch.object(foreground.subprocess,'run',side_effect=plan), \
                 patch.object(foreground,'execute_plan',side_effect=executed):
                self.assertEqual(foreground.run_owned(root,['test','focused','SiteForgeTests/Suite'],run,show_progress=False),0)
            self.assertEqual(len(started.call_args_list),1)
            self.assertEqual(started.call_args.args[0][0],'caffeinate')
            self.assertEqual(json.loads((run/'report.json').read_text())['status'],'passed')
            self.assertFalse((run/'progress-owner.json').exists())

    def test_focused_selector_never_expands_to_another_target_or_suite(self):
        code, state, calls = self.exercise(["SiteForgeTests/Suite/testOne"])
        self.assertEqual(code, 0)
        self.assertEqual(state["stages"]["ui"]["status"], "skipped")
        tracked = [args for _, args, track in calls if track]
        self.assertEqual(len(tracked), 1)
        self.assertIn("-only-testing:SiteForgeTests/Suite/testOne", tracked[0])
        self.assertNotIn("-only-testing:SiteForgeTests", tracked[0])
        self.assertEqual(state["stages"]["code"]["total"], 1)

    def test_enumeration_of_entire_product_is_intersected_with_exact_scope(self):
        leaves = ["SiteForgeTests/Suite/testOne", "SiteForgeTests/Suite/testTwo", "SiteForgeTests/Other/testOne"]
        self.assertEqual(foreground.selected_inventory(leaves, ["-only-testing:SiteForgeTests/Suite/testOne"], "SiteForgeTests"), leaves[:1])
        self.assertEqual(foreground.selected_inventory(leaves, ["-only-testing:SiteForgeTests/Suite",
                         "-skip-testing:SiteForgeTests/Suite/testTwo"], "SiteForgeTests"), leaves[:1])
        self.assertEqual(foreground.selected_inventory(leaves, [], "SiteForgeTests"), leaves)

    def test_interrupted_launch_releases_ownership_and_retains_a_terminal_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(foreground.Path, "home", return_value=Path(directory)), \
                 patch.object(foreground, "run_owned", side_effect=InterruptedError("fixture")):
                self.assertEqual(foreground.main(), 1)
            parent = Path(directory) / "Library/Application Support/SiteForge/TestingReports"
            self.assertFalse((parent / "active.json").exists())
            report = Path(json.loads((parent / "current.json").read_text())["run"]) / "report.json"
            self.assertEqual(json.loads(report.read_text())["status"], "blocked")

    def test_full_plan_enumerates_both_targets_before_testing(self):
        code, state, calls = self.exercise(verify=True)
        self.assertEqual(code, 0)
        self.assertEqual([name for name, _, _ in calls], ["repository", "build", "code", "ui", "code", "ui"])
        self.assertIn("build-for-testing", calls[1][1])
        self.assertTrue(all("test-without-building" in args for _, args, _ in calls[2:]))
        self.assertEqual([state["stages"][name]["total"] for name in ("code", "ui")], [1, 1])

    def test_target_enumeration_does_not_launch_other_target_and_host_error_blocks_retry(self):
        code, state, calls = self.exercise(["SiteForgeTests/Suite/testOne", "SiteForgeUITests/Suite/testOne"], enumeration_error=True)
        self.assertEqual(code, 1)
        self.assertEqual(state["stages"]["code"]["status"], "passed")
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")
        enumerations = [(name, args) for name, args, _ in calls if "-enumerate-tests" in args]
        self.assertEqual(len(enumerations), 2)
        self.assertNotIn("-only-testing:SiteForgeUITests/Suite/testOne", enumerations[0][1])
        self.assertNotIn("-only-testing:SiteForgeTests/Suite/testOne", enumerations[1][1])
        self.assertFalse(any(name == "ui" and track for name, _, track in calls))

    def test_missing_inventory_blocks_before_any_case_executes(self):
        code, state, calls = self.exercise(missing_inventory=True)
        self.assertEqual(code, 2)
        self.assertFalse(any(track for _, _, track in calls))
        self.assertEqual(state["stages"]["ui"]["completed"], 0)
        self.assertIsNone(state["stages"]["ui"]["total"])
        self.assertEqual(state["stages"]["ui"]["status"], "blocked")

    def test_source_change_after_build_prevents_test_launch(self):
        code, state, calls = self.exercise(changed_source=True)
        self.assertEqual(code, 2)
        self.assertEqual(state["stages"]["build"]["status"], "blocked")
        self.assertEqual(len(calls), 1)

    def test_build_and_test_exit_codes_are_preserved(self):
        self.assertEqual(self.exercise(build_exit=19)[0], 19)
        self.assertEqual(self.exercise(test_exit=65)[0], 65)


if __name__ == "__main__":
    unittest.main()
