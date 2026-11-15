"""Asynchronous Save As callbacks must not target a different document."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class SaveDialogIdentityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "addons/drawing/workspace.gd").read_text()
        cls.smoke = (ROOT / "drawing/tests/t132_dialog_document_identity_smoke.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()

    @staticmethod
    def function(source: str, name: str) -> str:
        return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]

    def test_file_dialog_completion_checks_origin_before_writing(self) -> None:
        self.assertIn("save_dialog.file_selected.connect(_save_dialog_selected)", self.source)
        self.assertIn("save_dialog.canceled.connect(_save_dialog_cancelled)", self.source)
        open_dialog = self.function(self.source, "_show_save_dialog")
        self.assertIn("_save_dialog_target = _capture_save_target()", open_dialog)
        completion = self.function(self.source, "_save_dialog_selected")
        for text in ("_save_target_is_current(target)", "_save_file(path)",
                     "_cancel_pending_close()", "_local_save_as = false"):
            self.assertIn(text, completion)
        self.assertLess(completion.index("_save_target_is_current(target)"),
                        completion.index("_save_file(path)"))
        cancelled = self.function(self.source, "_save_dialog_cancelled")
        self.assertIn("_save_dialog_target.clear()", cancelled)
        self.assertIn("_cancel_pending_close()", cancelled)

    def test_tab_and_object_identity_checked_against_active_context(self) -> None:
        identity = self.function(self.source, "_capture_save_target")
        self.assertIn('"tab": active_tab', identity)
        self.assertIn('"document": current_document()', identity)
        self.assertIn('"object": current_object()', identity)
        check = self.function(self.source, "_save_target_is_current")
        for key in ('active_tab == int(target["tab"])',
                    'current_document() == target["document"]',
                    'current_object() == target["object"]'):
            self.assertIn(key, check)

    def test_variant_dialog_is_also_bound_to_its_origin(self) -> None:
        self.assertIn("variant_dialog.confirmed.connect(_variant_dialog_confirmed)", self.source)
        ask = self.function(self.source, "_ask_save")
        self.assertLess(ask.index("_variant_dialog_target = _capture_save_target()"),
                        ask.index("variant_dialog.popup_centered()"))
        completion = self.function(self.source, "_variant_dialog_confirmed")
        self.assertLess(completion.index("_save_target_is_current(target)"),
                        completion.index("_save_as_named_object()"))
        self.assertIn("variant_dialog.canceled.connect(_variant_dialog_cancelled)", self.source)
        cancelled = self.function(self.source, "_variant_dialog_cancelled")
        self.assertIn("_variant_dialog_target.clear()", cancelled)
        self.assertIn("_cancel_pending_close()", cancelled)

    def test_oracle_covers_overwrite_rebinding_cancel_and_direct_save(self) -> None:
        for fixture in (
            "stale FileDialog cannot overwrite prior document path",
            "cancellation invalidates a late FileDialog event",
            "reused tab index never authorizes saving an unrelated document",
            "local Object file chooser cannot publish the wrong source",
            "stale named Save As cannot publish a different Object source",
            "genuine named Save As invokes only the originating publisher",
            "direct Save still accepts an explicit destination",
            "saved file contains originating document RGBA8",
        ):
            with self.subTest(fixture=fixture):
                self.assertIn(fixture, self.smoke)

    def test_existing_required_ci_step_executes_fail_closed_oracle(self) -> None:
        step = self.workflow.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        for text in ("res://tests/t132_dialog_document_identity_smoke.gd",
                     "--marker T132_DIALOG_PASSED",
                     "T132_DIALOG_PASSED checks=34 failures=0",
                     "test_t132_dialog_document_identity.py"):
            self.assertIn(text, step)
        self.assertEqual(verify_log("T132_DIALOG_PASSED checks=34 failures=0\n",
                                    "T132_DIALOG_PASSED")[0], [])
        for forged in (
            "T132_DIALOG_PASSED checks=31 failures=0\nSCRIPT ERROR: forged\n",
            "T132_DIALOG_FAILED: wrong target\nT132_DIALOG_PASSED checks=34 failures=0\n",
            "T132_DIALOG_PASSED checks=34 failures=0\n"
            "T132_DIALOG_PASSED checks=34 failures=0\n",
        ):
            self.assertTrue(verify_log(forged, "T132_DIALOG_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
