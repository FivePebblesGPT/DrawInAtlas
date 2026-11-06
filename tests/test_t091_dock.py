"""T-091 CI and native-log acceptance contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t091_log import verify  # noqa: E402


class T091DockTests(unittest.TestCase):
    def test_model_is_required_in_fast_ci(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        self.assertIn("dock_single_group_smoke.gd", workflow)
        self.assertIn("T091_MODEL_PASSED", workflow)
        self.assertIn("continue-on-error: true", workflow)

    def test_native_workflow_imports_before_x11_and_uploads_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-native-t091-docking.yml").read_text()
        for required in ("workflow_dispatch", "--import --quit", "xvfb-run",
                         "dock_single_group_native.gd", "T091_SCREENSHOTS",
                         "check_native_t091_log.py", "upload-artifact@v4"):
            with self.subTest(required=required):
                self.assertIn(required, workflow)

    def test_log_recognizes_only_post_success_known_leaks(self) -> None:
        base = "T091_NATIVE: 36 checks; 0 failed\nT091_NATIVE_PASSED"
        expected = base + "\nERROR: Texture with GL ID of 18: leaked 32 bytes."
        self.assertEqual(verify(expected), (True, [], 1))
        for invalid in (
            base + "\nT091_NATIVE_FAILED: group lost",
            base + "\nSCRIPT ERROR: stack overflow",
            base + "\nERROR: compositor crashed",
            "ERROR: Texture with GL ID of 18: leaked 32 bytes.\n" + base,
            "T091_NATIVE: 35 checks; 0 failed\nT091_NATIVE_PASSED",
            "T091_NATIVE: 36 checks; 1 failed\nT091_NATIVE_PASSED",
            "T091_NATIVE_PASSED\nT091_NATIVE: 36 checks; 0 failed",
            base + "\nT091_NATIVE_PASSED", ""):
            with self.subTest(invalid=invalid):
                self.assertFalse(verify(invalid)[0])


if __name__ == "__main__":
    unittest.main()
