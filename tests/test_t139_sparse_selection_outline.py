"""Fail-closed T-139 selection outline source, witness and CI contracts."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class SparseSelectionOutlineContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.fast_ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()
        cls.model = (ROOT / "drawing/tests/t139_sparse_selection_outline_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t139_sparse_selection_outline_native.gd").read_text()

    def test_source_limits_sparse_tiles_without_mutating_selection(self) -> None:
        helper = self.canvas.split("func _mask_outline_tile_candidates(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.canvas.split("func _draw_selection_outline() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for clause in (
            "selection_mask._pixel_mask",
            "not selection_mask.inverted",
            "selection_mask._operations.is_empty()",
            "selection_mask._base_bounds.has_point(point)",
            "footprint.has_point(point)",
            "DrawingDocument.TILES.floor_div(point.x, MASK_OUTLINE_TILE)",
            "DrawingDocument.TILES.floor_div(point.y, MASK_OUTLINE_TILE)",
            "if candidates.size() > MAX_MASK_OUTLINE_CACHE:",
            "candidates.sort_custom",
            "candidates.size() >= MAX_MASK_OUTLINE_CACHE",
        ):
            with self.subTest(clause=clause):
                self.assertIn(clause, helper)
        self.assertIn("_mask_outline_tile_candidates(footprint)", draw)
        self.assertIn("MASK_OUTLINE_TILES_PER_FRAME", draw)
        self.assertIn("selection_mask.contour_segments(", draw)
        # T-142 moves window/focus invalidation into a shared reconciliation
        # helper; it still clears on a changed window, but preserves overlap
        # across an in-window saturated focus change.
        sync = self.canvas.split("func _sync_mask_outline_cache(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_sync_mask_outline_cache(tile_window, focus, candidates)", draw)
        self.assertIn("_mask_outline_cache.clear()", sync)
        self.assertNotIn("_pixel_mask.clear()", helper)

    def test_oracles_cover_signed_mask_fallback_and_real_framebuffer(self) -> None:
        for clause in (
            "sparse explicit mask visits only two occupied outline tiles",
            "far positive selected island is not dropped",
            "false mask entries do not create contour tiles",
            "inverted explicit masks keep the bounded conservative scan",
            "compound explicit masks keep the bounded conservative scan",
            "over-capacity explicit indexes keep bounded tile allocation",
        ):
            self.assertIn(clause, self.model)
        for clause in (
            "changed_pixels(picked, cleared, a)",
            "changed_pixels(picked, cleared, b)",
            "far positive pixel changes actual framebuffer outline",
            "selection overlay does not publish raster content",
            "selection re-entry rebuilds only occupied contour tiles",
        ):
            self.assertIn(clause, self.native)

    def test_ci_retains_46_ids_and_strict_log_checks(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast_ci, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        t088 = self.fast_ci.split("id: ci_t088_selection_clipboard_model", 1)[1].split(
            "- name: Verify T-089", 1
        )[0]
        for clause in (
            "res://tests/t139_sparse_selection_outline_model.gd",
            "T139_OUTLINE_PASSED checks=14 failures=0",
            "--marker T139_OUTLINE_PASSED",
            "test_t139_sparse_selection_outline.py",
        ):
            self.assertIn(clause, t088)
        for clause in (
            "res://tests/t139_sparse_selection_outline_native.gd",
            "T139_NATIVE_PASSED checks=7 failures=0",
            "--marker T139_NATIVE_PASSED",
            "/tmp/t139-outline-native.log",
        ):
            self.assertIn(clause, self.native_ci)
        for marker, count in (("T139_OUTLINE_PASSED", 14), ("T139_NATIVE_PASSED", 7)):
            valid = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(valid, marker)[0])
            for invalid in (
                valid + valid,
                valid.replace("failures=0", "failures=1"),
                valid + "SCRIPT ERROR: stale mask\n",
            ):
                self.assertTrue(verify_log(invalid, marker)[0])


if __name__ == "__main__":
    unittest.main()
