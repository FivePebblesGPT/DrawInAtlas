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

    def test_legacy_counted_success_marker_requires_exact_positive_check_count(self) -> None:
        marker = "T089_MODEL_PASSED"
        self.assertEqual(verify_log(f"{marker}: 62 checks\n{LEAK}\n", marker), ([], 1))
        for text in (
            f"{marker}: 0 checks",
            f"{marker}: sixty-two checks",
            f"{marker}: failed 1/62 checks",
            f"{marker}: 62 checks but failed",
            f"{marker}: 62 checks and ignored a runtime error",
            f"prefix {marker}: 62 checks",
        ):
            with self.subTest(text=text):
                self.assertNotEqual(verify_log(text + "\n", marker)[0], [])
        problems, _ = verify_log(f"{marker}\n{marker}: 62 checks\n", marker)
        self.assertTrue(any("exactly one" in problem for problem in problems))

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

    def test_every_drawing_model_uses_one_strict_log_check(self) -> None:
        """Prevent a future loose substring grep from becoming a false-green gate."""
        from replay_godot_ci import extract_checks, WORKFLOW

        scripts = {check.identifier: check.script for check in extract_checks(WORKFLOW.read_text())}
        expected = {
            "ci_t085_live_stroke_preview": ("/tmp/godot-t085-model.log", "T085_MODEL_PASSED"),
            "ci_t086_viewport_cache_model": ("/tmp/godot-t086-cache-model.log", "T086_MODEL_PASSED"),
            "ci_t087_image_frame_model": ("/tmp/godot-t087-frame-model.log", "T087_MODEL_PASSED"),
            "ci_t088_selection_clipboard_model": ("/tmp/godot-t088-selection-model.log", "T088_MODEL_PASSED"),
            "ci_t089_layer_structure_model": ("/tmp/godot-t089-layers-model.log", "T089_MODEL_PASSED"),
            "ci_t091_single_group_docking_model": ("/tmp/godot-t091-dock-model.log", "T091_MODEL_PASSED"),
            "ci_t092_compact_color_history_model": ("/tmp/godot-t092-model.log", "T092_MODEL_PASSED"),
            "ci_t093_object_discovery_model": ("/tmp/godot-t093-discovery-model.log", "T093_MODEL_PASSED"),
        }
        for check_id, (log, success_marker) in expected.items():
            with self.subTest(check_id=check_id):
                script = scripts[check_id]
                invocation = f"python3 tools/check_godot_model_log.py {log} --marker {success_marker}"
                self.assertEqual(script.count(invocation), 1)
                self.assertIn("|| ci_fail_marker", script.split(invocation, 1)[1].split("\n", 1)[0])
                self.assertNotIn(f"grep -q '{success_marker}'", script)
                self.assertNotIn("if grep -E 'SCRIPT ERROR:", script)

    def test_embedded_marker_and_post_success_runtime_fault_cannot_hide(self) -> None:
        # Old grep -q accepted the first string and missed the later fault
        # for T-089/T-092/T-093 (or any unrecognized ERROR: diagnostic).
        examples = (
            f"Bootstrap T089_MODEL_PASSED in unrelated text\n",
            f"{MARKER}\nSCRIPT ERROR: Invalid call in deferred renderer\n",
            f"{MARKER}\nERROR: Unexpected storage corruption\n",
            f"{MARKER}\n{MARKER}\n",
        )
        for content in examples:
            with self.subTest(content=content):
                marker = "T089_MODEL_PASSED" if "T089" in content else MARKER
                self.assertNotEqual(verify_log(content, marker)[0], [])

    def test_fail_late_shell_rejects_marker_plus_runtime_error(self) -> None:
        """Exercise the exact CI guard's exit path, not merely its source text."""
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "model.log"
            for content, expected_code in (
                (f"{MARKER}\n{LEAK}\n", 0),
                (f"{MARKER}\nERROR: Unexpected storage corruption\n", 1),
                (f"{MARKER}\nSCRIPT ERROR: deferred call failed\n", 1),
            ):
                with self.subTest(content=content):
                    log.write_text(content, encoding="utf-8")
                    script = (
                        "source tools/ci_fail_late.sh\n"
                        f"python3 tools/check_godot_model_log.py '{log}' --marker {MARKER} "
                        "|| ci_fail_marker 'T094 strict model log rejected'\n"
                        "ci_finish\n"
                    )
                    result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script],
                                            cwd=ROOT, capture_output=True, text=True)
                    self.assertEqual(result.returncode, expected_code, result.stdout + result.stderr)

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
