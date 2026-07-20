#!/usr/bin/env python3
"""Redacting repository credential and sensitive-artifact scanner."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRECTORIES = {".git", ".build", "DerivedData", "xcuserdata", ".siteforge-test-fixtures"}
SKIP_SUFFIXES = {".xcresult", ".app", ".xctest", ".dSYM"}
BINARY_SUFFIXES = {".docx", ".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".dmg"}


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    category: str


PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
    "github-token": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})"),
    "aws-access-key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "google-api-key": re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    "slack-token": re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{20,}\b"),
    "stripe-live-key": re.compile(r"\b(?:sk|rk)_live_[0-9A-Za-z]{16,}\b"),
    "generic-secret-assignment": re.compile(
        r"(?i)\b(?:api[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd)\b"
        r"\s*[:=]\s*[\"']?(?!\$\{|<|example\b|fake\b|redacted\b|placeholder\b|none\b|null\b)"
        r"[A-Za-z0-9+/_.=-]{12,}"
    ),
}

SENSITIVE_NAMES = {
    ".env", "id_rsa", "id_ed25519", "credentials.json", "service-account.json",
}
SENSITIVE_SUFFIXES = {".p12", ".pfx", ".key", ".pem", ".mobileprovision", ".provisionprofile"}


def iter_files(root: Path):
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part in SKIP_DIRECTORIES or any(part.endswith(suffix) for suffix in SKIP_SUFFIXES)
               for part in relative.parts):
            continue
        if path.is_file():
            yield path, relative


def scan_file(path: Path, relative: Path) -> list[Finding]:
    findings: list[Finding] = []
    lower_name = relative.name.lower()
    if (lower_name in SENSITIVE_NAMES or
            (lower_name.startswith(".env.") and lower_name != ".env.example") or
            relative.suffix.lower() in SENSITIVE_SUFFIXES):
        findings.append(Finding(relative, 1, "sensitive-file"))
    if relative.suffix.lower() in BINARY_SUFFIXES:
        return findings
    try:
        data = path.read_bytes()
    except OSError:
        return findings + [Finding(relative, 1, "unreadable-file")]
    if b"\x00" in data[:8192]:
        return findings
    text = data.decode("utf-8", errors="replace")
    for line_number, line in enumerate(text.splitlines(), 1):
        for category, pattern in PATTERNS.items():
            if pattern.search(line):
                findings.append(Finding(relative, line_number, category))
    return findings


def scan(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path, relative in iter_files(root):
        findings.extend(scan_file(path, relative))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path, default=ROOT)
    parser.add_argument("--fixture", type=Path, help="scan one seeded fixture without exclusions")
    args = parser.parse_args()
    if args.fixture:
        fixture = args.fixture if args.fixture.is_absolute() else ROOT / args.fixture
        findings = scan_file(fixture, fixture.relative_to(ROOT))
    else:
        findings = scan(args.root.resolve())
    for finding in findings:
        print(f"{finding.path}:{finding.line}: potential {finding.category}", file=sys.stderr)
    if findings:
        print(f"Repository security scan found {len(findings)} redacted finding(s).", file=sys.stderr)
        return 1
    print("Repository security scan passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
