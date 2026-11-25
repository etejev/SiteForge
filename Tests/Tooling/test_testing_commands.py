"""Command boundaries: exact plans, headless execution, and build-only watch."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestingCommandTests(unittest.TestCase):
    def prepare(self, directory):
        root = Path(directory)
        (root / 'scripts').mkdir()
        (root / 'bin').mkdir()
        (root / 'SiteForge.xcodeproj').mkdir()
        shutil.copy2(ROOT / 'sf', root / 'sf')
        selector = root / 'scripts/select-test-scope.py'
        selector.write_text('#!/bin/zsh\nprint FULL\n')
        selector.chmod(0o755)
        shim = root / 'bin/xcodebuild'
        shim.write_text('#!/bin/zsh\nprint -rl -- "$@" >> "$SITEFORGE_COMMAND_MARKER"\nexit 19\n')
        shim.chmod(0o755)
        environment = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                           TMPDIR=str(root) + '/', SITEFORGE_COMMAND_MARKER=str(root / 'calls'),
                           SITEFORGE_DERIVED_DATA=str(root / 'DerivedData'))
        for key in ('CI', 'GITHUB_ACTIONS', 'SITEFORGE_TEST_PLAN', 'SITEFORGE_MONITOR_CHILD', 'SSH_CONNECTION'):
            environment.pop(key, None)
        return root, environment

    def test_hosted_and_ssh_invocations_keep_direct_execution_and_exit_code(self):
        for settings in ({'GITHUB_ACTIONS': 'true'}, {'SSH_CONNECTION': 'headless-fixture'}):
            with self.subTest(settings=settings), tempfile.TemporaryDirectory() as directory:
                root, env = self.prepare(directory)
                result = subprocess.run([str(root / 'sf'), 'test', 'quick'], env=dict(env, **settings), capture_output=True, text=True)
                self.assertEqual(result.returncode, 19, result.stderr)
                self.assertIn('-only-testing:SiteForgeTests/AppMetadataTests', (root / 'calls').read_text())

    def test_plans_preserve_scope_and_unmapped_changes_never_expand(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.prepare(directory)
            plan = root / 'plan.json'
            env['SITEFORGE_TEST_PLAN'] = str(plan)
            for arguments, expected in ((['quick'], 2), (['half'], 1), (['full'], 0),
                                        (['focused', 'SiteForgeTests/Suite/testOne'], 1)):
                with self.subTest(arguments=arguments):
                    result = subprocess.run([str(root / 'sf'), 'test'] + arguments, env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    command = json.loads(plan.read_text())
                    self.assertEqual(len([item for item in command if item.startswith('-only-testing:')]), expected)
            result = subprocess.run([str(root / 'sf'), 'test', 'changed'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('No bounded test scope', result.stderr)
            self.assertFalse((root / 'calls').exists())

    def test_headless_changed_uses_inventory_validating_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env = self.prepare(directory)
            (root/'scripts/select-test-scope.py').write_text('#!/bin/zsh\nprint SiteForgeTests/Suite\n')
            (root/'scripts/testing-foreground.py').write_text('import json,sys,os\nfrom pathlib import Path\nPath(os.environ["SITEFORGE_COMMAND_MARKER"]).write_text(json.dumps(sys.argv[1:]))\nsys.exit(23)\n')
            result = subprocess.run([str(root/'sf'),'test','changed'], env=dict(env,SSH_CONNECTION='fixture'), capture_output=True,text=True)
            self.assertEqual(result.returncode,23,result.stderr)
            self.assertEqual(json.loads((root/'calls').read_text()), ['--headless','test','focused','SiteForgeTests/Suite'])

    def test_watch_only_builds_on_start_and_source_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'SiteForge').mkdir()
            source = root / 'SiteForge/Test.swift'
            source.write_text('struct Initial {}')
            shutil.copy2(ROOT / 'scripts/watch-and-verify.sh', root / 'scripts/watch-and-verify.sh')
            shim = root / 'sf'
            shim.write_text('#!/bin/zsh\nprint -r -- "$@" >> "${0:A:h}/calls"\n')
            shim.chmod(0o755)
            child = subprocess.Popen(['/bin/zsh', str(root / 'scripts/watch-and-verify.sh')], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
            def wait_for(count):
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if (root / 'calls').exists() and len((root / 'calls').read_text().splitlines()) >= count:
                        return
                    time.sleep(.05)
                self.fail('Watch did not observe the expected build')
            try:
                wait_for(1)
                source.write_text('struct ChangedAndLonger {}')
                wait_for(2)
                self.assertEqual((root / 'calls').read_text().splitlines(), ['build', 'build'])
            finally:
                os.killpg(child.pid, signal.SIGTERM)
                child.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
