"""A masked-out bulk command must not materialize an accepted deferred Brush."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class MaskedBulkContracts(unittest.TestCase):
    def test_required_ci_fails_closed_on_native_witness(self) -> None:
        steps = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(steps), 46)
        script = next(
            s.script for s in steps if s.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t299_masked_bulk_noop.gd", script)
        self.assertIn("T299_MASKED_BULK_PASSED checks=40 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t299-masked-bulk.log", script
        )

    def test_early_guard_precedes_deferred_materialization(self) -> None:
        source = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        self.assertIn("not selection.inverted", source)
        self.assertIn("not selection.bounds.intersects(area)", source)
        for name, next_name in (
            ("apply_region", "fill_rect"),
            ("fill_rect", "clear_rect"),
            ("clear_rect", "_clear_rect_dense_tiles"),
            ("paint_polygon", "_fill_source_pixel"),
        ):
            method = source.split(f"func {name}(", 1)[1].split(f"func {next_name}(", 1)[0]
            guard = method.index("_bulk_selection_excludes_area(area, selection)")
            self.assertLess(guard, method.index("_materialize_brush_preview()"))
            self.assertLess(guard, method.index("_materialize_hokusai_preview()"))

    def test_native_witness_protects_mask_and_history(self) -> None:
        source = (ROOT / "tests/t299_masked_bulk_noop.gd").read_text(encoding="utf-8")
        for required in (
            "session._brush_deferred",
            "session._preview_epoch == initial_epoch",
            "fetches == 0",
            "session.clear_rect(",
            "session.paint_polygon(",
            "session.apply_region(",
            "session.fill_rect(",
            "inverted.inverted = true",
            "document.undo()",
            "document.redo()",
        ):
            self.assertIn(required, source)


if __name__ == "__main__":
    unittest.main()
