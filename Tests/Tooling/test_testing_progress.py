"""Compile real monitor code with native behavior and timing fixtures."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "darwin", "Native AppKit monitor")
class TestingProgressTests(unittest.TestCase):
    def test_native_monitor_controls_and_timing(self):
        if Path("/dev/console").stat().st_uid != os.getuid():
            self.skipTest("Offscreen AppKit controls require a local console session")
        root = Path(__file__).resolve().parents[2]
        source = (root / "scripts/full-verification-progress.swift").read_text()
        marker = "let arguments = CommandLine.arguments"
        self.assertIn(marker, source)
        fixtures = (root / "Tests/Tooling/TestingProgressFixtures.swift").read_text()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "main.swift").write_text(source.split(marker)[0] + "\n" + fixtures)
            compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", str(path / "main.swift"),
                                       "-o", str(path / "fixtures")], capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(path / "fixtures")], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Passed 9 monitor state and timing fixtures", result.stdout)
            self.assertIn("frozen elapsed time assertions", result.stdout)
            self.assertIn("terminal result assertions", result.stdout)


if __name__ == "__main__":
    unittest.main()
