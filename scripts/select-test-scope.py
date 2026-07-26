#!/usr/bin/env python3
"""Select conservative XCTest coverage for the repository's changed files.

This helper only narrows local feedback. The authoritative ``./sf verify``
command always executes the full unit and UI test suite.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import unittest
from pathlib import Path


QUICK_SELECTORS = (
    "SiteForgeTests/AppMetadataTests",
    "SiteForgeTests/ArchitectureBoundaryTests",
)

SOURCE_TESTS = {
    "CanvasRendererCore.swift": ("CanvasRendererTests", "SelectionModelTests"),
    "CanvasViewport.swift": ("CanvasViewportTests", "CanvasRendererTests"),
    "CommandKernel.swift": ("CommandKernelTests", "InsertionModelTests"),
    "ContentView.swift": ("ArchitectureBoundaryTests", "SiteForgeLaunchTests"),
    "DocumentLifecycle.swift": (
        "DocumentLifecycleTests",
        "DocumentLifecycleRaceTests",
    ),
    "DocumentModel.swift": (
        "CommandKernelTests",
        "BlankProjectTests",
        "InsertionModelTests",
    ),
    "FileAccessBoundary.swift": (
        "FileAccessBoundaryTests",
        "DocumentLifecycleTests",
    ),
    "IdentityBoundFileSystem.swift": (
        "IdentityBoundFileSystemTests",
        "ProjectPackageTests",
    ),
    "InsertionModel.swift": (
        "InsertionModelTests",
        "CommandKernelTests",
        "SelectionModelTests",
        "CanvasRendererTests",
        "LayoutEngineTests",
        "SiteForgeLaunchTests",
    ),
    "LaunchExperience.swift": ("LaunchExperienceTests", "SiteForgeLaunchTests"),
    "LayoutEngine.swift": ("LayoutEngineTests", "CanvasRendererTests"),
    "PersistedHistory.swift": (
        "PersistedHistoryTests",
        "DocumentLifecycleTests",
        "InsertionModelTests",
    ),
    "ProjectPackage.swift": (
        "ProjectPackageTests",
        "PersistedHistoryTests",
        "ProjectResourceTests",
        "DocumentLifecycleTests",
    ),
    "ProjectResources.swift": ("ProjectResourceTests", "ProjectPackageTests"),
    "SelectionModel.swift": (
        "SelectionModelTests",
        "CanvasRendererTests",
        "SiteForgeLaunchTests",
    ),
    "SiteForgeApp.swift": ("ArchitectureBoundaryTests", "SiteForgeLaunchTests"),
    "WorkspaceMaterialPolicy.swift": (
        "WorkspaceMaterialPolicyTests",
        "SiteForgeLaunchTests",
    ),
    "WorkspaceSceneComposition.swift": (
        "ArchitectureBoundaryTests",
        "SiteForgeLaunchTests",
    ),
    "WorkspaceShellModel.swift": (
        "CommandKernelTests",
        "SelectionModelTests",
        "InsertionModelTests",
        "SiteForgeLaunchTests",
    ),
    "WorkspaceShellView.swift": (
        "WorkspaceMaterialPolicyTests",
        "SelectionModelTests",
        "InsertionModelTests",
        "SiteForgeLaunchTests",
    ),
}

FULL_SUITE_PREFIXES = (
    ".github/workflows/",
    "SiteForge.xcodeproj/",
)

IGNORED_PREFIXES = (
    "docs/",
)

IGNORED_FILES = {
    ".gitignore",
    "AGENTS.md",
    "README.md",
}


def selector_for_test_path(path: str) -> str | None:
    parts = Path(path).parts
    if len(parts) != 3 or parts[0] != "Tests":
        return None
    stem = Path(path).stem
    if parts[1] == "SiteForgeTests" and stem.endswith("Tests"):
        return f"SiteForgeTests/{stem}"
    if parts[1] == "SiteForgeUITests" and stem.endswith("Tests"):
        return f"SiteForgeUITests/{stem}"
    return None


def select_for_paths(paths: list[str]) -> tuple[str, ...] | None:
    """Return selectors, or None when the full suite is the safe choice."""
    selectors: set[str] = set()
    relevant_path_seen = False

    for path in sorted(set(paths)):
        if path in IGNORED_FILES or path.startswith(IGNORED_PREFIXES):
            continue

        relevant_path_seen = True
        if path == "SiteForge.xcodeproj/project.pbxproj" or path.startswith(
            FULL_SUITE_PREFIXES
        ):
            return None

        direct_selector = selector_for_test_path(path)
        if direct_selector:
            selectors.add(direct_selector)
            continue

        if path.startswith("SiteForge/") and path.endswith(".swift"):
            test_names = SOURCE_TESTS.get(Path(path).name)
            if test_names is None:
                return None
            for test_name in test_names:
                target = (
                    "SiteForgeUITests"
                    if test_name == "SiteForgeLaunchTests"
                    else "SiteForgeTests"
                )
                selectors.add(f"{target}/{test_name}")
            continue

        if path in {"SiteForge/Info.plist", "SiteForge/SiteForge.entitlements"}:
            selectors.update(QUICK_SELECTORS)
            continue

        # Build/test orchestration and unknown production inputs can affect every
        # target. Escalating is more efficient than trusting an incomplete map.
        if path == "sf" or path.startswith("scripts/") or path.startswith("Tests/"):
            return None

        # Unknown source/configuration changes also require the complete suite.
        return None

    if not relevant_path_seen or not selectors:
        return QUICK_SELECTORS
    return tuple(sorted(selectors))


def git_lines(root: Path, *arguments: str) -> list[str]:
    result = subprocess.run(
        ("git", *arguments),
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def changed_paths(root: Path, base: str) -> list[str]:
    paths: set[str] = set()
    base_exists = subprocess.run(
        ("git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}"),
        cwd=root,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0

    if base_exists:
        paths.update(
            git_lines(
                root,
                "diff",
                "--name-only",
                "--diff-filter=ACMRTUXB",
                f"{base}...HEAD",
            )
        )
    paths.update(
        git_lines(root, "diff", "--name-only", "--diff-filter=ACMRTUXB")
    )
    paths.update(
        git_lines(
            root,
            "diff",
            "--cached",
            "--name-only",
            "--diff-filter=ACMRTUXB",
        )
    )
    paths.update(git_lines(root, "ls-files", "--others", "--exclude-standard"))
    return sorted(paths)


class SelectionTests(unittest.TestCase):
    def test_document_change_maps_to_dependent_unit_suites(self) -> None:
        self.assertEqual(
            select_for_paths(["SiteForge/DocumentLifecycle.swift"]),
            (
                "SiteForgeTests/DocumentLifecycleRaceTests",
                "SiteForgeTests/DocumentLifecycleTests",
            ),
        )

    def test_ui_source_includes_unit_and_ui_coverage(self) -> None:
        self.assertEqual(
            select_for_paths(["SiteForge/LaunchExperience.swift"]),
            (
                "SiteForgeTests/LaunchExperienceTests",
                "SiteForgeUITests/SiteForgeLaunchTests",
            ),
        )

    def test_changed_test_file_runs_its_test_class(self) -> None:
        self.assertEqual(
            select_for_paths(
                ["Tests/SiteForgeTests/ProjectPackageTests.swift"]
            ),
            ("SiteForgeTests/ProjectPackageTests",),
        )

    def test_docs_only_and_no_change_use_smoke_coverage(self) -> None:
        self.assertEqual(select_for_paths(["docs/CHANGELOG.md"]), QUICK_SELECTORS)
        self.assertEqual(select_for_paths([]), QUICK_SELECTORS)

    def test_unknown_source_or_project_change_escalates_to_full(self) -> None:
        self.assertIsNone(select_for_paths(["SiteForge/FutureFeature.swift"]))
        self.assertIsNone(
            select_for_paths(["SiteForge.xcodeproj/project.pbxproj"])
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SelectionTests)
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        return 0 if result.wasSuccessful() else 1

    selection = select_for_paths(changed_paths(args.root.resolve(), args.base))
    if selection is None:
        print("FULL")
    else:
        print(*selection, sep="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
