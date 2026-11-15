"""Fail-closed Object rename and Save As variant target invariants."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class ObjectPendingMetadataContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        cls.ci = (ROOT / ".github/workflows/godot-check.yml").read_text()
        cls.smoke = (ROOT / "drawing/tests/t131_object_pending_metadata_smoke.gd").read_text()

    def test_rename_guards_only_changed_source_names(self) -> None:
        body = self.workspace.split("func _rename_object(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('rename_field.text.strip_edges() != session.name', body)
        self.assertIn('_can_persist_or_close("Rename Object")', body)
        self.assertIn("session.set_name(rename_field.text)", body)
        self.assertLess(body.index('_can_persist_or_close("Rename Object")'),
                        body.index("session.set_name(rename_field.text)"))

    def test_variant_name_is_atomic_on_rejected_publication(self) -> None:
        body = self.workspace.split("func _save_as_named_object(", 1)[1].split("\nfunc ", 1)[0]
        for expected in ('_can_persist_or_close("Save Object As")',
                         'previous_variant_name: String = session.variant_name',
                         'session.variant_name = title',
                         'if not _publish_object(true):',
                         'session.variant_name = previous_variant_name'):
            self.assertIn(expected, body)
        self.assertLess(body.index('"Save Object As"'), body.index("session.variant_name = title"))
        self.assertLess(body.index("session.variant_name = title"),
                        body.index("if not _publish_object(true)"))
        publication = self.workspace.split("func _publish_object(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("-> bool:", self.workspace.split("func _publish_object(", 1)[0][-100:] +
                      "func _publish_object(" + publication)
        self.assertIn("return false", publication)
        self.assertIn("return true", publication)

    def test_existing_ci_step_runs_real_godot_witness_fail_closed(self) -> None:
        step = self.ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        for expected in ("res://tests/t131_object_pending_metadata_smoke.gd",
                         "--marker T131_OBJECT_META_PASSED",
                         "T131_OBJECT_META_PASSED checks=21 failures=0",
                         "test_t131_object_pending_metadata.py"):
            self.assertIn(expected, step)
        for expected in ("app._rename_object()", "app._save_as_named_object()",
                         "Simulated publisher failure", "malformed publication result",
                         "queued_paint(app.canvas)", "await_commit(app.canvas)"):
            self.assertIn(expected, self.smoke)
        self.assertEqual(verify_log("T131_OBJECT_META_PASSED checks=21 failures=0\n",
                                    "T131_OBJECT_META_PASSED")[0], [])
        for forged in (
            "T131_OBJECT_META_PASSED checks=20 failures=0\nSCRIPT ERROR: forged\n",
            "T131_OBJECT_META_FAILED: variant changed\nT131_OBJECT_META_PASSED checks=21 failures=0\n",
            "T131_OBJECT_META_PASSED checks=21 failures=0\nT131_OBJECT_META_PASSED checks=21 failures=0\n",
        ):
            self.assertTrue(verify_log(forged, "T131_OBJECT_META_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
