"""Source-routing and CI contracts for release-backlog persistence safety."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class T125PendingPersistenceContracts(unittest.TestCase):
    def test_all_persistence_and_close_entrypoints_refuse_pending_strokes(self) -> None:
        source = (ROOT / "addons/drawing/workspace.gd").read_text()
        canvas = (ROOT / "addons/drawing/canvas.gd").read_text()
        self.assertIn("func has_pending_stroke() -> bool:", canvas)
        self.assertIn("return session != null or not _deferred_stroke.is_empty()", canvas)
        self.assertIn("func _can_persist_or_close(action: String) -> bool:", source)
        self.assertIn("_cancel_pending_close()", source.split("func _can_persist_or_close", 1)[1].split("func _request_close_current", 1)[0])
        for func in ("_ask_save", "_save", "_save_file", "_publish_object"):
            body = source.split(f"func {func}(", 1)[1].split("\nfunc ", 1)[0]
            self.assertIn("_can_persist_or_close(", body, func)
        body = source.split("func _request_close_tab(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('if not _can_persist_or_close("Close Tab"):', body)
        close_body = source.split("func _close_index(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('if not _can_persist_or_close("Close Tab"):', close_body)

    def test_regression_executes_real_document_and_publishing_workflows(self) -> None:
        test = (ROOT / "drawing/tests/t125_pending_persistence_smoke.gd").read_text()
        for required in ("_save_file(path)", "_save()", "_ask_save()",
                         "_request_close_tab(", "_publish_object(false)",
                         "DrawingFileIO.open_with_frame", "DrawingObjectEditorFile.open",
                         "DrawingRenderer.render", "_deferred_stroke", "T125_PENDING_PASSED"):
            self.assertIn(required, test)

    def test_existing_required_ci_step_checks_exact_marker_and_exit(self) -> None:
        ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        step = ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        self.assertIn("res://tests/t125_pending_persistence_smoke.gd", step)
        self.assertIn("/tmp/godot-t125-persistence.log --marker T125_PENDING_PASSED", step)
        self.assertIn("|| ci_fail_marker 'T125 pending persistence/close rollback rejected'", step)
        self.assertIn("test_t125_pending_persistence.py", step)
        failures, _ = verify_log("T125_PENDING_PASSED checks=29 failures=0\n", "T125_PENDING_PASSED")
        self.assertEqual(failures, [])
        for invalid in ("T125_PENDING_PASSED checks=29 failures=1\n",
                        "T125_PENDING_PASSED checks=29 failures=0\nSCRIPT ERROR: broken\n",
                        "T125_PENDING_FAILED: overwritten\nT125_PENDING_PASSED checks=29 failures=0\n"):
            with self.subTest(invalid=invalid[:30]):
                self.assertTrue(verify_log(invalid, "T125_PENDING_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
