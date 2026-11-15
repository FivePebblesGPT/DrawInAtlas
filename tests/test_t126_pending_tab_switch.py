"""Contract checks for preserving unpublished Brush edits across tab changes."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PendingBrushTabSwitchContracts(unittest.TestCase):
    def test_entrypoints_guard_pending_transaction_before_mutating_tabs(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        for name in (
            "new_drawing", "new_object", "_open_file", "_open_raster_file",
            "_open_object_file", "_ask_open", "_ask_open_object",
            "attach_object_session",
        ):
            with self.subTest(name=name):
                body = source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]
                self.assertIn("_can_persist_or_close(", body)
        for name in ("_request_close_tab", "_close_index", "_save_and_close"):
            with self.subTest(name=name):
                body = source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]
                self.assertIn("_can_persist_or_close(", body)

    def test_tabbar_reentrancy_and_refusal_restore_selected_tab(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        body = source.split("func _activate(", 1)[1].split("\nfunc ", 1)[0]
        before_assignment = body.split("active_tab = index", 1)[0]
        self.assertIn("if index == active_tab and canvas.has_pending_stroke():", before_assignment)
        self.assertIn('not _can_persist_or_close("Switch Tab")', before_assignment)
        self.assertIn("tab_bar.current_tab = active_tab", before_assignment)
        self.assertIn("\t\treturn", before_assignment)

    def test_real_godot_witness_and_fail_late_ci_are_strict(self) -> None:
        witness = (ROOT / "drawing/tests/t126_pending_tab_switch_smoke.gd").read_text()
        for snippet in (
            "_cycle_tab(-1)", "_activate(0)", "_activate(1)",
            "tab_bar.current_tab = 0", "_request_close_tab(0)",
            "_open_file(path)", "_open_file(raster_path)",
            "new_drawing()", "new_object()", "attach_object_session(",
            "DrawingFileIO.open_with_frame", "DrawingRenderer.render",
            "original.undo()", "original.redo()", "_deferred_stroke",
            "T126_TAB_SWITCH_PASSED",
        ):
            with self.subTest(snippet=snippet):
                self.assertIn(snippet, witness)
        ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        step = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1
        )[0]
        self.assertIn("res://tests/t126_pending_tab_switch_smoke.gd", step)
        self.assertIn("/tmp/godot-t126-tab-switch.log --marker T126_TAB_SWITCH_PASSED", step)
        self.assertIn("|| ci_fail_marker 'T126 pending document switch rejected'", step)
        self.assertIn("test_t126_pending_tab_switch.py", step)
        self.assertEqual(verify_log("T126_TAB_SWITCH_PASSED checks=34 failures=0\n", "T126_TAB_SWITCH_PASSED")[0], [])
        for invalid in (
            "T126_TAB_SWITCH_PASSED checks=32 failures=1\n",
            "T126_TAB_SWITCH_PASSED checks=34 failures=0\nSCRIPT ERROR: broken\n",
            "T126_TAB_SWITCH_FAILED: lost input\nT126_TAB_SWITCH_PASSED checks=34 failures=0\n",
        ):
            self.assertTrue(verify_log(invalid, "T126_TAB_SWITCH_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
