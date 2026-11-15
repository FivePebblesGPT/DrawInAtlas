"""Fail-closed contracts for saturated selection contour plans after sub-tile pans."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class SubtileClipReconciliation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t143_contour_clip_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t143_contour_clip_native.gd").read_text()
        cls.fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.x11 = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_footprint_changes_reconcile_saturated_cache_without_full_reset(self) -> None:
        sync = self.canvas.split("func _sync_mask_outline_cache(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.canvas.split("func _draw_selection_outline() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for requirement in (
            "clipped_footprint: Rect2i", "clipped_footprint != _mask_outline_footprint",
            "candidates.size() >= MAX_MASK_OUTLINE_CACHE",
            "_mask_outline_cache.size() >= MAX_MASK_OUTLINE_CACHE",
            "focus != _mask_outline_focus", "if tile_window != _mask_outline_window:",
            "if not eligible.has(tile):", "_mask_outline_cache.erase(tile)",
            "_mask_outline_footprint = clipped_footprint",
        ):
            with self.subTest(requirement=requirement):
                self.assertIn(requirement, sync)
        self.assertIn("_sync_mask_outline_cache(tile_window, focus, candidates, footprint)", draw)
        self.assertIn("created >= MASK_OUTLINE_TILES_PER_FRAME", draw)
        self.assertIn("_mask_outline_footprint = Rect2i()", self.canvas)

    def test_model_and_native_verify_real_changed_footprint_not_just_focal_tile(self) -> None:
        for assertion in (
            "old clipped plan saturates cache", "edge islands exchange visibility",
            "only stale edge tile evicted", "all 4095 shared contours remain cached",
            "stable plan reuses the complete cache", "different tile windows retain unchanged shared eligible contours",
        ):
            self.assertIn(assertion, self.model)
        for assertion in (
            "camera remains within the same contour window and focal cell",
            "newly visible edge tile gets traced", "old edge tile evicted to make room",
            "new edge island has a visible outline in the real framebuffer",
            "selection overlay never modifies raster pixels or history",
            "edge_pixel_delta",
        ):
            self.assertIn(assertion, self.native)

    def test_ci_contract_remains_one_of_46_and_native_is_on_demand(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for item in (
            "res://tests/t143_contour_clip_model.gd",
            "T143_MODEL_PASSED checks=14 failures=0",
            "--marker T143_MODEL_PASSED",
            "test_t143_contour_clip_reconcile.py",
        ):
            self.assertIn(item, self.fast)
        for item in (
            "res://tests/t143_contour_clip_native.gd",
            "T143_NATIVE_PASSED checks=10 failures=0",
            "--marker T143_NATIVE_PASSED",
            "/tmp/t143-outline-native.log",
        ):
            self.assertIn(item, self.x11)

    def test_log_verifier_rejects_forged_or_post_success_errors(self) -> None:
        for marker, count in (("T143_MODEL_PASSED", 14), ("T143_NATIVE_PASSED", 10)):
            successful = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(successful, marker)[0])
            for invalid in (
                successful + successful,
                successful.replace("failures=0", "failures=1"),
                successful + "SCRIPT ERROR: silently skipped contour\n",
            ):
                self.assertTrue(verify_log(invalid, marker)[0])


if __name__ == "__main__":
    unittest.main()
