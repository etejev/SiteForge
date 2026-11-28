"""A local CLI prepares native scope without launching any test products."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import sys

spec = importlib.util.spec_from_file_location("open_testing", Path(__file__).resolve().parents[2] / "scripts/open-testing-window.py")
opener = importlib.util.module_from_spec(spec)
spec.loader.exec_module(opener)

class OpenTestingWindowTests(unittest.TestCase):
    def test_focused_cli_only_resolves_scope_and_opens_native_review(self):
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            if args[0].endswith("/sf"):
                environment = kwargs["env"]
                self.assertEqual(environment["SITEFORGE_MONITOR_CHILD"], "1")
                Path(environment["SITEFORGE_TEST_PLAN"]).write_text(json.dumps(
                    ["xcodebuild", "test", "-only-testing:SiteForgeTests/Suite/testOne"]))
            return SimpleNamespace(returncode=0)
        with patch.object(sys, "argv", ["opener", "test", "focused", "SiteForgeTests/Suite/testOne"]), \
             patch.object(opener.Path, "is_dir", return_value=True), patch.object(opener.subprocess, "run", side_effect=command):
            self.assertEqual(opener.main(), 0)
        self.assertEqual(calls[1][0], "/usr/bin/open")
        payload = json.loads(calls[2][-1])
        self.assertEqual(payload, {"mode": "code", "selectors": ["SiteForgeTests/Suite/testOne"]})
        self.assertFalse(any(args[0] == "xcodebuild" for args in calls))

    def test_changed_cli_opens_same_native_resolver_including_unresolved_scope(self):
        calls = []
        with patch.object(sys, 'argv', ['opener', 'test', 'changed', 'fixture-base']), \
             patch.object(opener.Path, 'is_dir', return_value=True), \
             patch.object(opener.subprocess, 'run', side_effect=lambda args, **kw: (calls.append(args) or SimpleNamespace(returncode=0))):
            self.assertEqual(opener.main(), 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(json.loads(calls[1][-1]),
                         {'mode': 'full', 'selectors': [], 'policy': 'affected', 'base': 'fixture-base'})
        self.assertFalse(any(args[0].endswith('/sf') for args in calls))

    def test_changed_empty_base_and_environment_defaults_match_cli(self):
        for alias, value, expected in [('changed', '', 'origin/main'), ('impacted', 'fixture-environment', 'fixture-environment')]:
            calls=[]
            with patch.dict(opener.os.environ, {'SITEFORGE_TEST_BASE':value}), \
                 patch.object(sys,'argv',['opener','test',alias,'']), \
                 patch.object(opener.Path,'is_dir',return_value=True), \
                 patch.object(opener.subprocess,'run',side_effect=lambda args,**kw:(calls.append(args) or SimpleNamespace(returncode=0))):
                self.assertEqual(opener.main(),0)
            self.assertEqual(json.loads(calls[-1][-1])['base'],expected)

    def test_missing_installation_never_falls_back_to_automatic_testing(self):
        with patch.object(sys, "argv", ["opener", "verify"]), \
             patch.object(opener.Path, "is_dir", return_value=False), patch.object(opener.subprocess, "run") as launch:
            self.assertEqual(opener.main(), 2)
        launch.assert_not_called()

if __name__ == "__main__":
    unittest.main()
