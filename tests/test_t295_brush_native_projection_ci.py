"""Require native brush projection safety under existing fast T-068 CI."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class BrushProjectionContracts(unittest.TestCase):
    def test_required_native_step_gates_brush_boundary_witness(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        script = next(
            c.script for c in checks if c.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t295_brush_native_projection.gd", script)
        self.assertIn("T295_BRUSH_PROJECTION_PASSED checks=50 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t295-brush-projection.log",
            script,
        )
        self.assertLess(
            script.index("t294_bulk_native_projection.gd"),
            script.index("t295_brush_native_projection.gd"),
        )
        self.assertLess(
            script.index("t295_brush_native_projection.gd"),
            script.index("drawing_fill_verified_stage_smoke.gd"),
        )

    def test_brush_guard_precedes_lazy_sources_and_deferred_materialization(self) -> None:
        code = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        session = code.split("func _stage(", 1)[1].split("\nfunc _stage_brush_tile(", 1)[0]
        self.assertLess(
            session.index("_check_native_pixel_projection and not"),
            session.index("_materialize_brush_preview()"),
        )
        self.assertLess(
            session.index("_check_native_pixel_projection and not"),
            session.index("_stage_brush_tile("),
        )
        self.assertLess(
            session.index("_check_native_pixel_projection and not"),
            session.index("document._resolve_chunk("),
        )
        self.assertIn("MAX_PROJECTION_PIXEL_COORD", code)
        self.assertIn('ClassDB.class_exists("DrawingNativeTiles")', code)

    def test_real_witness_covers_axes_and_exact_history(self) -> None:
        code = (ROOT / "tests/t295_brush_native_projection.gd").read_text(encoding="utf-8")
        for proof in (
            "for axis_x: bool in [true, false]",
            "for sign_value: int in [1, -1]",
            "session._brush_deferred",
            "session._source_tiles.is_empty()",
            "document.undo()",
            "document.redo()",
        ):
            self.assertIn(proof, code)


if __name__ == "__main__":
    unittest.main()
