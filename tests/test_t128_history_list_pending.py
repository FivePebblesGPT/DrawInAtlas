"""Guard History list row navigation from unpublished Brush history conflicts."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PendingHistoryListContracts(unittest.TestCase):
    def test_list_jump_refuses_pending_revisions_and_restores_cursor(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        body = source.split("func _history_item_selected(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('if not _can_persist_or_close("History navigation"):', body)
        self.assertIn("if target == document.history_position():", body)
        self.assertLess(body.index("if target == document.history_position():"),
                        body.index('_can_persist_or_close("History navigation")'))
        self.assertLess(body.index('_can_persist_or_close("History navigation")'),
                        body.index("document.undo()"))
        self.assertLess(body.index('_can_persist_or_close("History navigation")'),
                        body.index("document.redo()"))
        self.assertIn("_history_row_positions.find(document.history_position())", body)
        self.assertIn("history_list.select(current_row)", body)
        self.assertIn("history_list.deselect_all()", body)
        self.assertIn("_rendering_history = true", body)
        self.assertIn("_rendering_history = false", body)
        self.assertIn("history_list.item_selected.connect(_history_item_selected)", source)

    def test_godot_witness_is_required_under_existing_ci_id(self) -> None:
        witness = (ROOT / "drawing/tests/t128_history_list_pending_smoke.gd").read_text()
        for expected in (
            "history_list.item_selected.emit(row)",
            "history_list.select(row)",
            "selected_position(app)",
            "_deferred_stroke", "_history_row_positions", "await_commit",
            "DrawingRenderer.render", "DrawingFileIO.open_with_frame",
            "T128_HISTORY_LIST_PASSED",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, witness)
        ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        existing_step = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1
        )[0]
        self.assertIn("res://tests/t128_history_list_pending_smoke.gd", existing_step)
        self.assertIn("--marker T128_HISTORY_LIST_PASSED", existing_step)
        self.assertIn("T128_HISTORY_LIST_PASSED checks=37 failures=0", existing_step)
        self.assertIn("test_t128_history_list_pending.py", existing_step)
        self.assertEqual(verify_log(
            "T128_HISTORY_LIST_PASSED checks=37 failures=0\n",
            "T128_HISTORY_LIST_PASSED",
        )[0], [])
        for bad in (
            "T128_HISTORY_LIST_PASSED checks=37 failures=1\n",
            "T128_HISTORY_LIST_FAILED: cancelled stroke\nT128_HISTORY_LIST_PASSED checks=37 failures=0\n",
            "T128_HISTORY_LIST_PASSED checks=37 failures=0\nSCRIPT ERROR: broken source\n",
            "T128_HISTORY_LIST_PASSED checks=37 failures=0\nT128_HISTORY_LIST_PASSED checks=37 failures=0\n",
        ):
            self.assertTrue(verify_log(bad, "T128_HISTORY_LIST_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
