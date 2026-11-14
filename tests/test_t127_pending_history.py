"""Regression contracts for Undo/Redo during unpublished Brush transactions."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PendingBrushHistoryContracts(unittest.TestCase):
    def test_all_history_entrypoints_guard_revision_before_undo_redo(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        for action in ("Undo", "Redo"):
            with self.subTest(action=action):
                body = source.split(f"func _{action.lower()}(", 1)[1].split("\nfunc ", 1)[0]
                guard = f'if not _can_persist_or_close("{action}"):'
                self.assertIn(guard, body)
                self.assertLess(body.index(guard), body.index(f"current_document().{action.lower()}()"))
                self.assertLess(body.index(guard), body.index("canvas.has_floating_move()"))
        self.assertIn("canvas.has_pending_stroke()", source)
        self.assertIn("_can_persist_or_close", source)

    def test_keyboard_menu_and_history_buttons_share_guarded_callbacks(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.assertIn('Callable(self, "_undo")', source)
        self.assertIn('Callable(self, "_redo")', source)
        self.assertIn('history_undo.pressed.connect(_undo)', source)
        self.assertIn('history_redo.pressed.connect(_redo)', source)
        keyboard = source.split("func _unhandled_key_input(", 1)[1].split("\nfunc ", 1)[0]
        for excerpt in ("KEY_Z:", "KEY_Y: _redo()", "_undo()", "_redo()"):
            self.assertIn(excerpt, keyboard)

    def test_real_document_queued_history_witness_and_strict_ci(self) -> None:
        witness = (ROOT / "drawing/tests/t127_pending_history_smoke.gd").read_text()
        for excerpt in (
            "_deferred_stroke", "_undo()", "_redo()", "_unhandled_key_input(",
            "history_undo.pressed.emit()", "history_redo.pressed.emit()",
            "DrawingRenderer.render", "DrawingFileIO.open_with_frame",
            "alpha_at", "T127_HISTORY_PASSED",
        ):
            with self.subTest(excerpt=excerpt):
                self.assertIn(excerpt, witness)
        ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        step = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1
        )[0]
        self.assertIn("res://tests/t127_pending_history_smoke.gd", step)
        self.assertIn("/tmp/godot-t127-history.log --marker T127_HISTORY_PASSED", step)
        self.assertIn("grep -Fqx 'T127_HISTORY_PASSED checks=40 failures=0'", step)
        self.assertIn("|| ci_fail_marker 'T127 pending Brush history rejected'", step)
        self.assertIn("test_t127_pending_history.py", step)
        self.assertEqual(verify_log("T127_HISTORY_PASSED checks=40 failures=0\n", "T127_HISTORY_PASSED")[0], [])
        for invalid in (
            "T127_HISTORY_PASSED checks=40 failures=1\n",
            "T127_HISTORY_PASSED checks=39 failures=0\nT127_HISTORY_FAILED: missing assertion\n",
            "T127_HISTORY_PASSED checks=40 failures=0\nSCRIPT ERROR: bad source\n",
            "T127_HISTORY_FAILED: cancelled edit\nT127_HISTORY_PASSED checks=40 failures=0\n",
        ):
            self.assertTrue(verify_log(invalid, "T127_HISTORY_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
