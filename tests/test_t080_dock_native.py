"""T-080 native pointer regression and fail-closed CI evidence contracts."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t080_log import verify  # noqa: E402


class T080DockNativeTests(unittest.TestCase):
    def test_on_demand_workflow_runs_imported_x11_pointer_witness(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-native-t080-reorder.yml").read_text()
        for value in ("workflow_dispatch", "setup-godot@v2", "--import --quit",
                      "xvfb-run", "--audio-driver Dummy", "dock_reorder_native.gd",
                      "check_native_t080_log.py", "T080_SCREENSHOTS", "upload-artifact@v4"):
            with self.subTest(value=value):
                self.assertIn(value, workflow)

    def test_native_witness_covers_invalid_target_and_clipped_bottom(self) -> None:
        source = (ROOT / "drawing/tests/dock_reorder_native.gd").read_text()
        for value in ("Vector2(-24.0, -24.0)", "floating_hosts.size()",
                      "before scrolling to the bottom", "after-last-group insertion hint",
                      "invalid drop is exact no-op", "Ctrl+Alt+S keyboard split"):
            with self.subTest(value=value):
                self.assertIn(value, source)

    def test_complete_log_and_known_shutdown_leak(self) -> None:
        base = "T080_DOCK_REORDER_NATIVE: 70 checks; 0 failed\nT080_DOCK_REORDER_NATIVE_PASSED"
        self.assertEqual(verify(base), (True, [], 0))
        self.assertEqual(verify(base + "\nERROR: Texture with GL ID of 77: leaked 2048 bytes."),
                         (True, [], 1))

    def test_rejects_incomplete_error_or_corrupt_log(self) -> None:
        base = "T080_DOCK_REORDER_NATIVE: 70 checks; 0 failed\nT080_DOCK_REORDER_NATIVE_PASSED"
        for invalid in (
            "", base + "\nT080_DOCK_REORDER_NATIVE_PASSED",
            "T080_DOCK_REORDER_NATIVE: 69 checks; 0 failed\nT080_DOCK_REORDER_NATIVE_PASSED",
            "T080_DOCK_REORDER_NATIVE: 70 checks; 1 failed\nT080_DOCK_REORDER_NATIVE_PASSED",
            "T080_DOCK_REORDER_NATIVE_PASSED\nT080_DOCK_REORDER_NATIVE: 70 checks; 0 failed",
            base + "\nSCRIPT ERROR: stale Control reference",
            base + "\nT080_NATIVE_FAILED: invalid host drop",
            base + "\nERROR: Unrecognized UI failure",
            "ERROR: Texture with GL ID of 77: leaked 2048 bytes.\n" + base,
        ):
            with self.subTest(invalid=invalid):
                self.assertFalse(verify(invalid)[0])


if __name__ == "__main__":
    unittest.main()
