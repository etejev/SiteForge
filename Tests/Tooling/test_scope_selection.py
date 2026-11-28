"""SF-1902-007/008: real Git history and actual selector CLI regressions."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('scope_selector', ROOT / 'scripts/select-test-scope.py')
scope = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scope)

class ScopeGitTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.env = dict(os.environ, GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
        self.git('init', '-q')
        for path in ['SiteForge/DocumentLifecycle.swift', 'Tests/SiteForgeTests/DocumentLifecycleTests.swift',
                     'Tests/SiteForgeTests/DocumentLifecycleRaceTests.swift', 'Tests/SiteForgeTests/RemovedTests.swift',
                     'docs/note.md']:
            self.write(path, path)
        self.git('add', '.')
        self.git('commit', '-qm', 'baseline')
        self.base = self.git('rev-parse', 'HEAD').strip()

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgSign=false', *args],
                                       cwd=self.root, env=self.env, text=True)

    def write(self, path, content):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def change(self, old, new=None, state='unstaged'):
        if new: (self.root / old).rename(self.root / new)
        else: (self.root / old).unlink()
        if state != 'unstaged': self.git('add', '-A')
        if state == 'committed': self.git('commit', '-qm', 'fixture change')

    def selection(self, base=None):
        result = subprocess.run([sys.executable, str(scope.__file__), '--root', str(self.root), '--base', base or self.base],
                                text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def lifecycle(self):
        return ['SiteForgeTests/DocumentLifecycleRaceTests', 'SiteForgeTests/DocumentLifecycleTests']

    def test_unstaged_production_deletion(self):
        self.change('SiteForge/DocumentLifecycle.swift')
        self.assertIn('SiteForge/DocumentLifecycle.swift', scope.changed_paths(self.root, self.base))
        self.assertEqual(self.selection(), self.lifecycle())

    def test_staged_production_deletion(self):
        self.change('SiteForge/DocumentLifecycle.swift', state='staged')
        self.assertEqual(self.selection(), self.lifecycle())

    def test_committed_production_deletion(self):
        self.change('SiteForge/DocumentLifecycle.swift', state='committed')
        self.assertEqual(self.selection(), self.lifecycle())

    def test_unstaged_identical_production_rename(self):
        self.rename_production('unstaged')

    def test_staged_identical_production_rename(self):
        self.rename_production('staged')

    def test_committed_identical_production_rename(self):
        self.rename_production('committed')

    def rename_production(self, state):
        old, new = 'SiteForge/DocumentLifecycle.swift', 'SiteForge/FutureFeature.swift'
        self.change(old, new, state)
        self.assertEqual(scope.changed_paths(self.root, self.base), sorted([old, new]))
        self.assertEqual(self.selection(), ['FULL'])

    def test_known_production_move_keeps_surviving_regressions(self):
        (self.root / 'SiteForge/Moved Sources').mkdir()
        self.change('SiteForge/DocumentLifecycle.swift', 'SiteForge/Moved Sources/DocumentLifecycle.swift', 'committed')
        self.assertEqual(self.selection(), self.lifecycle())

    def test_unstaged_test_deletion(self):
        self.change('Tests/SiteForgeTests/RemovedTests.swift')
        self.assertEqual(self.selection(), ['FULL'])

    def test_staged_test_deletion(self):
        self.change('Tests/SiteForgeTests/RemovedTests.swift', state='staged')
        self.assertEqual(self.selection(), ['FULL'])

    def test_committed_test_deletion(self):
        self.change('Tests/SiteForgeTests/RemovedTests.swift', state='committed')
        self.assertEqual(self.selection(), ['FULL'])

    def test_unstaged_identical_test_rename(self):
        self.rename_test('unstaged')

    def test_staged_identical_test_rename(self):
        self.rename_test('staged')

    def test_committed_identical_test_rename(self):
        self.rename_test('committed')

    def rename_test(self, state):
        old, new = 'Tests/SiteForgeTests/RemovedTests.swift', 'Tests/SiteForgeTests/ReplacementTests.swift'
        self.change(old, new, state)
        self.assertEqual(scope.changed_paths(self.root, self.base), sorted([old, new]))
        self.assertEqual(self.selection(), ['FULL'])

    def test_missing_mapped_suite_never_becomes_explicit_scope(self):
        self.change('SiteForge/DocumentLifecycle.swift')
        self.change('Tests/SiteForgeTests/DocumentLifecycleRaceTests.swift')
        self.assertEqual(self.selection(), ['FULL'])

    def test_actual_sf_plan_resolves_deletion_and_refuses_unknown_scope(self):
        import json
        import shutil
        shutil.copy2(ROOT / 'sf', self.root / 'sf')
        (self.root / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/select-test-scope.py', self.root / 'scripts/select-test-scope.py')
        self.write('SiteForge.xcodeproj/project.pbxproj', 'fixture')
        self.git('add', '.'); self.git('commit', '-qm', 'CLI fixture')
        base = self.git('rev-parse', 'HEAD').strip()
        self.change('SiteForge/DocumentLifecycle.swift')
        plan = self.root / '.git/plan.json'
        env = dict(self.env, SITEFORGE_TEST_PLAN=str(plan), SITEFORGE_MONITOR_CHILD='1')
        result = subprocess.run([str(self.root/'sf'), 'test', 'changed', base], env=env, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(sorted(item.removeprefix('-only-testing:') for item in json.loads(plan.read_text()) if item.startswith('-only-testing:')), self.lifecycle())
        self.write('SiteForge/Unknown.swift','fixture')
        result = subprocess.run([str(self.root/'sf'), 'test', 'changed', base], env=env, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode,2)
        self.assertIn('No bounded test scope',result.stderr)

    def test_untracked_test_selects_current_filename_hint(self):
        self.write('Tests/SiteForgeTests/ExtraTests.swift', 'fixture')
        self.assertEqual(self.selection(), ['SiteForgeTests/ExtraTests'])

    def test_current_test_modification_preserves_class_api(self):
        self.write('Tests/SiteForgeTests/RemovedTests.swift', 'changed fixture')
        self.assertEqual(self.selection(), ['SiteForgeTests/RemovedTests'])

    def test_missing_base_keeps_working_deletion(self):
        self.change('SiteForge/DocumentLifecycle.swift')
        self.assertEqual(self.selection('missing-base'), self.lifecycle())

    def test_missing_base_clean_checkout_is_smoke(self):
        self.assertEqual(self.selection('missing-base'), list(scope.QUICK_SELECTORS))

    def test_docs_only_and_clean_use_smoke(self):
        self.assertEqual(self.selection(), list(scope.QUICK_SELECTORS))
        self.write('docs/note.md', 'modified')
        self.assertEqual(self.selection(), list(scope.QUICK_SELECTORS))

    def test_nul_paths_preserve_spaces_tabs_newlines_and_no_quoting(self):
        paths = ['docs/with space.md', 'docs/with\ttab.md', 'docs/with\nnewline.md']
        for path in paths: self.write(path, 'fixture')
        self.git('add', '.'); self.git('commit', '-qm', 'whitespace paths')
        self.assertEqual(scope.changed_paths(self.root, self.base), sorted(paths))
        self.assertEqual(self.selection(), list(scope.QUICK_SELECTORS))

    def test_untracked_spaced_test_filename_is_unresolved(self):
        self.write('Tests/SiteForgeTests/With SpacesTests.swift', 'fixture')
        self.assertEqual(self.selection(), ['FULL'])

    def test_committed_index_worktree_untracked_union_deduplicates(self):
        self.write('SiteForge/DocumentLifecycle.swift', 'committed')
        self.git('add', '.'); self.git('commit', '-qm', 'edit')
        self.write('SiteForge/DocumentLifecycle.swift', 'staged')
        self.git('add', '.')
        self.write('SiteForge/DocumentLifecycle.swift', 'worktree')
        self.write('docs/untracked.md', 'fixture')
        self.assertEqual(scope.changed_paths(self.root, self.base), ['SiteForge/DocumentLifecycle.swift', 'docs/untracked.md'])
        self.assertEqual(self.selection(), self.lifecycle())

if __name__ == '__main__': unittest.main(verbosity=2)
