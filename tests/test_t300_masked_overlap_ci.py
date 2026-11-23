"""Required CI must reject masked-overlap no-ops that flatten deferred Brush."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class MaskedOverlapContracts(unittest.TestCase):
    def test_required_native_ci_runs_strict_witness(self) -> None:
        steps = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(steps), 46)
        script = next(
            step.script
            for step in steps
            if step.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t300_masked_overlap_noop.gd", script)
        self.assertIn("T300_MASK_OVERLAP_PASSED checks=62 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t300-mask-overlap.log", script
        )

    def test_bounded_mask_probe_precedes_deferred_materialization(self) -> None:
        selection = (ROOT / "addons/drawing/selection.gd").read_text(encoding="utf-8")
        self.assertIn("const MAX_BULK_OVERLAP_PROBES: int = 4096", selection)
        probe = selection.split("func allows_any_in_area(", 1)[1].split(
            "func translated(", 1
        )[0]
        self.assertIn("if not enabled or inverted:", probe)
        self.assertIn("MAX_BULK_OVERLAP_PROBES / overlap.size.x", probe)
        self.assertIn("if allows(Vector2i(x, y)):", probe)
        source = (ROOT / "addons/drawing/edit_session.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("not selection.allows_any_in_area(area)", source)
        for method, next_method in (
            ("apply_region", "fill_rect"),
            ("fill_rect", "clear_rect"),
            ("clear_rect", "_clear_rect_dense_tiles"),
            ("paint_polygon", "_fill_source_pixel"),
        ):
            body = source.split(f"func {method}(", 1)[1].split(
                f"func {next_method}(", 1
            )[0]
            guard = body.index("_bulk_selection_excludes_area(area, selection)")
            self.assertLess(guard, body.index("_materialize_brush_preview()"))
            self.assertLess(guard, body.index("_materialize_hokusai_preview()"))

    def test_witness_covers_masks_combinations_loader_and_native_history(self) -> None:
        fixture = (ROOT / "tests/t300_masked_overlap_noop.gd").read_text(
            encoding="utf-8"
        )
        for term in (
            "selection.bounds.intersects(AREA)",
            'sparse.set_mask(bits)',
            '"Subtract"',
            '"Intersect"',
            '"Add"',
            "session._brush_deferred",
            "session._preview_epoch == epoch",
            "fetches == 0",
            "session.clear_rect(",
            "session.paint_polygon(",
            "session.apply_region(",
            "session.fill_rect(",
            "document.undo()",
            "document.redo()",
            "sparse.inverted = true",
        ):
            self.assertIn(term, fixture)


if __name__ == "__main__":
    unittest.main()
