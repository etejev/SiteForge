"""Focused tooling ledger attached by the native Regular Testing XCTest case."""
import importlib.util
import json
from pathlib import Path
import sys
import time
import unittest

root = Path(__file__).resolve().parents[2]
report = Path(sys.argv[1])
suite = unittest.TestSuite()
for name in ('test_scope_selection', 'test_unattended_verification', 'test_testing_foreground',
             'test_testing_commands', 'test_open_testing_window', 'test_testing_progress'):
    spec = importlib.util.spec_from_file_location(name, root / 'Tests/Tooling' / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
spec = importlib.util.spec_from_file_location('scope_self_tests', root / 'scripts/select-test-scope.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))

class Ledger(unittest.TextTestResult):
    def startTest(self, test):
        super().startTest(test); self.started = time.monotonic()
    def record(self, test, outcome, detail=None):
        self.entries.append(dict(case=test.id(), outcome=outcome, seconds=time.monotonic()-self.started, detail=detail))
    def addSuccess(self, test): super().addSuccess(test); self.record(test, 'passed')
    def addFailure(self, test, error): super().addFailure(test, error); self.record(test, 'failed', self._exc_info_to_string(error,test))
    def addError(self, test, error): super().addError(test, error); self.record(test, 'error', self._exc_info_to_string(error,test))
    def addSkip(self, test, reason): super().addSkip(test, reason); self.record(test, 'skipped', reason)
    def __init__(self, *args): super().__init__(*args); self.entries=[]
result = unittest.TextTestRunner(verbosity=2, resultclass=Ledger).run(suite)
report.write_text(json.dumps(dict(requirements=['SF-1902-007','SF-1902-008','SF-0206-006','SF-0206-008','SF-1607-006','SF-1607-008'], kind='nested-tooling-checks',
    total=result.testsRun, passed=sum(x['outcome']=='passed' for x in result.entries),
    failed=len(result.failures)+len(result.errors), skipped=len(result.skipped), cases=result.entries), indent=2)+'\n')
sys.exit(0 if result.wasSuccessful() else 1)
