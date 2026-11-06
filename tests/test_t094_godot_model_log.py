"""T-094: strict model smoke logs preserve known leaks without hiding defects."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_godot_model_log import verify_log  # noqa: E402

MARKER = "T094_MODEL_PASSED"
LEAK = "ERROR: 11 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit."
TEXTURE_LEAK = "ERROR: Texture with GL ID of 19: leaked 2048 bytes."


class ModelLogTests(unittest.TestCase):
    def test_exact_known_leaks_after_one_success_marker_are_reported(self) -> None:
        issues, count = verify_log(f"Godot Engine\n{MARKER}\n{LEAK}\n{TEXTURE_LEAK}\n", MARKER)
        self.assertEqual(issues, [])
        self.assertEqual(count, 2)

    def test_pre_success_leak_is_never_whitelisted(self) -> None:
        issues, count = verify_log(f"{LEAK}\n{MARKER}\n", MARKER)
        self.assertTrue(issues)
        self.assertEqual(count, 0)

    def test_unknown_error_after_success_is_fatal(self) -> None:
        for error in ("ERROR: Invalid native mask", "SCRIPT ERROR: Invalid call",
                      "Parse Error: invalid token", "Compile Error: script broken",
                      "T094_MODEL_FAILED: pixel mismatch", "DOCK MODEL FAILED: wrong state"):
            with self.subTest(error=error):
                issues, _ = verify_log(f"{MARKER}\n{error}\n", MARKER)
                self.assertTrue(issues)

    def test_missing_or_duplicate_or_ambiguous_marker_fails(self) -> None:
        for output in ("", "OTHER_MODEL_PASSED", f"{MARKER}\n{MARKER}"):
            with self.subTest(output=output):
                self.assertTrue(verify_log(output, MARKER)[0])
        for bad in ("", "success", "_PASSED", "PASSED", "BAD-PASSED"):
            with self.assertRaises(ValueError):
                verify_log(f"{MARKER}\n", bad)

    def test_fast_ci_affected_smokes_call_shared_strict_verifier(self) -> None:
        from replay_godot_ci import extract_checks, WORKFLOW
        scripts = {check.identifier: check.script for check in extract_checks(WORKFLOW.read_text())}
        self.assertIn("mktemp -d", scripts["ci_07_verify_t_053_standalone_linux_release_package"])
        self.assertIn("check_godot_model_log.py", scripts["ci_07_verify_t_053_standalone_linux_release_package"])
        for identifier in (
            "ci_t087_image_frame_model", "ci_t088_selection_clipboard_model",
            "ci_10_verify_t_058_editable_text_font_integrity_and_undoable_rasteriz",
            "ci_t064_nested_project_copy",
            "ci_12_verify_t_062_object_editor_source_publishing_bound_origin_and_s",
            "ci_14_verify_t_055_atlas_canonical_drawing_composition_and_input",
            "ci_dock_layout_model", "ci_t065_asset_browser_model",
            "ci_t065_asset_thumbnail_model", "ci_t065_atlas_browser_bridge",
        ):
            with self.subTest(check=identifier):
                script = scripts[identifier]
                self.assertIn("python3 tools/check_godot_model_log.py", script)
                self.assertNotIn("if grep -E 'SCRIPT ERROR:|^ERROR:", script)

    def test_cli_preserves_actual_model_log_and_reports_leaks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "smoke.log"
            log.write_text(f"{MARKER}\n{LEAK}\n", encoding="utf-8")
            call = [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                    str(log), "--marker", MARKER]
            result = subprocess.run(call, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("POST_EXIT_LEAKS: 1", result.stdout)
            self.assertIn(LEAK, log.read_text())
            log.write_text(f"{MARKER}\nERROR: something else\n")
            rejected = subprocess.run(call, capture_output=True, text=True)
            self.assertEqual(rejected.returncode, 1)
            self.assertIn("LOG_REJECTED", rejected.stdout)


if __name__ == "__main__":
    unittest.main()
