"""T-068: isolated GDExtension runner contracts; no Godot/native UI in push CI."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/benchmarks/t068_bridge/run_bridge.py"
SPEC = importlib.util.spec_from_file_location("t068_bridge_runner", SOURCE)
assert SPEC is not None and SPEC.loader is not None
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class IsolatedBridgeRunnerContracts(unittest.TestCase):
    def test_references_only_test_assets_and_existing_checked_kernel(self) -> None:
        self.assertEqual(bridge.ROOT, ROOT)
        self.assertTrue((bridge.BRIDGE / "t068_bridge.cpp").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_bridge_smoke.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_revision_adapter.gd").is_file())
        self.assertTrue((bridge.BRIDGE / "t068_revision_smoke.gd").is_file())
        self.assertTrue((ROOT / "tools/benchmarks/t068_raster_kernel.cpp").is_file())
        self.assertFalse(list(ROOT.rglob("*.gdextension")),
                         "The experimental native extension must not load at app startup")

    def test_correctness_marker_and_multiple_runs(self) -> None:
        expected = "T068_BRIDGE_PASSED: 443 checks\n"
        self.assertEqual(bridge.PASS_RE.search(expected).group(1), "443")
        self.assertIsNone(bridge.PASS_RE.search("T068_BRIDGE_FAILED: 1/443"))
        self.assertEqual(bridge.REVISION_RE.search(
            "T068_REVISION_PASSED: 370 checks\n").group(1), "370")
        self.assertIsNone(bridge.REVISION_RE.search("T068_REVISION_FAILED: 1/370"))
        self.assertIsNotNone(bridge.TIMING_RE.search(
            'T068_BRIDGE_TIMING: {"32":{"median_us":8}}\n'))

    def test_nonzero_exit_and_godot_errors_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wd = Path(tmp)
            self.assertIn("ready", bridge.checked_run(
                [sys.executable, "-c", "print('ready')"], cwd=wd, timeout=10))
            with self.assertRaises(RuntimeError):
                bridge.checked_run([sys.executable, "-c", "raise SystemExit(3)"],
                                   cwd=wd, timeout=10)
            for diagnostic in ("SCRIPT ERROR: parse failed", "ERROR: invalid extension",
                               "T068_BRIDGE_FAIL: mismatched bytes",
                               "T068_REVISION_FAIL: stale write accepted",
                               "T068_REVISION_FAILED: 1/370"):
                with self.subTest(diagnostic=diagnostic), self.assertRaises(RuntimeError):
                    bridge.checked_run([sys.executable, "-c",
                                        f"print({diagnostic!r})"], cwd=wd, timeout=10)

    def test_generated_header_and_compiler_called_without_mutating_main_project(self) -> None:
        original = SOURCE.read_text(encoding="utf-8")
        self.assertIn("--dump-gdextension-interface", original)
        self.assertIn("with tempfile.TemporaryDirectory", original)
        self.assertIn("str(ROOT / \"tools/benchmarks/t068_raster_kernel.cpp\")", original)
        self.assertIn('"--script", "res://test.gd"', original)
        self.assertNotIn('ROOT / "project.godot").write_text(', original)
        self.assertNotIn('ROOT / "addons"', original)

    def test_revision_checks_require_native_renderer_and_isolation(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn('shutil.which("xvfb-run")', source)
        self.assertIn('"--audio-driver", "Dummy"', source)
        self.assertIn('"res://revision_test.gd"', source)
        self.assertIn('"revision_checks": int(revision_match.group(1))', source)
        self.assertIn("T068_REVISION_PASSED", source)
        self.assertNotIn('ROOT / "scripts"', source)
        adapter = (bridge.BRIDGE / "t068_revision_adapter.gd").read_text(encoding="utf-8")
        self.assertIn('expected_revision != revision or original != _pixels', adapter)
        self.assertIn('texture.update(_image())', adapter)
        self.assertIn('"dirty_rect": Rect2i(', adapter)



if __name__ == "__main__":
    unittest.main()
