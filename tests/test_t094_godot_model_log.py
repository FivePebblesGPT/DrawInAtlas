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

    def test_wrapped_diagnostics_and_process_crashes_cannot_claim_success(self) -> None:
        # Prior verifier only recognized ERROR: at column zero and missed
        # terminal-color wrappers plus shell crash text printed after PASS.
        bad_lines = (
            "  ERROR: invalid script state",
            "\tERROR: invalid renderer state",
            "\x1b[31mERROR: invalid renderer state\x1b[0m",
            "  \x1b[1;31mERROR: failed read\x1b[0m",
            "FATAL ERROR: invalid native state",
            "CRASH: renderer backend failed",
            "Segmentation fault (core dumped)",
            "Aborted (core dumped)",
            "terminate called after throwing an instance of RuntimeError",
        )
        for line in bad_lines:
            with self.subTest(line=line):
                issues, leaks = verify_log(f"{MARKER}\n{line}\n", MARKER)
                self.assertTrue(issues)
                self.assertEqual(leaks, 0)
        # An indented or ANSI-wrapped leak is not byte-identical to a known
        # shutdown diagnostic; it must not consume the narrow leak exception.
        for line in (" " + LEAK, "\x1b[31m" + LEAK + "\x1b[0m"):
            with self.subTest(line=line):
                issues, leaks = verify_log(f"{MARKER}\n{line}\n", MARKER)
                self.assertTrue(issues)
                self.assertEqual(leaks, 0)

    def test_shell_wrapped_crashes_and_tracebacks_cannot_follow_pass(self) -> None:
        # Shells include line numbers and child PIDs before the crash banner.
        # The prior prefix-only crash matcher silently accepted these lines.
        bad_lines = (
            "bash: line 8: 12345 Segmentation fault (core dumped) ./godot",
            "bash: line 10: 321 Aborted (core dumped) ./godot",
            "dash: 77: Segmentation fault ./godot",
            "sh: line 2: 98 Segmentation fault ./godot",
            "./scripts/check.sh: line 4: 1024 Aborted ./godot",
            "\x1b[31m  bash: line 1: 7 Segmentation fault (core dumped) ./godot\x1b[0m",
            "Traceback (most recent call last):",
            "  \x1b[1;31mTraceback (most recent call last):\x1b[0m",
        )
        for line in bad_lines:
            with self.subTest(line=line):
                problems, leaks = verify_log(f"{MARKER}\n{line}\n", MARKER)
                self.assertTrue(problems, line)
                self.assertEqual(leaks, 0)
        # Explanatory lines must not trigger a crash regex mid-sentence.
        notes = (
            "Diagnostic note: Segmentation fault (core dumped) text is rejected",
            "Reporter documents Traceback (most recent call last): output",
        )
        for line in notes:
            with self.subTest(note=line):
                self.assertEqual(verify_log(f"{MARKER}\n{line}\n", MARKER), ([], 0))

    def test_native_signal_crashes_cannot_follow_a_pass_marker(self) -> None:
        # Signal 4/7/8 crash messages are emitted by common POSIX shells and
        # can follow an already printed Godot PASS marker. The old checker
        # accepted all of these without reporting a problem.
        failures = (
            "Bus error (core dumped)",
            "Illegal instruction (core dumped)",
            "Floating point exception (core dumped)",
            "bash: line 8: 12345 Bus error (core dumped) ./godot",
            "dash: 31: Illegal instruction ./godot",
            "sh: line 2: 7 Floating point exception ./godot",
            "./ci/godot.sh: line 40: 48 Bus error ./godot",
            "\x1b[1;31m  bash: line 9: 81 Illegal instruction (core dumped) ./godot\x1b[0m",
        )
        for fatal in failures:
            with self.subTest(fatal=fatal):
                self.assertTrue(verify_log(f"{MARKER}\n{fatal}\n", MARKER)[0])
        # Do not interpret ordinary notes mentioning crash signatures as
        # fatal diagnostics; exact known post-success leaks are unchanged.
        for note in (
            "A reporter describes Bus error (core dumped) in documentation.",
            "Native crash notes: Illegal instruction on unsupported CPUs.",
            "README: Floating point exception examples are disallowed.",
        ):
            with self.subTest(note=note):
                self.assertEqual(verify_log(f"{MARKER}\n{note}\n", MARKER), ([], 0))
        self.assertEqual(verify_log(f"{MARKER}\n{LEAK}\n", MARKER), ([], 1))

    def test_native_signal_crash_rejected_by_real_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "signal.log"
            for fatal in (
                "Bus error (core dumped)",
                "dash: 31: Illegal instruction ./godot",
                "sh: line 2: 7 Floating point exception ./godot",
            ):
                with self.subTest(fatal=fatal):
                    log.write_text(f"{MARKER}\n{fatal}\n", encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                         str(log), "--marker", MARKER],
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn("GODOT_MODEL_LOG_REJECTED", result.stdout)

    def test_post_success_oom_heap_and_uncaught_python_failures(self) -> None:
        # These production crash banners were previously ignored when they
        # followed a valid Godot model PASS marker. Keep the known RID-leak
        # exception intentionally narrow.
        failures = (
            "Killed",  # POSIX signal-9 diagnostic from an enclosing process
            "bash: line 8: 12345 Killed                  ./godot",
            "dash: 77: Killed ./godot",
            "sh: line 2: 98 Killed ./godot",
            "./ci/model.sh: line 4: 1024 Killed ./godot",
            "\x1b[31m  bash: line 3: 77 Killed ./godot\x1b[0m",
            "malloc(): corrupted top size",
            "malloc(): unsorted double linked list corrupted",
            "free(): double free detected in tcache 2",
            "realloc(): invalid pointer",
            "munmap_chunk(): invalid pointer",
            "double free or corruption (!prev)",
            'Exception in thread "MainThread":',
            "Fatal Python error: Segmentation fault",
        )
        for line in failures:
            with self.subTest(fatal=line):
                issues, leaks = verify_log(f"{MARKER}\n{line}\n", MARKER)
                self.assertTrue(issues, line)
                self.assertEqual(leaks, 0)
        for benign in (
            "Note: Killed a stale process during test cleanup",
            "Model docs mention malloc(): corrupted top size",
            "Reporter quotes Fatal Python error: as an example",
            "Traceback format documented in test metadata",
        ):
            with self.subTest(note=benign):
                self.assertEqual(verify_log(f"{MARKER}\n{benign}\n", MARKER), ([], 0))
        self.assertEqual(verify_log(f"{MARKER}\n{LEAK}\n", MARKER), ([], 1))

    def test_compact_godot_timestamped_errors_fail_after_success(self) -> None:
        # Godot can print a compact E <timestamp> diagnostic instead of the
        # verbose ERROR: form; the former used to produce false-green CI logs.
        examples = (
            "E 0:00:00:542   draw_canvas: Invalid texture RID.",
            "E 0:01:23:005   load: Failed to parse resource.",
            "E 0:00:00   renderer: Invalid state.",
            "\x1b[1;31m  E 0:00:03:127   parse: Broken resource\x1b[0m",
        )
        for diagnostic in examples:
            with self.subTest(diagnostic=diagnostic):
                errors, leaks = verify_log(f"{MARKER}\n{diagnostic}\n", MARKER)
                self.assertTrue(errors, diagnostic)
                self.assertEqual(leaks, 0)
        # Non-error elapsed-time reports and text documenting the format must
        # not cause arbitrary prose to fail an otherwise valid run.
        for benign in (
            "I 0:00:00:542   Initialized renderer.",
            "W 0:00:00:543   Shader cache warmup pending.",
            "Reporter describes E 0:00:00:542 diagnostics in its manual.",
        ):
            with self.subTest(benign=benign):
                self.assertEqual(verify_log(f"{MARKER}\n{benign}\n", MARKER), ([], 0))
        self.assertEqual(verify_log(f"{MARKER}\n{LEAK}\n", MARKER), ([], 1))

    def test_compact_godot_error_is_rejected_by_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "godot.log"
            log.write_text(f"{MARKER}\nE 0:00:00:542   render: Invalid RID.\n")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                 str(log), "--marker", MARKER],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("GODOT_MODEL_LOG_REJECTED", result.stdout)

    def test_heap_failure_is_rejected_by_real_log_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "model.log"
            for fatal in ("malloc(): corrupted top size", "bash: line 8: 9 Killed ./godot"):
                with self.subTest(fatal=fatal):
                    log.write_text(f"{MARKER}\n{fatal}\n", encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                         str(log), "--marker", MARKER],
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("GODOT_MODEL_LOG_REJECTED", result.stdout)

    def test_shell_crash_and_python_traceback_fail_through_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "godot.log"
            for fatal in ("bash: line 5: 314 Segmentation fault ./godot",
                          "Traceback (most recent call last):"):
                with self.subTest(fatal=fatal):
                    log.write_text(f"{MARKER}\n{fatal}\n", encoding="utf-8")
                    result = subprocess.run(
                        [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                         str(log), "--marker", MARKER],
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("GODOT_MODEL_LOG_REJECTED", result.stdout)

    def test_wrapped_diagnostics_fail_through_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "godot.log"
            log.write_text(f"{MARKER}\n\x1b[31mERROR: runtime fault\x1b[0m\n")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/check_godot_model_log.py"),
                 str(log), "--marker", MARKER],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("GODOT_MODEL_LOG_REJECTED", result.stdout)

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

    def test_known_positive_summary_formats_are_accepted(self) -> None:
        valid = (
            "T086_COLD_PASSED 45/45",
            "T089_MODEL_PASSED: 62 checks",
            "DRAWING_TEXT_UI_PASSED (91 checks; 0 failed)",
            "DRAWING_PACK_FONT_PASSED (0 failures)",
            "T064_COPY_UI_PASSED (39 checks, 0 failures)",
            "T055_COMPOSITION_PASSED checks=89 failures=0",
            "T065_ATLAS_BROWSER_PASSED 28 checks, failures=0",
            "T095_ORACLE_PASSED",
        )
        for line in valid:
            with self.subTest(line=line):
                marker = line.split()[0].split(":")[0]
                self.assertEqual(verify_log(line + "\n" + LEAK + "\n", marker), ([], 1))

    def test_partial_or_spoofed_success_summaries_are_fatal(self) -> None:
        examples = (
            "T086_COLD_PASSED 44/45",  # A failing fraction was previously accepted.
            "T086_COLD_PASSED 0/0",
            "T086_COLD_PASSED -1/3",
            "T086_COLD_PASSED 045/045",
            "T089_MODEL_PASSED: 0 checks",
            "T089_MODEL_PASSED: 62 checks; 3 failed",
            "DRAWING_TEXT_UI_PASSED (91 checks; 2 failed)",
            "DRAWING_TEXT_UI_PASSED (0 checks; 0 failed)",
            "DRAWING_PACK_FONT_PASSED (1 failures)",
            "T064_COPY_UI_PASSED (39 checks, 1 failures)",
            "T064_COPY_UI_PASSED (0 checks, 0 failures)",
            "T055_COMPOSITION_PASSED checks=89 failures=2",
            "T055_COMPOSITION_PASSED checks=0 failures=0",
            "T065_ATLAS_BROWSER_PASSED 28 checks, failures=4",
            "T065_ATLAS_BROWSER_PASSED 0 checks, failures=0",
            "T095_ORACLE_PASSED but some pixels failed",
            "T096_MODEL_PASSED (warning: stale selection)",
            "T095_ORACLE_PASSED 1/1 ignored error",
        )
        for line in examples:
            with self.subTest(line=line):
                marker = line.split()[0].split(":")[0]
                self.assertTrue(verify_log(line + "\n", marker)[0])
        marker = "T086_COLD_PASSED"
        for extra in (f"{marker} 2/3", f"{marker} with problems"):
            with self.subTest(extra=extra):
                self.assertTrue(verify_log(f"{marker}\n{extra}\n", marker)[0])

    def test_new_source_pixel_oracles_are_required_without_new_check_ids(self) -> None:
        from replay_godot_ci import extract_checks, WORKFLOW
        from report_godot_ci import expected_check_ids

        workflow = WORKFLOW.read_text()
        checks = extract_checks(workflow)
        scripts = {check.identifier: check.script for check in checks}
        self.assertEqual(len(checks), 46)
        self.assertEqual([check.identifier for check in checks], expected_check_ids(workflow))
        for check_id, script_name, log, marker in (
            ("ci_t085_live_stroke_preview", "brush_coverage_smoke.gd",
             "/tmp/godot-t095-oracle.log", "T095_ORACLE_PASSED"),
            ("ci_t088_selection_clipboard_model", "selection_large_smoke.gd",
             "/tmp/godot-t096-model.log", "T096_MODEL_PASSED"),
        ):
            with self.subTest(check_id=check_id):
                script = scripts[check_id]
                self.assertIn(f"--script res://tests/{script_name}", script)
                self.assertIn(f"tee {log}", script)
                invocation = f"python3 tools/check_godot_model_log.py {log} --marker {marker}"
                self.assertEqual(script.count(invocation), 1)
                self.assertIn("|| ci_fail_marker", script.split(invocation, 1)[1].split("\n", 1)[0])
                self.assertIn("source tools/ci_fail_late.sh", script)
                self.assertIn("ci_finish", script)
                self.assertLess(script.index("python3 tools/build_drawing_app.py --in-place"),
                                script.index(f"--script res://tests/{script_name}"))
                self.assertLess(script.index("godot --headless --editor --path drawing --import --quit"),
                                script.index(f"--script res://tests/{script_name}"))

    def test_headless_save_dialog_keeps_real_dialog_and_desktop_centering(self) -> None:
        workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        section = workspace.split("func _show_save_dialog() -> void:\n", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn('if DisplayServer.get_name() == "headless":', section)
        self.assertIn("save_dialog.show()", section)
        self.assertIn("save_dialog.popup_centered()", section)
        self.assertEqual(workspace.count("_show_save_dialog()"), 3)  # definition and two entrypoints
        witness = (ROOT / "drawing/tests/object_editor_ui_smoke.gd").read_text()
        self.assertIn("app._save_and_close()", witness)
        self.assertIn("app._close_after_save and app._closing_index == app.active_tab", witness)
        self.assertIn("app.save_dialog.visible", witness)

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
