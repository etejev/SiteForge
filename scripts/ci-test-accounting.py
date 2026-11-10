"""OD-031: schedule exact XCTest selectors and reconcile hosted receipts."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


SHARDS = 8
CORE = "SiteForgeTests"
UI = "SiteForgeUITests"
UI_PREFIX = f"{UI}/SiteForgeLaunchTests/"
TIMINGS = Path(__file__).with_name("ci-ui-timings.txt")
SELECTOR = re.compile(r"(SiteForgeTests|SiteForgeUITests)/[A-Za-z_][\w]*/test[A-Za-z_0-9]+", re.ASCII)
SKIPS = {
    UI_PREFIX + "testOwnerDarkFlowNativeThemeAndFlow": "Requires the owner-open independent Dark Flow project",
    UI_PREFIX + "testOwnerDarkFlowVisibleGradientControls": "Requires the owner-open independent Dark Flow project",
    UI_PREFIX + "testOwnerDarkFlowTransferSavedProjectToCurrentBuild": "Requires explicit owner-session project and isolation storage",
}
OUTCOMES = {"Passed", "Failed", "Skipped"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def selector(value):
    require(isinstance(value, str), "Test identifier is not a string")
    value = value.removesuffix("()")
    require(SELECTOR.fullmatch(value), f"Unsupported test identifier: {value!r}")
    return value


def partition(path=TIMINGS):
    durations = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, seconds = line.split()
        key = selector(UI_PREFIX + name)
        require(key not in durations and int(seconds) > 0, f"Duplicate or invalid timing: {key}")
        durations[key] = int(seconds)
    require(set(SKIPS) <= durations.keys(), "Owner-only skip policy is missing a selector")
    loads = [0] * SHARDS
    groups = [[] for _ in loads]
    for key in sorted(durations, key=lambda item: (-durations[item], item)):
        i = min(range(SHARDS), key=loads.__getitem__)
        groups[i].append(key)
        loads[i] += durations[key]
    require(all(groups), "Empty UI shard")
    return [sorted(group) for group in groups], loads


def exact(actual, expected, label):
    seen = set()
    duplicates = set()
    for item in actual:
        if item in seen:
            duplicates.add(item)
        seen.add(item)
    missing, unknown = set(expected) - seen, seen - set(expected)
    if missing or unknown or duplicates:
        raise ValueError(f"{label}: missing={sorted(missing)} unknown={sorted(unknown)} duplicates={sorted(duplicates)}")


def discovery(payload, groups):
    require(not payload["errors"], "Xcode test enumeration reported errors")
    require(len(payload["values"]) == 1, "Expected one destination and test plan")
    plan = payload["values"][0]
    require(not plan["disabledTests"], "The full scheme has disabled selectors")
    enabled = [selector(entry["identifier"]) for entry in plan["enabledTests"]]
    ui = [key for key in enabled if key.startswith(UI + "/")]
    exact(ui, [key for group in groups for key in group], "UI discovery vs timing manifest")
    core = [key for key in enabled if key.startswith(CORE + "/")]
    require(core, "Empty non-UI discovery")
    exact(core, core, "Non-UI discovery")
    return sorted(core)


def records(payload):
    def visit(nodes, target=None):
        for node in nodes:
            kind = node["nodeType"]
            if kind in ("Unit test bundle", "UI test bundle"):
                target = node["name"]
            if kind == "Test Case":
                key = selector(f"{target}/{node['nodeIdentifier']}")
                outcome = node["result"]
                require(outcome in OUTCOMES, f"{key}: nonterminal or unknown result {outcome!r}")
                reasons = [child["name"] for child in node.get("children", [])
                           if child["nodeType"] == "Skip Message"]
                yield {"selector": key, "outcome": outcome, "reasons": reasons}
            else:
                yield from visit(node.get("children", []), target)
    return list(visit(payload["testNodes"]))


def reconcile(receipts, groups, sha):
    labels = ["core", *(f"ui-{i}" for i in range(1, SHARDS + 1))]
    exact([item["job"] for item in receipts], labels, "Job receipts")
    by_job = {item["job"]: item for item in receipts}
    core = discovery(by_job["core"]["enumeration"], groups)
    errors = []
    for label, expected in zip(labels, [core, *groups], strict=True):
        receipt = by_job[label]
        require(receipt["sha"] == sha, f"{label}: receipt SHA mismatch")
        entries = receipt["records"]
        keys = [selector(record["selector"]) for record in entries]
        counts = {result: sum(entry["outcome"] == result for entry in entries)
                  for result in sorted(OUTCOMES)}
        print(f"{label}: {counts}; not recorded={len(set(expected) - set(keys))}; execution={receipt['execution']}")
        if receipt["execution"] != "success" or receipt["error"]:
            errors.append(f"{label}: {receipt['execution']}: {receipt['error']}")
        try:
            exact(keys, expected, label)
        except ValueError as error:
            errors.append(str(error))
        for key, record in zip(keys, entries, strict=True):
            outcome = record["outcome"]
            if outcome == "Skipped" and key in SKIPS:
                reason = SKIPS[key]
                if record["reasons"] in ([reason], ["Test skipped - " + reason]):
                    print(f"  {key}: {reason}")
                    continue
            if outcome != "Passed":
                errors.append(f"{key}: {outcome} {record['reasons']}")
    require(not errors, "\n".join(errors))


def load(path):
    return json.loads(path.read_text())


def create_receipt(args):
    result = dict(sha=args.sha, job=args.job, execution=args.execution, records=[], error="")
    try:
        if args.job == "core":
            result["enumeration"] = load(args.directory / "enumeration.json")
        bundles = list((args.directory / "TestResults").glob("*.xcresult"))
        require(len(bundles) == 1, "Expected exactly one finalized XCTest result bundle")
        bundle = bundles[0]
        require(bundle.with_suffix(".log").is_file(), "Missing XCTest transcript")
        raw = subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)],
            text=True, timeout=60)
        result["records"] = records(json.loads(raw))
        require(result["records"], "Empty XCTest result")
    except (ValueError, KeyError, OSError, TypeError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    (args.directory / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{args.job}: {len(result['records'])} XCTest outcomes; {result['execution']}; {result['error']}")
    return 1 if result["error"] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("plan")
    selected = commands.add_parser("selectors")
    selected.add_argument("shard", type=int, choices=range(1, SHARDS + 1))
    discover = commands.add_parser("discover")
    discover.add_argument("enumeration", type=Path)
    receipt = commands.add_parser("receipt")
    receipt.add_argument("directory", type=Path)
    receipt.add_argument("job", choices=["core", *(f"ui-{i}" for i in range(1, SHARDS + 1))])
    receipt.add_argument("sha")
    receipt.add_argument("execution", choices=["success", "failure", "cancelled", "skipped"])
    verify = commands.add_parser("verify")
    verify.add_argument("directory", type=Path)
    verify.add_argument("sha")
    args = parser.parse_args()
    try:
        groups, loads = partition()
        if args.command == "plan":
            for i, (group, load_seconds) in enumerate(zip(groups, loads, strict=True), 1):
                print(f"UI shard {i}: {len(group)} selectors; {load_seconds}s historical")
        elif args.command == "selectors":
            print("\n".join(groups[args.shard - 1]))
        elif args.command == "discover":
            core = discovery(load(args.enumeration), groups)
            print(f"Discovered {len(core)} non-UI and {sum(map(len, groups))} UI selectors.")
        elif args.command == "receipt":
            return create_receipt(args)
        else:
            reconcile([load(path) for path in sorted(args.directory.glob("*/receipt.json"))],
                      groups, args.sha)
    except (ValueError, KeyError, OSError, TypeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
