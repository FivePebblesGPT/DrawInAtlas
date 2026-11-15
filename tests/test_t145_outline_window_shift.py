"""Regression contracts for contour continuity across visible tile-window pans."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class ContourWindowContinuityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t145_outline_window_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t145_outline_window_native.gd").read_text()
        cls.fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.x11 = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_shift_reconciles_only_ineligible_contours(self) -> None:
        sync = self.source.split("func _sync_mask_outline_cache(", 1)[1].split("\nfunc ", 1)[0]
        for required in (
            "if tile_window != _mask_outline_window:",
            "reconcile = true",
            "if reconcile and not _mask_outline_cache.is_empty():",
            "for tile: Vector2i in candidates:",
            "if not eligible.has(tile):",
            "_mask_outline_cache.erase(tile)",
            "_mask_outline_window = tile_window",
            "_mask_outline_footprint = clipped_footprint",
        ):
            with self.subTest(required=required):
                self.assertIn(required, sync)
        self.assertNotIn("_mask_outline_cache.clear()", sync)
        self.assertIn("created >= MASK_OUTLINE_TILES_PER_FRAME", self.source)
        self.assertIn("MAX_MASK_OUTLINE_CACHE: int = 4096", self.source)

    def test_real_window_shift_and_source_invalidation_are_exercised(self) -> None:
        for expected in (
            "window translation evicts only contours no longer eligible",
            "target cached edges survive translation without recompositing",
            "in-place public mask change invalidates cached contours",
            "selection replacement invalidates all old contours",
            "no obsolete cached contour lies outside new plan",
        ):
            self.assertIn(expected, self.model)
        for expected in (
            "panning moved visible contour tile window",
            "shared distant island remains cached after actual window translation",
            "far island remains visibly outlined in the actual framebuffer",
            "outline-cache continuity never changes document pixels or history",
            "framebuffer_delta",
        ):
            self.assertIn(expected, self.native)

    def test_fast_and_native_ci_remain_fail_closed_without_new_job(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for item in (
            "res://tests/t145_outline_window_model.gd",
            "T145_MODEL_PASSED checks=14 failures=0",
            "--marker T145_MODEL_PASSED",
            "test_t145_outline_window_shift.py",
        ):
            self.assertIn(item, self.fast)
        for item in (
            "res://tests/t145_outline_window_native.gd",
            "T145_NATIVE_PASSED checks=10 failures=0",
            "--marker T145_NATIVE_PASSED",
            "/tmp/t145-outline-native.log",
        ):
            self.assertIn(item, self.x11)

    def test_log_verifier_rejects_forged_or_post_success_failures(self) -> None:
        for marker, count in (("T145_MODEL_PASSED", 14), ("T145_NATIVE_PASSED", 10)):
            success = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(success, marker)[0])
            for forged in (success + success, success.replace("failures=0", "failures=1"),
                           success + "SCRIPT ERROR: stale contour tile\n"):
                self.assertTrue(verify_log(forged, marker)[0])


if __name__ == "__main__":
    unittest.main()
