"""T-092: CI, persistence isolation and native witness contracts."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_native_t092_log import verify  # noqa: E402


class T092ColorsHistoryTests(unittest.TestCase):
    def test_model_runs_in_required_fast_ci(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        self.assertIn("color_history_smoke.gd", workflow)
        self.assertIn("T092_MODEL_PASSED", workflow)
        self.assertIn("continue-on-error: true", workflow)

    def test_native_workflow_stages_imports_and_collects_software_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-native-t092-color-history.yml").read_text()
        for field in ("workflow_dispatch", "--import --quit", "xvfb-run",
                      "color_history_native.gd", "T092_SCREENSHOTS",
                      "check_native_t092_log.py", "upload-artifact@v4"):
            with self.subTest(field=field):
                self.assertIn(field, workflow)

    def test_log_retains_known_shutdown_warnings_only_after_success(self) -> None:
        base = "T092_NATIVE: 32 checks; 0 failed\nT092_NATIVE_PASSED"
        self.assertEqual(verify(base), (True, [], 0))
        self.assertEqual(verify(base + "\nERROR: Texture with GL ID of 18: leaked 32 bytes."),
                         (True, [], 1))
        for bad in ("", "T092_NATIVE_PASSED", base + "\nT092_NATIVE_PASSED",
                    "T092_NATIVE: 31 checks; 0 failed\nT092_NATIVE_PASSED",
                    "T092_NATIVE: 32 checks; 1 failed\nT092_NATIVE_PASSED",
                    base + "\nSCRIPT ERROR: bad assignment", base + "\nERROR: compositor failed",
                    "ERROR: Texture with GL ID of 18: leaked 32 bytes.\n" + base):
            with self.subTest(bad=bad):
                self.assertFalse(verify(bad)[0])

    def test_app_preference_is_separate_from_document_file(self) -> None:
        prefs = (ROOT / "addons/drawing/workspace_preferences.gd").read_text()
        shell = (ROOT / "addons/drawing/workspace.gd").read_text()
        self.assertIn("user://drawing-workspace-preferences-v1.json", shell)
        self.assertIn("func _load_preferences()", shell)
        self.assertIn("record_selection_history", prefs)
        self.assertIn('"Preferences…"', shell)
        self.assertNotIn('history_label.text = "Undo / Redo"', shell)


if __name__ == "__main__":
    unittest.main()
