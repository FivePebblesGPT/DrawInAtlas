"""Prevent regressions in the required Rust-backed bulk projection witness."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class BulkNativeProjectionContracts(unittest.TestCase):
    def test_required_native_ci_has_fail_closed_bulk_witness(self) -> None:
        steps = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(steps), 46)
        script = next(s.script for s in steps if s.identifier == "ci_t068_stationary_dab_parity")
        self.assertIn("res://tests/t294_bulk_native_projection.gd", script)
        self.assertIn("T294_BULK_PROJECTION_PASSED checks=71 failures=0", script)
        self.assertIn("check_godot_model_log.py /tmp/godot-t294-bulk-projection.log", script)
        self.assertLess(script.index("t293_fill_native_projection.gd"),
                        script.index("t294_bulk_native_projection.gd"))
        self.assertLess(script.index("t294_bulk_native_projection.gd"),
                        script.index("drawing_fill_verified_stage_smoke.gd"))

    def test_signed_extent_preflight_precedes_source_or_preview_mutation(self) -> None:
        edit = (ROOT / "addons/drawing/edit_session.gd").read_text(encoding="utf-8")
        preflight = edit.split("func _bulk_area_in_native_projection(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("document._native_raster_store", preflight)
        self.assertIn("DrawingNativeTiles", preflight)
        self.assertEqual(preflight.count("pixel_coordinates_in_projection_range("), 2)
        for name, next_name in (("apply_region", "fill_rect"),
                                ("fill_rect", "clear_rect"),
                                ("paint_polygon", "_fill_source_pixel")):
            method = edit.split(f"func {name}(", 1)[1].split(f"\nfunc {next_name}(", 1)[0]
            self.assertLess(method.index("_bulk_area_in_native_projection(area)"),
                            method.index("_materialize_hokusai_preview()"))

    def test_witness_has_signed_axes_and_transaction_evidence(self) -> None:
        source = (ROOT / "tests/t294_bulk_native_projection.gd").read_text(encoding="utf-8")
        for expected in ("for axis_x: bool in [true, false]",
                         "for sign_value: int in [1, -1]", "session.fill_rect(",
                         "session.apply_region(", "session.paint_polygon(",
                         "session._brush_deferred", "document.undo()", "document.redo()"):
            self.assertIn(expected, source)


if __name__ == "__main__":
    unittest.main()
