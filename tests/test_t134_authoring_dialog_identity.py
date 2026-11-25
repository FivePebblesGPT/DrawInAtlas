"""Authoring modal completions belong to their originating document and row."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class AuthoringDialogIdentityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "addons/drawing/workspace.gd").read_text()
        cls.smoke = (ROOT / "drawing/tests/t134_authoring_dialog_identity_smoke.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()

    @staticmethod
    def method(source: str, name: str) -> str:
        return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]

    def test_all_six_real_confirm_signals_are_guarded(self) -> None:
        controls = (
            ("layer_rename_dialog", "layer_rename", "_ask_layer_rename", "_commit_layer_rename"),
            ("rename_dialog", "object_rename", "_ask_rename_object", "_rename_object"),
            ("frame_dialog", "object_frame", "_ask_object_frame", "_change_object_frame"),
            ("grid_dialog", "grid", "_ask_grid_settings", "_apply_grid_settings"),
            ("image_frame_dialog", "image_frame", "_ask_image_frame", "_apply_image_frame"),
        )
        for dialog, kind, opener, legacy_mutation in controls:
            with self.subTest(dialog=dialog):
                self.assertIn(f'{dialog}.confirmed.connect(_confirm_{kind})', self.source)
                self.assertIn(
                    f'{dialog}.canceled.connect(_cancel_authoring_dialog.bind("{kind}"))',
                    self.source,
                )
                self.assertIn(
                    f'_capture_authoring_dialog_target("{kind}")',
                    self.method(self.source, opener),
                )
                wrapper = self.method(self.source, f"_confirm_{kind}")
                self.assertIn(f'_authoring_dialog_is_current("{kind}"', wrapper)
                self.assertIn(legacy_mutation + "()", wrapper)
                self.assertLess(
                    wrapper.index("_authoring_dialog_is_current"),
                    wrapper.index(legacy_mutation + "()"),
                )

    def test_text_panel_apply_has_same_identity_guard(self) -> None:
        self.assertIn("text_apply.pressed.connect(_confirm_text)", self.source)
        self.assertIn("text_cancel.pressed.connect(_cancel_text)", self.source)
        self.assertIn('_capture_authoring_dialog_target("text")', self.method(self.source, "_edit_text_at"))
        commit = self.method(self.source, "_commit_text_dialog")
        self.assertLess(commit.index("_text_target_current()"), commit.index("document.commit_text("))
        guard = self.method(self.source, "_text_target_current")
        for condition in ('_save_target_is_current(target)', 'current_document().revision',
                          'current_layer()', 'selected_layer_node()'):
            self.assertIn(condition, guard)
        self.assertIn('_cancel_authoring_dialog("text")', self.method(self.source, "_cancel_text"))

    def test_guard_requires_exact_tab_document_object_and_layer(self) -> None:
        capture = self.method(self.source, "_capture_authoring_dialog_target")
        self.assertIn("_capture_save_target()", capture)
        for field in ('"layer"', '"selected_node"', '"revision"'):
            self.assertIn(field, capture)
        authorize = self.method(self.source, "_authoring_dialog_is_current")
        self.assertLess(authorize.index("_authoring_dialog_targets.erase(kind)"),
                        authorize.index("_save_target_is_current(target)"))
        for condition in (
            'current_layer() == String(target["layer"])',
            'selected_layer_node() == String(target["selected_node"])',
            'current_document().revision == int(target["revision"])',
        ):
            self.assertIn(condition, authorize)
        self.assertIn("_authoring_dialog_targets.erase(kind)",
                      self.method(self.source, "_cancel_authoring_dialog"))
        self.assertIn("reopen it", authorize)

    def test_oracle_has_negative_and_positive_paths(self) -> None:
        for expected in (
            "stale layer rename cannot mutate a different tab",
            "stale Text editor cannot create a layer in another tab",
            "stale image-frame dialog cannot rewrite another tab",
            "stale grid dialog cannot change the other tab view",
            "cancelled layer rename cannot be replayed by a late confirmation",
            "stale layer dialog cannot rename a newly selected layer",
            "stale Object rename cannot change either source",
            "stale Object frame cannot change another source",
            "reused tab index cannot authorize an old layer rename",
            "current-tab layer dialog commits to its intended row",
            "current-tab Text dialog commits to original document",
            "current Object frame still works",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.smoke)

    def test_ci_and_strict_log_contract(self) -> None:
        step = self.workflow.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1
        )[0]
        for text in (
            "res://tests/t134_authoring_dialog_identity_smoke.gd",
            "--marker T134_DIALOG_PASSED",
            "T134_DIALOG_PASSED checks=22 failures=0",
            "test_t134_authoring_dialog_identity.py",
        ):
            self.assertIn(text, step)
        self.assertEqual(verify_log("T134_DIALOG_PASSED checks=22 failures=0\n",
                                    "T134_DIALOG_PASSED")[0], [])
        for forged in (
            "T134_DIALOG_PASSED checks=21 failures=1\n",
            "T134_DIALOG_FAILED: wrong tab\nT134_DIALOG_PASSED checks=22 failures=0\n",
            "T134_DIALOG_PASSED checks=22 failures=0\n"
            "T134_DIALOG_PASSED checks=22 failures=0\n",
            "T134_DIALOG_PASSED checks=22 failures=0\nSCRIPT ERROR: forged\n",
        ):
            self.assertTrue(verify_log(forged, "T134_DIALOG_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
