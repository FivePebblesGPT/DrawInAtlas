"""Bounded exact sparse-selection overflow and fail-closed CI contracts."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class SparseMaskOverflowContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t141_sparse_mask_overflow_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t141_sparse_mask_overflow_native.gd").read_text()
        cls.fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_index_is_bounded_and_selects_only_true_pixels(self) -> None:
        plan = self.canvas.split("func _mask_outline_tile_candidates(", 1)[1].split("\nfunc ", 1)[0]
        for required in (
            "MAX_MASK_OUTLINE_INDEX_POINTS: int = 8192",
            "selection_mask._pixel_mask.size() <= MAX_MASK_OUTLINE_INDEX_POINTS",
            "not selection_mask._pixel_mask[point]",
            "selection_mask._base_bounds.has_point(point)",
            "footprint.has_point(point)",
            "if candidates.size() > MAX_MASK_OUTLINE_CACHE:",
            "if candidates.size() >= MAX_MASK_OUTLINE_CACHE:",
            "var rings: Dictionary[int, Array] = {}",
            "ring.sort()",
            "maxi(absi(tile.x - focus.x), absi(tile.y - focus.y))",
            "radius_limit",  # The fallback still exists for unknown/oversize masks.
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.canvas if required.startswith("MAX_MASK_OUTLINE_INDEX_POINTS:") else plan)

    def test_red_green_probes_include_real_pixels_and_fallback(self) -> None:
        for statement in (
            "far-but-occupied islands remain eligible",
            "no empty tiles consume the selected-pixel budget",
            "small sparse mask remains exact and row-major",
            "oversized index uses bounded fallback",
        ):
            self.assertIn(statement, self.model)
        for statement in (
            "far occupied island is in bounded outline plan",
            "real framebuffer includes far occupied island outline",
            "selection overlay never publishes raster pixels or history",
            "deselect invalidates cached contours",
        ):
            self.assertIn(statement, self.native)

    def test_workflow_stays_in_46_checks_and_strict_log_policy(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        t088 = self.fast.split("id: ci_t088_selection_clipboard_model", 1)[1].split(
            "- name: Verify T-089", 1
        )[0]
        for clause in (
            "res://tests/t141_sparse_mask_overflow_model.gd",
            "T141_OUTLINE_PASSED checks=12 failures=0",
            "--marker T141_OUTLINE_PASSED",
            "test_t141_sparse_mask_overflow.py",
        ):
            self.assertIn(clause, t088)
        for clause in (
            "res://tests/t141_sparse_mask_overflow_native.gd",
            "T141_NATIVE_PASSED checks=8 failures=0",
            "--marker T141_NATIVE_PASSED",
            "/tmp/t141-outline-native.log",
        ):
            self.assertIn(clause, self.native_ci)

    def test_success_markers_fail_closed(self) -> None:
        for marker, count in (("T141_OUTLINE_PASSED", 12), ("T141_NATIVE_PASSED", 8)):
            ok = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(ok, marker)[0])
            for bad in (ok + ok, ok.replace("failures=0", "failures=1"),
                        ok + "SCRIPT ERROR: outline missing\n"):
                self.assertTrue(verify_log(bad, marker)[0])


if __name__ == "__main__":
    unittest.main()
