"""Require native Delete preflight under the existing fast T-068 CI step."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class ClearProjectionContracts(unittest.TestCase):
    def test_required_native_step_fails_closed_on_signed_delete_witness(self) -> None:
        steps = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(steps), 46)
        script = next(
            s.script for s in steps if s.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t296_clear_native_projection.gd", script)
        self.assertIn("T296_CLEAR_PROJECTION_PASSED checks=50 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t296-clear-projection.log", script
        )
        self.assertLess(
            script.index("t295_brush_native_projection.gd"),
            script.index("t296_clear_native_projection.gd"),
        )
        self.assertLess(
            script.index("t296_clear_native_projection.gd"),
            script.index("drawing_fill_verified_stage_smoke.gd"),
        )

    def test_delete_guard_is_before_any_preview_or_lazy_source(self) -> None:
        source = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        method = source.split("func clear_rect(", 1)[1].split("\nfunc _clear_rect_dense_tiles(", 1)[0]
        guard = method.index("_bulk_area_in_native_projection(area)")
        for action in (
            "_materialize_hokusai_preview()",
            "_materialize_brush_preview()",
            "_materialize_clear_preview()",
            "document._resolve_chunk(",
        ):
            self.assertLess(guard, method.index(action))

    def test_real_witness_checks_four_edges_and_deferred_history(self) -> None:
        source = (ROOT / "tests/t296_clear_native_projection.gd").read_text(
            encoding="utf-8"
        )
        for requirement in (
            "for axis_x: bool in [true, false]",
            "for sign_value: int in [1, -1]",
            "session.clear_rect(",
            "session._clear_deferred",
            "session._brush_deferred",
            "reads == 0",
            "document.undo()",
            "document.redo()",
        ):
            self.assertIn(requirement, source)


if __name__ == "__main__":
    unittest.main()
