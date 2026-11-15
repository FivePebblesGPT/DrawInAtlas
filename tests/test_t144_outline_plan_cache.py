"""Fail-closed exact selection-outline planning reuse and native CI contracts."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class OutlinePlanCacheContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.selection = (ROOT / "addons/drawing/selection.gd").read_text()
        cls.model = (ROOT / "drawing/tests/t144_outline_plan_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t144_outline_plan_native.gd").read_text()
        cls.fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.x11 = (ROOT / ".github/workflows/godot-native-t088-selection.yml").read_text()

    def test_plan_reuse_is_context_and_generation_scoped(self) -> None:
        plan = self.canvas.split("func _mask_outline_tile_candidates(", 1)[1].split("\nfunc ", 1)[0]
        remember = self.canvas.split("func _remember_mask_outline_plan(", 1)[1].split("\nfunc ", 1)[0]
        for expected in (
            "_mask_outline_plan_valid", "_mask_outline_plan_mask == selection_mask",
            "_mask_outline_plan_generation != selection_mask.generation",
            "_mask_outline_plan_footprint == footprint", "_mask_outline_plan_focus == plan_focus",
            "_mask_outline_plan_inverted != selection_mask.inverted",
            "_mask_outline_plan_operation_count != selection_mask._operations.size()",
            "_mask_outline_plan_pixel_count != selection_mask._pixel_mask.size()",
            "_mask_outline_plan_candidates.duplicate()", "_mask_outline_cache.clear()",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, plan)
        self.assertIn("_mask_outline_plan_build_count += 1", remember)
        self.assertIn("_mask_outline_plan_candidates = candidates.duplicate()", remember)
        self.assertIn("_mask_outline_plan_valid = false", self.canvas)
        for expected in ("generation += 1", "copy.generation = generation"):
            self.assertIn(expected, self.selection)
        self.assertGreaterEqual(plan.count("return _remember_mask_outline_plan("), 6)

    def test_model_and_native_witnesses_enforce_reuse_and_pixels(self) -> None:
        for required in (
            "24 stable redraws do not reindex 4300 source-mask entries",
            "caller modifications cannot poison the cached candidate list",
            "sub-tile clipped footprint changes invalidate cached plan",
            "in-place source-mask change also invalidates traced contours",
            "direct inversion invalidates a previously indexed explicit plan",
            "fallback candidate plan is also reused when its context is stable",
            "warm_median_us",
        ):
            self.assertIn(required, self.model)
        for required in (
            "deferred redraws reuse the same candidate plan",
            "cached sparse outline remains visible in real framebuffer",
            "camera pan creates one new focal plan",
            "outline planning never publishes pixels or history",
            "changed_pixels",
        ):
            self.assertIn(required, self.native)

    def test_ci_has_46_required_ids_and_strict_bounded_witnesses(self) -> None:
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.fast, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        t088 = self.fast.split("id: ci_t088_selection_clipboard_model", 1)[1].split(
            "- name: Verify T-089", 1
        )[0]
        for required in (
            "res://tests/t144_outline_plan_model.gd",
            "T144_MODEL_PASSED checks=16 failures=0",
            "--marker T144_MODEL_PASSED",
            "test_t144_outline_plan_cache.py",
        ):
            self.assertIn(required, t088)
        for required in (
            "res://tests/t144_outline_plan_native.gd",
            "T144_NATIVE_PASSED checks=9 failures=0",
            "--marker T144_NATIVE_PASSED",
            "/tmp/t144-outline-native.log",
        ):
            self.assertIn(required, self.x11)

    def test_log_markers_fail_closed(self) -> None:
        for marker, count in (("T144_MODEL_PASSED", 16), ("T144_NATIVE_PASSED", 9)):
            valid = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(valid, marker)[0])
            for invalid in (
                valid + valid,
                valid.replace("failures=0", "failures=1"),
                valid + "SCRIPT ERROR: wrong mask generation\n",
            ):
                self.assertTrue(verify_log(invalid, marker)[0])


if __name__ == "__main__":
    unittest.main()
