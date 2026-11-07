"""T-081 floating dock canvas-width and fail-closed native-log contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t081_log import verify  # noqa: E402


class FloatingDockNativeContracts(unittest.TestCase):
    def test_code_reserves_stable_expanded_dock_minimum(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.assertIn("const EXPANDED_DOCK_MIN_WIDTH: int = 192", source)
        self.assertIn("inspector.custom_minimum_size.x = EXPANDED_DOCK_MIN_WIDTH", source)
        self.assertIn("48 if minimized else EXPANDED_DOCK_MIN_WIDTH", source)

    def test_native_assertions_cover_float_hide_and_recovery(self) -> None:
        native = (ROOT / "drawing/tests/dock_float_native.gd").read_text()
        for value in ("expanded dock reserves compact panel width",
                      "removing Colors cannot shrink expanded dock minimum width",
                      "floating overlay leaves split canvas width unchanged",
                      "hiding the floated overlay cannot resize the canvas",
                      "showing a hidden floated overlay cannot resize the canvas",
                      "1.5x content scale preserves host bounds"):
            with self.subTest(value=value):
                self.assertIn(value, native)

    def test_on_demand_workflow_runs_real_imported_pointer_checks(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-native-t081-floating.yml").read_text()
        for value in ("workflow_dispatch", "setup-godot@v2", "--import --quit",
                      "xvfb-run", "--audio-driver Dummy", "dock_float_native.gd",
                      "check_native_t081_log.py", "T081_SCREENSHOTS", "upload-artifact@v4"):
            with self.subTest(value=value):
                self.assertIn(value, workflow)

    def test_accepts_complete_native_evidence_and_only_known_teardown(self) -> None:
        valid = "T081_FLOAT_NATIVE: 58 checks; 0 failed\nT081_FLOAT_NATIVE_PASSED"
        self.assertEqual(verify(valid), (True, [], 0))
        self.assertEqual(verify(valid + "\nERROR: Texture with GL ID of 7: leaked 1024 bytes."),
                         (True, [], 1))

    def test_rejects_stale_runtime_failure_or_spoofed_log(self) -> None:
        valid = "T081_FLOAT_NATIVE: 58 checks; 0 failed\nT081_FLOAT_NATIVE_PASSED"
        for content in (
            "", "T081_FLOAT_NATIVE: 54 checks; 0 failed\nT081_FLOAT_NATIVE_PASSED",
            "T081_FLOAT_NATIVE: 58 checks; 1 failed\nT081_FLOAT_NATIVE_PASSED",
            valid + "\nT081_FLOAT_NATIVE_PASSED",
            "T081_FLOAT_NATIVE_PASSED\nT081_FLOAT_NATIVE: 58 checks; 0 failed",
            valid + "\nT081_NATIVE_FAILED: host resized canvas",
            valid + "\nSCRIPT ERROR: stale host pointer",
            valid + "\nParse Error: failed source import",
            valid + "\nERROR: unexpected renderer error",
            "ERROR: Texture with GL ID of 7: leaked 1024 bytes.\n" + valid,
        ):
            with self.subTest(content=content):
                self.assertFalse(verify(content)[0])


if __name__ == "__main__":
    unittest.main()
