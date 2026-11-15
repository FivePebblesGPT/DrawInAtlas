"""Standalone OS close must not bypass document or Brush publication gates."""

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402


class StandaloneWindowQuitContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "addons/drawing/workspace.gd").read_text()
        cls.smoke = (ROOT / "drawing/tests/t133_window_quit_smoke.gd").read_text()
        cls.workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()

    @staticmethod
    def function(source: str, name: str) -> str:
        return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]

    def test_only_standalone_root_overrides_and_restores_engine_quit(self) -> None:
        ready = self.function(self.source, "_ready")
        exit_tree = self.function(self.source, "_exit_tree")
        notification = self.function(self.source, "_notification")
        self.assertIn("get_parent() == get_tree().root", ready)
        self.assertIn("_old_auto_accept_quit = get_tree().auto_accept_quit", ready)
        self.assertIn("get_tree().auto_accept_quit = false", ready)
        self.assertIn("get_tree().auto_accept_quit = _old_auto_accept_quit", exit_tree)
        self.assertIn("NOTIFICATION_WM_CLOSE_REQUEST and _window_quit_guard_enabled", notification)
        self.assertIn("_request_window_quit()", notification)

    def test_quit_requires_drain_then_exact_existing_close_flow(self) -> None:
        request = self.function(self.source, "_request_window_quit")
        advance = self.function(self.source, "_advance_window_quit")
        close = self.function(self.source, "_close_index")
        self.assertLess(request.index('_can_persist_or_close("Close Window")'),
                        request.index("_window_quit_requested = true"))
        self.assertIn('_can_persist_or_close("Close Window")', advance)
        self.assertIn("_request_close_tab(tabs.size() - 1)", advance)
        self.assertIn("get_tree().quit()", advance)
        self.assertLess(advance.index("if tabs.is_empty():"),
                        advance.index("get_tree().quit()"))
        self.assertIn('call_deferred("_advance_window_quit")', close)
        cancel = self.function(self.source, "_cancel_pending_close")
        self.assertIn("_window_quit_requested = false", cancel)
        self.assertIn("close_dialog.canceled.connect(_cancel_pending_close)", self.source)
        self.assertIn('close_dialog.hide()', self.source)
        self.assertIn('call_deferred("_save_and_close")', self.source)

    def test_oracle_checks_pending_cancel_multi_tab_and_embedded(self) -> None:
        for witness in (
            "released brush has unpublished pixels",
            "window close cannot discard an unpublished brush transaction",
            "rejected OS close is visible",
            "dirty standalone tab triggers Save/Discard/Cancel",
            "Cancel revokes the OS close request",
            "embedded workspace never changes Atlas host quit policy",
            "clean tab closes; next dirty tab prompts in order",
            "Cancel stops multi-tab close",
            "Save choice uses existing Save As flow",
            "saved tab contains exact RGBA8 from correct document",
            "explicit Discard closes final tab",
            "cancelling Object close leaves the private source untouched",
            "saved Object closes only after successful portable publication",
        ):
            with self.subTest(witness=witness):
                self.assertIn(witness, self.smoke)

    def test_required_ci_integrates_strict_and_exact_log_without_new_step(self) -> None:
        step = self.workflow.split("id: ci_t085_live_stroke_preview", 1)[1].split(
            "- name: Verify T-086", 1)[0]
        for expected in (
            "res://tests/t133_window_quit_smoke.gd",
            "--marker T133_WINDOW_QUIT_PASSED",
            "T133_WINDOW_QUIT_PASSED checks=31 failures=0",
            "test_t133_window_quit.py",
        ):
            self.assertIn(expected, step)
        ids = re.findall(r"^\s+id: (ci_[a-z0-9_]+)\s*$", self.workflow, re.M)
        self.assertEqual(len(ids), 46)
        self.assertEqual(len(set(ids)), 46)
        self.assertEqual(verify_log("T133_WINDOW_QUIT_PASSED checks=31 failures=0\n",
                                    "T133_WINDOW_QUIT_PASSED")[0], [])
        for bad in (
            "T133_WINDOW_QUIT_FAILED: dropped\nT133_WINDOW_QUIT_PASSED\n",
            "T133_WINDOW_QUIT_PASSED\nSCRIPT ERROR: other error\n",
            "T133_WINDOW_QUIT_PASSED\nT133_WINDOW_QUIT_PASSED\n",
        ):
            self.assertTrue(verify_log(bad, "T133_WINDOW_QUIT_PASSED")[0])


if __name__ == "__main__":
    unittest.main()
