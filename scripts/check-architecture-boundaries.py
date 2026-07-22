#!/usr/bin/env python3
"""Enforce the Milestone 0 headless dependency and scene-ownership boundaries."""

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MODEL_SLICE = ["SiteForge/DocumentModel.swift"]
ENGINE_SLICE = [
    "SiteForge/DocumentModel.swift",
    "SiteForge/CommandKernel.swift",
    "SiteForge/IdentityBoundFileSystem.swift",
    "SiteForge/ProjectPackage.swift",
    "SiteForge/ProjectResources.swift",
    "SiteForge/PersistedHistory.swift",
]
RUNWAY_HEADLESS_SLICE = [
    "Benchmarks/AuthoringEngineRunway/RunwayCore.swift",
    "Benchmarks/AuthoringEngineRunway/RunwayHTMLExport.swift",
]
CANVAS_VIEWPORT_SLICE = [
    "SiteForge/DocumentModel.swift",
    "SiteForge/CanvasViewport.swift",
]
LAYOUT_ENGINE_SLICE = [
    "SiteForge/DocumentModel.swift",
    "SiteForge/LayoutEngine.swift",
]
CANVAS_RENDERER_SLICE = [
    "SiteForge/DocumentModel.swift",
    "SiteForge/CanvasViewport.swift",
    "SiteForge/CanvasRendererCore.swift",
]
SELECTION_MODEL_SLICE = [
    "SiteForge/DocumentModel.swift",
    "SiteForge/CanvasViewport.swift",
    "SiteForge/CanvasRendererCore.swift",
    "SiteForge/SelectionModel.swift",
]
INSERTION_MODEL_SLICE = list(dict.fromkeys(ENGINE_SLICE + [
    "SiteForge/CanvasViewport.swift",
    "SiteForge/LayoutEngine.swift",
    "SiteForge/InsertionModel.swift",
]))
HEADLESS_FORBIDDEN = {"SwiftUI", "AppKit", "Metal", "WebKit"}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def imports(path: str) -> set[str]:
    text = (ROOT / path).read_text()
    return set(re.findall(r"^import\s+(\w+)", text, re.MULTILINE))


def typecheck(name: str, sources: list[str]) -> None:
    command = ["xcrun", "swiftc", "-typecheck", "-swift-version", "6", *sources]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        fail(f"Headless {name} slice failed to type-check:\n{result.stdout}{result.stderr}")


for source in dict.fromkeys(
    MODEL_SLICE + ENGINE_SLICE + RUNWAY_HEADLESS_SLICE + CANVAS_VIEWPORT_SLICE + LAYOUT_ENGINE_SLICE + CANVAS_RENDERER_SLICE + SELECTION_MODEL_SLICE + INSERTION_MODEL_SLICE
):
    forbidden = imports(source) & HEADLESS_FORBIDDEN
    if forbidden:
        fail(f"{source} imports forbidden UI framework(s): {', '.join(sorted(forbidden))}")

typecheck("canonical-model", MODEL_SLICE)
typecheck("command-and-persistence", ENGINE_SLICE)
typecheck("authoring-runway", RUNWAY_HEADLESS_SLICE)
typecheck("canvas-viewport", CANVAS_VIEWPORT_SLICE)
typecheck("deterministic-layout", LAYOUT_ENGINE_SLICE)
typecheck("canvas-renderer-contract", CANVAS_RENDERER_SLICE)
typecheck("selection-model-contract", SELECTION_MODEL_SLICE)
typecheck("insertion-model-contract", INSERTION_MODEL_SLICE)

project = (ROOT / "SiteForge.xcodeproj/project.pbxproj").read_text()
if "WorkspaceSceneComposition.swift in Sources" not in project:
    fail("WorkspaceSceneComposition.swift is not compiled into the application target.")
if "CanvasViewport.swift in Sources" not in project:
    fail("The headless canvas viewport is not compiled into the application target.")
if "LayoutEngine.swift in Sources" not in project:
    fail("The headless deterministic layout engine is not compiled into the application target.")
if "CanvasRendererCore.swift in Sources" not in project:
    fail("The headless canvas renderer contract is not compiled into the application target.")
if "SelectionModel.swift in Sources" not in project or "SelectionModelTests.swift in Sources" not in project:
    fail("The headless selection model and its behavioral tests must be compiled into their targets.")
if "InsertionModel.swift in Sources" not in project or "InsertionModelTests.swift in Sources" not in project:
    fail("The headless insertion model and its behavioral tests must be compiled into their targets.")

selection_source = (ROOT / "SiteForge/SelectionModel.swift").read_text()
if re.search(r"(?:struct|class)\s+SelectionState\s*:\s*[^\n]*(?:Codable|Encodable|Decodable)", selection_source):
    fail("Selection convenience state must not become canonical serialized project content.")
insertion_source = (ROOT / "SiteForge/InsertionModel.swift").read_text()
if re.search(r"(?:struct|class)\s+InsertionSession\s*:\s*[^\n]*(?:Codable|Encodable|Decodable)", insertion_source):
    fail("Insertion preview/session state must not become canonical serialized project content.")
app_sources = re.search(
    r"600000000000000000000001 /\* Sources \*/ = .*?files = \((.*?)\);",
    project,
    re.DOTALL,
)
if not app_sources:
    fail("The application Sources phase could not be resolved.")
for prototype in ["RunwayCore.swift", "RunwayHTMLExport.swift", "RunwayCanvasBenchmarks.swift", "RunwayBrowserOracle.swift"]:
    if prototype in app_sources.group(1):
        fail(f"Prototype source leaked into the production application target: {prototype}")
for prototype in ["RunwayCore.swift in Sources", "RunwayHTMLExport.swift in Sources"]:
    if prototype not in project:
        fail(f"Headless runway source is not compiled into the unit-test target: {prototype}")

app = (ROOT / "SiteForge/SiteForgeApp.swift").read_text()
if "@StateObject" in app or "WorkspaceSceneRoot(composition:" not in app:
    fail("The App root must delegate document ownership to each WindowGroup scene.")

composition = (ROOT / "SiteForge/WorkspaceSceneComposition.swift").read_text()
required_markers = [
    "final class WorkspaceDocumentContext",
    "let shellState: WorkspaceShellState",
    "let launchExperience: LaunchExperienceController",
    "#if DEBUG",
    "arguments: [], enabled: false",
]
for marker in required_markers:
    if marker not in composition:
        fail(f"Scene composition boundary is missing required marker: {marker}")

for source in (ROOT / "SiteForge").glob("*.swift"):
    if source.name == "WorkspaceSceneComposition.swift":
        continue
    text = source.read_text()
    if "ProcessInfo.processInfo.arguments" in text:
        fail(f"{source.relative_to(ROOT)} bypasses the centralized Debug composition seam.")

open_panel_owners = []
for source in (ROOT / "SiteForge").glob("*.swift"):
    if "NSOpenPanel()" in source.read_text():
        open_panel_owners.append(source.relative_to(ROOT).as_posix())
if open_panel_owners != ["SiteForge/LaunchExperience.swift"]:
    fail(f"Native Open panel ownership must remain singular: {open_panel_owners}")

fixture_root_owners = []
for source in (ROOT / "Tests").rglob("*.swift"):
    if ".siteforge-test-fixtures" in source.read_text():
        fixture_root_owners.append(source.relative_to(ROOT).as_posix())
if fixture_root_owners != ["Tests/Support/RepositoryTestFixtures.swift"]:
    fail(f"Test fixture-root construction must remain centralized: {fixture_root_owners}")
if "RepositoryTestFixtures.swift in Sources" not in project:
    fail("The shared repository fixture allocator is not compiled into test targets.")
sf_script = (ROOT / "sf").read_text()
if "trap cleanup_test_fixtures EXIT" not in sf_script or sf_script.count("cleanup_test_fixtures") < 4:
    fail("Test fixture cleanup must run on success, failure, and interruption.")

print("Architecture boundary checks passed.")
