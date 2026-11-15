"""Fail-closed regression contracts for bounded focal-first outline overflow."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class FocalSelectionOutlineContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t140_focal_mask_overflow_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t140_focal_mask_overflow_native.gd").read_text()
        cls.fast_ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_bounded_focal_fallback_and_stale_cache_rejection(self) -> None:
        focal = self.canvas.split("func _mask_outline_focal_cell(", 1)[1].split("\nfunc ", 1)[0]
        candidates = self.canvas.split("func _mask_outline_tile_candidates(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.canvas.split("func _draw_selection_outline() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for clause in (
            "clampi(", "floori(camera.x)", "floori(camera.y)",
        ):
            with self.subTest(clause=clause):
                self.assertIn(clause, focal)
        for clause in (
            "selection_mask._pixel_mask.size() <= MAX_MASK_OUTLINE_INDEX_POINTS", "_mask_outline_focal_cell(",
            "radius_limit", "maxi(left, focus.x - radius)",
            "mini(bottom, focus.y + radius)",
            "candidates.size() >= MAX_MASK_OUTLINE_CACHE",
        ):
            with self.subTest(clause=clause):
                self.assertIn(clause, candidates)
        self.assertIn("var candidates: Array[Vector2i] = _mask_outline_tile_candidates(footprint)", draw)
        self.assertIn("focus != _mask_outline_focus", draw)
        self.assertIn("_mask_outline_cache.clear()", draw)
        self.assertIn("MASK_OUTLINE_TILES_PER_FRAME", draw)
        self.assertIn("selection_mask.contour_segments(", draw)

    def test_negative_controls_cover_real_frames_and_overflow(self) -> None:
        for clause in (
            "first fallback tile is the camera focal cell",
            "camera move prioritizes actual selected tiles when the focal cell is empty",
            "outside camera prioritizes the nearest occupied tile in the footprint",
            "very tall narrow footprint still bounded",
            "small sparse mask still indexes only actual occupied tiles",
            "inverted fallback prioritizes the camera",
        ):
            self.assertIn(clause, self.model)
        for clause in (
            "focal selection outline changes the actual framebuffer",
            "panning inside the selection keeps the same outline tile window",
            "focal change evicts an old full cache",
            "overlay does not change canonical raster or history",
            "MAX_MASK_OUTLINE_CACHE",
        ):
            self.assertIn(clause, self.native)

    def test_existing_46_check_inventory_and_strict_ci(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast_ci, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        t088 = self.fast_ci.split("id: ci_t088_selection_clipboard_model", 1)[1].split(
            "- name: Verify T-089", 1
        )[0]
        for clause in (
            "res://tests/t140_focal_mask_overflow_model.gd",
            "T140_OUTLINE_PASSED checks=17 failures=0",
            "--marker T140_OUTLINE_PASSED",
            "test_t140_focal_selection_outline.py",
        ):
            self.assertIn(clause, t088)
        for clause in (
            "res://tests/t140_focal_mask_overflow_native.gd",
            "T140_NATIVE_PASSED checks=9 failures=0",
            "--marker T140_NATIVE_PASSED",
            "/tmp/t140-outline-native.log",
        ):
            self.assertIn(clause, self.native_ci)
        for marker, count in (("T140_OUTLINE_PASSED", 17), ("T140_NATIVE_PASSED", 9)):
            valid = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(valid, marker)[0])
            for invalid in (
                valid + valid,
                valid.replace("failures=0", "failures=1"),
                valid + "SCRIPT ERROR: stale contour cache\n",
            ):
                self.assertTrue(verify_log(invalid, marker)[0])


if __name__ == "__main__":
    unittest.main()
