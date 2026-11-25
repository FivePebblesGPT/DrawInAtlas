"""Pin native fill projection safety to the existing required T-068 CI step."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class NativeProjectionFillCIContracts(unittest.TestCase):
    def test_required_native_step_gates_signed_projection_witness(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        native = next(c for c in checks if c.identifier == "ci_t068_stationary_dab_parity")
        script = native.script
        self.assertIn("res://tests/t293_fill_native_projection.gd", script)
        self.assertIn("T293_PROJECTION_PASSED checks=41 failures=0", script)
        self.assertIn("check_godot_model_log.py /tmp/godot-t293-projection.log", script)
        self.assertLess(
            script.index("t292_fill_frontier_bounds.gd"),
            script.index("t293_fill_native_projection.gd"),
        )
        self.assertLess(
            script.index("t293_fill_native_projection.gd"),
            script.index("drawing_fill_verified_stage_smoke.gd"),
        )

    def test_witness_tests_both_projection_fences_and_native_history(self) -> None:
        source = (ROOT / "tests/t293_fill_native_projection.gd").read_text(encoding="utf-8")
        edit = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        for term in (
            '"positive-x"', '"negative-x"', '"positive-y"', '"negative-y"',
            'document.undo()', 'document.redo()', 'session._source_tiles.is_empty()',
        ):
            self.assertIn(term, source)
        # Other native publication paths may legitimately share this predicate.
        self.assertGreaterEqual(edit.count("pixel_coordinates_in_projection_range("), 2)


if __name__ == "__main__":
    unittest.main()
