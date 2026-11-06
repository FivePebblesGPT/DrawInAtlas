"""Regression tests for complete CI execution and final failure reporting."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "godot-check.yml"
sys.path.insert(0, str(ROOT / "tools"))
from report_godot_ci import summarize  # noqa: E402


class GodotCIFailLateTests(unittest.TestCase):
    def test_all_checks_run_even_after_earlier_failure(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        blocks = re.findall(r"(?ms)^      - name: ([^\n]+)\n(.*?)(?=^      - name: |\Z)", workflow)
        self.assertGreaterEqual(len(blocks), 20)
        # Keep push CI bounded while permitting new focused, fast model
        # witnesses (T-065 paging, T-086 cache, T-087 frame and T-088 selection).
        self.assertLessEqual(len(blocks), 44)
        self.assertIn("Verify T-086 source-space dirty-display tile invalidation", workflow)
        self.assertIn("Verify T-088 selection channel, clipboard, and transaction history", workflow)
        for name, block in blocks:
            if name.startswith(("Install Godot ", "Verify the exact beta engine")) or name == "Summarize CI failures":
                continue
            with self.subTest(name=name):
                self.assertRegex(block, r"(?m)^        id: ci_[a-z0-9_]+$")
                self.assertIn("if: ${{ !cancelled() }}", block)
                self.assertIn("continue-on-error: true", block)
        self.assertIn("GODOT_CI_STEPS_JSON: ${{ toJSON(steps) }}", workflow)
        self.assertRegex(workflow, r"(?m)^      - name: Summarize CI failures$")
        self.assertEqual(workflow.count("run: python3 tools/report_godot_ci.py"), 1)

    def test_multi_suite_steps_collect_errors(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        names = [
            "Verify T-054 Drawing/Atlas chronological history",
            "Verify T-058 editable text, font integrity and undoable rasterization",
            "Verify T-062 Object Editor source publishing, bound origin and saved variants",
            "Verify T-066 atomic sparse campaign generations, recovery and editor Save/Load",
        ]
        for name in names:
            match = re.search(r"(?ms)^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - name: |\Z)", workflow)
            self.assertIsNotNone(match, name)
            assert match is not None
            with self.subTest(name=name):
                self.assertIn("source tools/ci_fail_late.sh", match.group(1))
                self.assertIn("ci_finish", match.group(1))
                self.assertNotIn("then exit 1; fi", match.group(1))

    def test_every_godot_script_has_a_process_watchdog(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        calls = [line.strip() for line in workflow.splitlines()
                 if "godot" in line and "--script" in line]
        self.assertGreaterEqual(len(calls), 12)
        for call in calls:
            with self.subTest(command=call[:90]):
                self.assertIn("timeout --signal=TERM --kill-after=5s ", call)
                self.assertRegex(call, r"\b(?:120|240)s (?:godot|xvfb-run)\b")

    def test_fast_desktop_ci_excludes_unfinished_and_costly_suites(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for forbidden in [
            "Export Web", "Upload Web build", "build/web", "--export-release Web",
            "xvfb-run", "Run native framebuffer acceptance",
            "Verify T-058 native framebuffer glyphs", "Verify T-053 native Drawing pointer",
            "Verify retired battlemat creation paths (T-014)",
            "Verify active-layer Move gestures (T-022)",
            "Verify Line endpoints, modifiers, masks and saving (T-024)",
            "Verify polygon shape geometry, masks and persistence (T-025)",
            "Verify editable wall paths, geometry, history and native saves (T-026)",
        ]:
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, workflow)
        self.assertIn("Verify T-051 isolated Drawing contract consumer", workflow)
        self.assertIn("Verify T-055 Atlas canonical Drawing composition and input", workflow)
        self.assertIn("Verify T-078 reusable grouped dock layout model", workflow)

    def test_reporting_uses_original_outcome_not_masked_conclusion(self) -> None:
        report, ok = summarize({
            "ci_03_good": {"outcome": "success", "conclusion": "success"},
            "ci_04_bad": {"outcome": "failure", "conclusion": "success"},
            "ci_05_skipped": {"outcome": "skipped", "conclusion": "skipped"},
            "setup": {"outcome": "success"},
        })
        self.assertFalse(ok)
        self.assertIn("1/3 checks passed", report)
        self.assertIn("`ci_04_bad`", report)
        self.assertIn("`ci_05_skipped`", report)
        self.assertNotIn("`ci_03_good` |", report)
        self.assertFalse(summarize({})[1])
        self.assertTrue(summarize({"ci_03_good": {"outcome": "success"}})[1])

    def test_bash_group_continues_after_command_and_marker_failures(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["bash", "-c", """
                  source tools/ci_fail_late.sh
                  false
                  echo first_completed > "$1/first"
                  if echo 'FAILED:' | grep -q 'FAILED:'; then ci_fail_marker expected_failure; fi
                  echo second_completed > "$1/second"
                  ci_finish
                """, "ci-test", directory],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((Path(directory) / "first").read_text(), "first_completed\n")
            self.assertEqual((Path(directory) / "second").read_text(), "second_completed\n")
            self.assertIn("2 failed commands or assertions", result.stdout)


if __name__ == "__main__":
    unittest.main()
