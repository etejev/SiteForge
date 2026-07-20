#!/usr/bin/env python3
"""Behavioral seeded checks for the redacting repository scanner."""

from pathlib import Path
from contextlib import contextmanager
import importlib.util
import os
import shutil
import sys
import tempfile
from typing import Optional

ROOT = Path(__file__).resolve().parents[1]
module_path = ROOT / "scripts/scan-repository-secrets.py"
spec = importlib.util.spec_from_file_location("siteforge_secret_scanner", module_path)
assert spec and spec.loader
scanner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = scanner
spec.loader.exec_module(scanner)

def joined(*parts: str) -> str:
    return "".join(parts)


def synthetic_examples() -> list[str]:
    """Build scanner-only examples without storing credential-shaped values."""
    return [
        joined("-----BEGIN ", "PRIVATE ", "KEY-----"),
        joined("gh", "p_", "A" * 24),
        joined("github_", "pat_", "A_" * 18),
        joined("AK", "IA", "B" * 16),
        joined("AI", "za", "C" * 32),
        joined("xo", "xb-", "D" * 24),
        joined("s", "k_", "live_", "E" * 24),
        joined("client_", "secret", " = ", "F" * 20),
    ]


@contextmanager
def owned_synthetic_fixture():
    directory = Path(tempfile.mkdtemp(prefix="siteforge-secret-scanner-"))
    os.chmod(directory, 0o700)
    metadata = directory.stat()
    if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        shutil.rmtree(directory)
        raise RuntimeError("Synthetic secret fixture directory is not private")
    fixture = directory / "runtime-positive.txt"
    try:
        descriptor = os.open(fixture, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write("\n".join(synthetic_examples()))
            stream.write("\n")
        yield fixture
    finally:
        shutil.rmtree(directory)


def prove_cleanup(exception: Optional[BaseException]) -> None:
    directory: Optional[Path] = None
    try:
        with owned_synthetic_fixture() as fixture:
            directory = fixture.parent
            if exception is not None:
                raise exception
    except (RuntimeError, KeyboardInterrupt):
        if exception is None:
            raise
    if directory is None or directory.exists():
        raise SystemExit("Synthetic secret fixture cleanup failed")


with owned_synthetic_fixture() as positive_path:
    positive = scanner.scan_file(positive_path, Path("runtime-positive.txt"))
categories = {finding.category for finding in positive}
expected = {
    "private-key", "github-token", "aws-access-key", "google-api-key", "slack-token",
    "stripe-live-key", "generic-secret-assignment",
}
missing = expected - categories
if missing:
    raise SystemExit(f"Secret scanner missed seeded categories: {', '.join(sorted(missing))}")
for sensitive_name in [Path(".env"), Path("credentials.json"), Path("certificate.p12"), Path("id_ed25519")]:
    with owned_synthetic_fixture() as positive_path:
        named_findings = scanner.scan_file(positive_path, sensitive_name)
    if not any(finding.category == "sensitive-file" for finding in named_findings):
        raise SystemExit(f"Secret scanner missed sensitive filename policy: {sensitive_name}")

prove_cleanup(None)
prove_cleanup(RuntimeError("synthetic failure"))
prove_cleanup(KeyboardInterrupt())

negative_relative = Path("Tests/Fixtures/SecretScanner/negative.txt")
negative = scanner.scan_file(ROOT / negative_relative, negative_relative)
if negative:
    raise SystemExit("Secret scanner falsely classified the seeded negative fixture")
binary_negative = scanner.scan_file(ROOT / negative_relative, Path("representative.png"))
if binary_negative:
    raise SystemExit("Secret scanner falsely parsed an excluded representative binary")

repository_findings = scanner.scan(ROOT)
if repository_findings:
    raise SystemExit("Secret scanner found repository content; run scan-repository-secrets.py for redacted locations")
print(
    f"Secret scanner tests passed ({len(positive)} seeded pattern detections, "
    "4 sensitive-name policies, runtime fixture cleanup, 0 negative-fixture findings)."
)
