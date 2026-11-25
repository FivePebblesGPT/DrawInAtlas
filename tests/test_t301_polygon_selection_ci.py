"""Required native CI and behavior contract for polygon/selection no-op preflight."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class PolygonSelectionContracts(unittest.TestCase):
    def test_required_ci_keeps_exact_native_witness(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        script = next(
            step.script for step in checks
            if step.identifier == "ci_t068_stationary_dab_parity"
        )
        self.assertIn("res://tests/t301_polygon_selection_noop.gd", script)
        self.assertIn("T301_POLYGON_SELECTION_PASSED checks=39 failures=0", script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t301-polygon-selection.log", script
        )

    def test_geometry_preflight_is_bounded_and_before_materialization(self) -> None:
        source = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        helper = source.split("func _polygon_selection_excludes_pixels(", 1)[1].split(
            "func apply_region(", 1
        )[0]
        for term in (
            "selection.inverted",
            "DrawingSelection.MAX_BULK_OVERLAP_PROBES",
            "points.size() > 65536 / candidate_count",
            "selection.allows(Vector2i(x, y))",
            "Geometry2D.is_point_in_polygon(",
            "return false",
        ):
            self.assertIn(term, helper)
        polygon = source.split("func paint_polygon(", 1)[1].split(
            "func _fill_source_pixel(", 1
        )[0]
        preflight = polygon.index("_polygon_selection_excludes_pixels(area, points, selection)")
        self.assertLess(preflight, polygon.index("_materialize_brush_preview()"))
        self.assertLess(preflight, polygon.index("_materialize_hokusai_preview()"))
        self.assertLess(preflight, polygon.index("_stage(x, y, rgba, selection)"))

    def test_native_witness_checks_negative_and_positive_geometry(self) -> None:
        witness = (ROOT / "tests/t301_polygon_selection_noop.gd").read_text(
            encoding="utf-8"
        )
        for term in (
            'rectangular: DrawingSelection',
            'masked.set_mask(',
            '"Subtract"',
            'selection.allows_any_in_area(',
            'session._brush_deferred',
            'session._preview_epoch == epoch',
            'fetches == 0',
            'unavailable = false',
            'document.undo()',
            'document.redo()',
            'mask.inverted = true',
            'large uncertain overlap never skips staging',
        ):
            self.assertIn(term, witness)


if __name__ == "__main__":
    unittest.main()
