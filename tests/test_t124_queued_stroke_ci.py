"""CI contracts for bounded, chronological input while another stroke drains."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CANVAS = ROOT / "addons/drawing/canvas.gd"
CI = ROOT / ".github/workflows/godot-check.yml"
NATIVE_CI = ROOT / ".github/workflows/godot-native-t095-brush.yml"
HEADLESS = ROOT / "drawing/tests/t124_queued_brush_smoke.gd"
NATIVE = ROOT / "drawing/tests/t124_queued_brush_native.gd"


class QueuedStrokeContracts(unittest.TestCase):
    def test_capture_is_bounded_and_not_a_second_uncommitted_edit(self) -> None:
        source = CANVAS.read_text()
        self.assertIn("const MAX_DEFERRED_STROKE_SAMPLES: int = 4096", source)
        self.assertIn("func _capture_deferred_stroke(position: Vector2)", source)
        self.assertIn("func _promote_deferred_stroke()", source)
        self.assertIn("if _stroke_phase == StrokePhase.DRAINING", source)
        self.assertIn("_deferred_points.size() >= MAX_DEFERRED_STROKE_SAMPLES", source)
        self.assertIn("_discard_deferred_stroke(\"Deferred stroke input limit reached", source)
        self.assertIn("_promote_deferred_stroke()", source.split("func _commit_stroke()")[1])

    def test_control_oracles_are_real_godot_tests(self) -> None:
        headless = HEADLESS.read_text()
        native = NATIVE.read_text()
        for contract in ("DrawingRenderer.render", "doc.undo()", "doc.redo()",
                         "T124_QUEUED_PASSED", "first_path()", "overflow_scenario()"):
            self.assertIn(contract, headless)
        for contract in ("root.push_input", "RenderingServer.frame_post_draw",
                         "root.get_texture().get_image()", "T124_NATIVE_PASSED",
                         "doc.undo()", "doc.redo()"):
            self.assertIn(contract, native)

    def test_required_ci_uses_existing_check_and_strict_verifier(self) -> None:
        ci = CI.read_text()
        section = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        self.assertIn("res://tests/t124_queued_brush_smoke.gd", section)
        self.assertIn("check_godot_model_log.py /tmp/godot-t124-queued-brush.log", section)
        self.assertIn("--marker T124_QUEUED_PASSED || ci_fail_marker", section)
        self.assertIn("res://tests/t124_queued_brush_native.gd", NATIVE_CI.read_text())
        self.assertIn("--marker T124_NATIVE_PASSED", NATIVE_CI.read_text())
        self.assertIn("res://tests/stroke_navigation_native.gd", NATIVE_CI.read_text())
        self.assertIn("--marker T095_NAV_PASSED", NATIVE_CI.read_text())


if __name__ == "__main__":
    unittest.main()
