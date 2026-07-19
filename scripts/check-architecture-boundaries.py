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
    "SiteForge/PersistedHistory.swift",
]
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


for source in dict.fromkeys(MODEL_SLICE + ENGINE_SLICE):
    forbidden = imports(source) & HEADLESS_FORBIDDEN
    if forbidden:
        fail(f"{source} imports forbidden UI framework(s): {', '.join(sorted(forbidden))}")

typecheck("canonical-model", MODEL_SLICE)
typecheck("command-and-persistence", ENGINE_SLICE)

project = (ROOT / "SiteForge.xcodeproj/project.pbxproj").read_text()
if "WorkspaceSceneComposition.swift in Sources" not in project:
    fail("WorkspaceSceneComposition.swift is not compiled into the application target.")

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

print("Architecture boundary checks passed.")
