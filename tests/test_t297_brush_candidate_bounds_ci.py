"""T-297: real numeric-overflow Brush witness remains a required CI gate."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class BrushCandidateBoundsContracts(unittest.TestCase):
    def test_required_native_step_runs_fail_closed_brush_witness(self) -> None:
        steps = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(steps), 46)
        script = next(
            s.script for s in steps if s.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t297_brush_candidate_bounds.gd", script)
        self.assertIn("T297_BRUSH_BOUNDS_PASSED checks=113 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t297-brush-bounds.log", script
        )
        self.assertLess(
            script.index("t296_clear_native_projection.gd"),
            script.index("t297_brush_candidate_bounds.gd"),
        )
        self.assertLess(
            script.index("t297_brush_candidate_bounds.gd"),
            script.index("drawing_fill_verified_stage_smoke.gd"),
        )

    def test_candidate_window_clips_float_before_integer_conversion(self) -> None:
        source = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        segment = source.split("func _paint_segment(", 1)[1].split(
            "\nfunc _paint_oblique_scanlines(", 1
        )[0]
        self.assertLess(
            segment.index("left_bound = maxf(left_bound"),
            segment.index("floori(left_bound)"),
        )
        self.assertLess(
            segment.index("left_bound <= -1073741824.0"),
            segment.index("floori(left_bound)"),
        )
        for expression in (
            "floori(maxf(float(left), center.x - reach - 2.5))",
            "ceili(minf(float(right), center.x + reach + 1.5))",
            "floori(maxf(float(left), minf(x_a, x_b) - broad_radius))",
            "floori(maxf(float(left), min_x - reach - 2.5))",
            "floori(maxf(float(left), start.x - reach - 2.5))",
        ):
            self.assertIn(expression, source)

    def test_witness_covers_overflow_clipping_and_history(self) -> None:
        witness = (ROOT / "tests/t297_brush_candidate_bounds.gd").read_text(
            encoding="utf-8"
        )
        for requirement in (
            "_unclipped(1.0e30)",
            "_unclipped(1.0e100)",
            "_clipped(\"dab\"",
            "_clipped(\"horizontal\"",
            "_clipped(\"vertical\"",
            "_clipped(\"oblique\"",
            "session.change_count() == 4",
            "doc.undo().ok",
            "doc.redo().ok",
            "SOURCE if x == 1 and y == 1 else 0",
        ):
            self.assertIn(requirement, witness)


if __name__ == "__main__":
    unittest.main()
