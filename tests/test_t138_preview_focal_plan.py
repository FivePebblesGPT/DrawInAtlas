"""Fail-closed contracts for focal cache retention with detached previews."""
from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PreviewFocalRetentionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.native_ci = (ROOT / ".github/workflows/godot-native-t086-viewport.yml").read_text()
        cls.model = (ROOT / "drawing/tests/t138_preview_focal_plan_model.gd").read_text()
        cls.native = (ROOT / "drawing/tests/t138_preview_focal_plan_native.gd").read_text()

    def test_preview_plan_checks_metadata_and_precedes_frame_evictions(self) -> None:
        plan = self.canvas.split("func _focal_retention_plan(", 1)[1].split("\nfunc ", 1)[0]
        draw = self.canvas.split("func _draw() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for guard in (
            "preview_stamps: Dictionary = {}",
            "preview_complete: bool = false",
            "has_preview and not preview_complete",
            "MAX_FOCAL_PLAN_CANDIDATES",
            "preview_stamps[key] is int",
            "int(preview_stamps[key]) <= 0",
            "x_text.is_valid_int()",
            "y_text.is_valid_int()",
            '"%d,%d" % [tile.x, tile.y] != key',
            "window.has_point(tile)",
            "occupied.size() <= MAX_DISPLAY_TILES",
            "MAX_DISPLAY_TILES",
        ):
            with self.subTest(guard=guard):
                self.assertIn(guard, plan)
        self.assertLess(draw.index("_preview_index_for_draw(preview_session, visible_tiles)"),
                        draw.index("_focal_retention_plan(visible_tiles, cache_focus,"))
        self.assertLess(draw.index("_focal_retention_plan(visible_tiles, cache_focus,"),
                        draw.index("_sparse_visible_draw_rows(visible_tiles,"))
        self.assertIn("indexed_stamps, preview_session != null and use_preview_index", draw)
        self.assertIn('metrics["focal_plan_tiles"]', draw)
        self.assertIn("_focal_retention_plan(window, focus).is_empty()", self.model)

    def test_model_and_native_oracles_exercise_real_fallback_and_pixels(self) -> None:
        for clause in (
            "nearest preview-only tile is retained",
            "moving focus selects a distant preview-only tile",
            "complete detached Move preview uses the same bounded focal plan",
            "incomplete preview cannot authorize focal plan",
            "malformed or noncanonical preview metadata",
            "over-limit preview metadata falls back",
            "committed focal plan remains unchanged after cancellation",
        ):
            self.assertIn(clause, self.model)
        for clause in (
            "191 real signed source chunks registered",
            "live preview supplies a complete display index",
            "complete over-budget preview uses 144-entry focal retention plan",
            "near-focus preview-only display texture is retained",
            "panning with complete preview continues focal preselection",
            "blue detached pixel appears in real framebuffer",
            "Undo restores exact empty center",
            "Redo restores center source pixel",
        ):
            self.assertIn(clause, self.native)

    def test_existing_ci_ids_and_exact_log_markers(self) -> None:
        required = self.workflow.split("id: ci_t086_viewport_cache_model", 1)[1].split(
            "- name: Verify T-087", 1
        )[0]
        for clause in (
            "res://tests/t138_preview_focal_plan_model.gd",
            "T138_FOCAL_PASSED checks=19 failures=0",
            "--marker T138_FOCAL_PASSED",
            "test_t138_preview_focal_plan.py",
        ):
            self.assertIn(clause, required)
        for clause in (
            "res://tests/t138_preview_focal_plan_native.gd",
            "T138_NATIVE_PASSED checks=22 failures=0",
            "--marker T138_NATIVE_PASSED",
            "/tmp/t138-preview-focal-native.log",
        ):
            self.assertIn(clause, self.native_ci)
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.workflow, re.M)
        self.assertEqual((len(ids), len(set(ids))), (46, 46))
        for marker, count in (("T138_FOCAL_PASSED", 19), ("T138_NATIVE_PASSED", 22)):
            valid = f"{marker} checks={count} failures=0\n"
            self.assertFalse(verify_log(valid, marker)[0])
            for invalid in (valid + valid, valid.replace("failures=0", "failures=1"),
                            valid + "SCRIPT ERROR: stale source\n"):
                self.assertTrue(verify_log(invalid, marker)[0])


if __name__ == "__main__":
    unittest.main()
