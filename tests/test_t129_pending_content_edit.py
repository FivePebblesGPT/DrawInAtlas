"""Pending Brush source ownership across layer and clipboard commands."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PendingContentEditContracts(unittest.TestCase):
    def test_mutators_refuse_revision_changes_before_document_writes(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        actions = {
            "_create_selected_layer": "Add Layer",
            "_set_row_visibility": "Change Layer Visibility",
            "_set_row_lock": "Change Layer Lock",
            "_move_selected_layer": "Reorder Layer",
            "_indent_selected_layer": "Indent Layer",
            "_outdent_selected_layer": "Outdent Layer",
            "_commit_layer_rename": "Rename Layer",
            "_remove_layer": "Remove Layer",
            "_commit_text_dialog": "Commit Text",
            "_rasterize_text": "Rasterize Text",
            "_delete_selection": "Delete Pixels",
            "_cut_selection": "Cut Pixels",
            "_paste_selection": "Paste Pixels",
        }
        for name, label in actions.items():
            with self.subTest(name=name):
                body = source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]
                self.assertIn(f'not _can_persist_or_close("{label}")', body)
                self.assertLess(body.index(f'not _can_persist_or_close("{label}")'),
                                min((body.index(x) for x in (
                                    "current_document().create_layer(",
                                    "current_document().set_visibility(",
                                    "current_document().set_locked(",
                                    "current_document().reorder(",
                                    "current_document().rename_layer(",
                                    "current_document().remove_subtree(",
                                    "current_document().rasterize_text(",
                                    "document.commit_text(",
                                    "current_document().begin_edit(",
                                    "_insertion_target()",
                                ) if x in body), default=len(body)))
        selection = source.split("func _select_layer_node(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('not _can_persist_or_close("Change Layer")', selection)
        self.assertIn("item.select(0)", selection)
        self.assertIn("node_id == selected_layer_node() and canvas.has_pending_stroke()", selection)

    def test_ci_runs_strict_witness_and_preserves_legacy_layer_contract(self) -> None:
        ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        step = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1
        )[0]
        for required in (
            "res://tests/t129_pending_content_edit_smoke.gd",
            "T129_PENDING_EDIT_PASSED checks=35 failures=0",
            "test_t129_pending_content_edit.py",
            "--marker T129_PENDING_EDIT_PASSED",
        ):
            self.assertIn(required, step)
        legacy = (ROOT / "drawing/tests/layer_structure_smoke.gd").read_text()
        self.assertIn("row visibility refuses to invalidate unpublished source pixels", legacy)
        self.assertIn("workspace.canvas.cancel_gesture()", legacy)
        self.assertIn("row visibility resumes after explicit cancellation", legacy)
        self.assertEqual(verify_log("T129_PENDING_EDIT_PASSED checks=35 failures=0\n",
                                    "T129_PENDING_EDIT_PASSED")[0], [])
        for bad in (
            "T129_PENDING_EDIT_PASSED checks=34 failures=0\nSCRIPT ERROR: broken\n",
            "T129_PENDING_EDIT_FAILED: lost paint\nT129_PENDING_EDIT_PASSED checks=35 failures=0\n",
            "T129_PENDING_EDIT_PASSED checks=35 failures=0\nT129_PENDING_EDIT_PASSED checks=35 failures=0\n",
        ):
            self.assertTrue(verify_log(bad, "T129_PENDING_EDIT_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
