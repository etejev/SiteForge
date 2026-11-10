"""Synthetic and checked-in OD-031 accounting regressions; no XCTest launch."""

import copy
import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("accounting", Path(__file__).with_name("ci-test-accounting.py"))
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)


class AccountingTests(unittest.TestCase):
    def setUp(self):
        self.groups, self.loads = CI.partition()
        self.ui = [key for group in self.groups for key in group]
        self.core = ["SiteForgeTests/CoreTests/testOne"]
        self.enumeration = {"errors": [], "values": [{
            "disabledTests": [],
            "enabledTests": [{"identifier": key + "()"} for key in self.core + self.ui],
        }]}
        self.receipts = []
        for job, keys in zip(["core", *(f"ui-{i}" for i in range(1, 9))],
                             [self.core, *self.groups], strict=True):
            self.receipts.append(dict(sha="candidate", job=job, execution="success", error="",
                                      records=[dict(selector=key, outcome="Skipped" if key in CI.SKIPS else "Passed",
                                                    reasons=[CI.SKIPS[key]] if key in CI.SKIPS else []) for key in keys]))
        self.receipts[0]["enumeration"] = self.enumeration

    def test_complete_balanced_exact_union_and_owner_skips(self):
        self.assertEqual(len(self.ui), len(set(self.ui)))
        self.assertLess(max(self.loads) - min(self.loads), 10)
        CI.reconcile(self.receipts, self.groups, "candidate")

    def test_missing_new_duplicate_disabled_and_bad_plan_fail_closed(self):
        for change in ("missing", "new", "duplicate", "disabled", "multiple"):
            with self.subTest(change=change):
                candidate = copy.deepcopy(self.enumeration)
                enabled = candidate["values"][0]["enabledTests"]
                if change == "missing":
                    enabled.pop()
                elif change == "new":
                    enabled.append({"identifier": CI.UI_PREFIX + "testNew"})
                elif change == "duplicate":
                    enabled.append(enabled[-1])
                elif change == "disabled":
                    candidate["values"][0]["disabledTests"] = [enabled.pop()]
                else:
                    candidate["values"].append(candidate["values"][0])
                with self.assertRaises(ValueError):
                    CI.discovery(candidate, self.groups)

    def test_timeout_failure_wrong_sha_missing_job_wrong_shard_and_bad_skip_fail(self):
        for change in ("timeout", "failure", "wrong-sha", "missing-job", "wrong-shard", "skip", "duplicate"):
            with self.subTest(change=change):
                candidate = copy.deepcopy(self.receipts)
                if change == "timeout":
                    candidate[1].update(execution="cancelled", records=[], error="No result bundle")
                elif change == "failure":
                    candidate[1]["records"][0]["outcome"] = "Failed"
                elif change == "wrong-sha":
                    candidate[1]["sha"] = "stale"
                elif change == "missing-job":
                    candidate.pop()
                elif change == "wrong-shard":
                    candidate[1]["records"][0] = candidate[2]["records"][0]
                elif change == "skip":
                    candidate[1]["records"][0].update(outcome="Skipped", reasons=["Unapproved"])
                else:
                    candidate[1]["records"].append(candidate[1]["records"][0])
                with self.assertRaises(ValueError):
                    CI.reconcile(candidate, self.groups, "candidate")

    def test_result_tree_preserves_skip_reason_and_rejects_nonterminal_result(self):
        key, reason = next(iter(CI.SKIPS.items()))
        node = {"nodeType": "Test Case", "nodeIdentifier": key.split("/", 1)[1] + "()",
                "result": "Skipped", "children": [{"nodeType": "Skip Message", "name": "Test skipped - " + reason}]}
        tree = {"testNodes": [{"nodeType": "Test Plan", "children": [
            {"nodeType": "UI test bundle", "name": CI.UI, "children": [node]}]}]}
        self.assertEqual(CI.records(tree), [{"selector": key, "outcome": "Skipped", "reasons": ["Test skipped - " + reason]}])
        node["result"] = "Running"
        with self.assertRaises(ValueError):
            CI.records(tree)

    def test_xcode_26_omitted_skip_reason_requires_exact_transcript_diagnostic(self):
        key, reason = next(iter(CI.SKIPS.items()))
        target, suite, method = key.split("/")
        entries = [{"selector": key, "outcome": "Skipped", "reasons": []}]
        other = f"/checkout/Test.swift:245: -[{suite} testOther] : Test skipped - {reason}"
        CI.restore_skip_reasons(entries, other)
        self.assertEqual(entries[0]["reasons"], [])
        exact = f"/checkout/Test.swift:245: -[{target}.{suite} {method}] : Test skipped - {reason}"
        CI.restore_skip_reasons(entries, exact)
        self.assertEqual(entries[0]["reasons"], [reason])
        entries[0]["reasons"] = []
        CI.restore_skip_reasons(entries, exact + "\n" + exact)
        self.assertEqual(entries[0]["reasons"], [reason, reason])


if __name__ == "__main__":
    unittest.main(buffer=True)
