"""Fail-closed tests for retained saturated selection contour caches."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class OutlineCacheReuseContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t142_outline_cache_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t142_outline_cache_native.gd").read_text()
        cls.fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.x11 = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_reconcile_only_eligible_contours_and_preserve_budget(self) -> None:
        sync = self.source.split("func _sync_mask_outline_cache(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.source.split("func _draw_selection_outline() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for requirement in (
            "if tile_window != _mask_outline_window:",
            "reconcile = true",
            "candidates.size() >= MAX_MASK_OUTLINE_CACHE",
            "focus != _mask_outline_focus",
            "var eligible: Dictionary[Vector2i, bool] = {}",
            "eligible[tile] = true",
            "for tile: Vector2i in _mask_outline_cache.keys():",
            "if not eligible.has(tile):",
            "_mask_outline_cache.erase(tile)",
            "_mask_outline_focus = focus",
        ):
            with self.subTest(requirement=requirement):
                self.assertIn(requirement, sync)
        self.assertIn("_sync_mask_outline_cache(tile_window, focus, candidates, footprint)", draw)
        self.assertIn("created >= MASK_OUTLINE_TILES_PER_FRAME", draw)
        self.assertIn("MAX_MASK_OUTLINE_CACHE", draw)

    def test_regressions_check_pan_overlap_and_real_pixels(self) -> None:
        for requirement in (
            "all overlapping tiles retain their cached contour data",
            "no stale/out-of-plan tiles retained",
            "changed tile window retains shared eligible contours",
            "mask authorization is not changed by cache planning",
            "overlap",
        ):
            self.assertIn(requirement, self.model)
        for requirement in (
            "retained distant island remains outlined in actual framebuffer after pan",
            "selection pixels or document history",
            "camera pans inside unchanged contour tile window",
            "deselect clears all retained contours",
            "far_pixel_delta",
        ):
            self.assertIn(requirement, self.native)

    def test_ci_preserves_46_required_check_ids(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for needle in (
            "res://tests/t142_outline_cache_model.gd",
            "T142_OUTLINE_PASSED checks=13 failures=0",
            "--marker T142_OUTLINE_PASSED",
            "test_t142_outline_cache_reuse.py",
        ):
            self.assertIn(needle, self.fast)
        for needle in (
            "res://tests/t142_outline_cache_native.gd",
            "T142_NATIVE_PASSED checks=11 failures=0",
            "--marker T142_NATIVE_PASSED",
            "/tmp/t142-outline-native.log",
        ):
            self.assertIn(needle, self.x11)

    def test_strict_markers_reject_corrupted_success(self) -> None:
        for marker, count in (("T142_OUTLINE_PASSED", 13), ("T142_NATIVE_PASSED", 11)):
            with self.subTest(marker=marker):
                good = f"{marker} checks={count} failures=0\n"
                self.assertFalse(verify_log(good, marker)[0])
                for bad in (good + good, good.replace("failures=0", "failures=1"),
                            good + "SCRIPT ERROR: lost outline\n"):
                    self.assertTrue(verify_log(bad, marker)[0])


if __name__ == "__main__":
    unittest.main()
