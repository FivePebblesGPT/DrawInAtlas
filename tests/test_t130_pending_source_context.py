"""Fail-closed source-context guards for unpublished Brush transactions."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class PendingSourceContextContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        cls.ci = (ROOT / ".github/workflows/godot-check.yml").read_text()

    def test_early_guards_prevent_source_context_mutation(self) -> None:
        actions = {
            "_deselect": ("Clear Selection", "canvas.clear_selection()"),
            "_apply_image_frame": ("Change Image Frame", 'tabs[active_tab]["frame"] = frame'),
            "_change_object_frame": ("Change Object Frame", "session.set_frame(origin, bounds)"),
        }
        for function, (label, mutation) in actions.items():
            with self.subTest(function=function):
                body = self.workspace.split(f"func {function}(", 1)[1].split("\nfunc ", 1)[0]
                guard = f'_can_persist_or_close("{label}")'
                self.assertIn(guard, body)
                self.assertIn(mutation, body)
                self.assertLess(body.index(guard), body.index(mutation))
        self.assertIn("canvas.selection_mask.enabled", self.workspace.split(
            "func _deselect(", 1)[1].split("\nfunc ", 1)[0])
        self.assertIn("if frame == canvas.image_bounds:", self.workspace.split(
            "func _apply_image_frame(", 1)[1].split("\nfunc ", 1)[0])
        self.assertIn("origin != session.origin or bounds != session.bounds", self.workspace.split(
            "func _change_object_frame(", 1)[1].split("\nfunc ", 1)[0])

    def test_existing_required_ci_step_executes_exact_oracle(self) -> None:
        step = self.ci.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        for term in (
            "res://tests/t130_pending_source_context_smoke.gd",
            "--marker T130_CONTEXT_PASSED",
            "T130_CONTEXT_PASSED checks=34 failures=0",
            "test_t130_pending_source_context.py",
        ):
            self.assertIn(term, step)
        self.assertEqual(verify_log("T130_CONTEXT_PASSED checks=34 failures=0\n",
                                    "T130_CONTEXT_PASSED")[0], [])
        for forged in (
            "T130_CONTEXT_PASSED checks=33 failures=0\nSCRIPT ERROR: failed\n",
            "T130_CONTEXT_FAILED: cancelled stroke\nT130_CONTEXT_PASSED checks=34 failures=0\n",
            "T130_CONTEXT_PASSED checks=34 failures=0\nT130_CONTEXT_PASSED checks=34 failures=0\n",
        ):
            self.assertTrue(verify_log(forged, "T130_CONTEXT_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
