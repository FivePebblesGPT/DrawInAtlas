"""T-094: local replay is faithful, auditable and never claims partial CI green."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import Check, WORKFLOW, extract_checks, revision_identity, run_checks  # noqa: E402
from report_godot_ci import expected_check_ids  # noqa: E402


def fixture(command: str) -> str:
    return (
        "      - name: Test command\n"
        "        id: ci_example\n"
        "        if: ${{ !cancelled() }}\n"
        "        continue-on-error: true\n"
        "        shell: bash\n"
        "        run: |\n"
        + "".join("          " + line + "\n" for line in command.splitlines())
    )


class LocalReplayTests(unittest.TestCase):
    def test_checked_in_inventory_extracts_all_real_commands_in_order(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        steps = extract_checks(workflow)
        self.assertEqual([step.identifier for step in steps], expected_check_ids(workflow))
        self.assertEqual(len(steps), 46)
        self.assertIn("test_t094_ci_replay.py", workflow)
        self.assertIn("python3 tests/check_explicit_types.py", steps[0].script)
        self.assertIn("godot --headless", steps[-1].script)
        self.assertIn("tools/ci_fail_late.sh", next(
            step.script for step in steps if step.identifier == "ci_t085_live_stroke_preview"))

    def test_parser_rejects_unreplayable_step_changes(self) -> None:
        valid = fixture("echo first\necho second")
        self.assertEqual(extract_checks(valid)[0].script, "echo first\necho second\n")
        for altered in (
            valid.replace("        run: |", "        uses: example/action@v1"),
            valid.replace("        shell: bash", "        shell: pwsh"),
            valid.replace("        continue-on-error: true", "        continue-on-error: false"),
            valid.replace("        if: ${{ !cancelled() }}", "        if: ${{ false }}"),
            valid.replace("echo second", "echo ${{ secrets.API_KEY }}"),
            valid + valid,
        ):
            with self.subTest(change=altered[-60:]):
                with self.assertRaises(ValueError):
                    extract_checks(altered)

    def test_partial_replay_never_reports_complete_or_passed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = run_checks([
                Check("ci_one", "first", "printf 'hello\\n'\n"),
                Check("ci_two", "second", "echo skipped\n"),
            ], root / "out", timeout_seconds=5, selected={"ci_one"}, cwd=root)
            self.assertFalse(report["complete"])
            self.assertFalse(report["passed"])
            self.assertEqual(report["checks_executed"], 1)
            self.assertIn("**missing**", (root / "out/summary.md").read_text())
            record = report["checks"][0]
            content = (root / "out" / record["log"]).read_bytes()
            self.assertEqual(hashlib.sha256(content).hexdigest(), record["log_sha256"])
            self.assertTrue(content.startswith(b"hello"))

    def test_all_commands_execute_after_failure_and_report_exact_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = run_checks([
                Check("ci_fail", "fail", "echo failed; exit 7\n"),
                Check("ci_after", "after failure", "printf 'ran'\n"),
            ], root / "results", timeout_seconds=5, cwd=root)
            self.assertTrue(result["complete"])
            self.assertFalse(result["passed"])
            self.assertEqual([r["outcome"] for r in result["checks"]], ["failure", "success"])
            self.assertEqual(result["checks"][0]["exit_code"], 7)
            self.assertEqual((root / "results/logs/ci_after.log").read_text(), "ran")

    def test_timeout_kills_process_group_and_continues_next_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = run_checks([
                Check("ci_slow", "timeout", "sleep 30 & wait\n"),
                Check("ci_after", "after timeout", "echo survived\n"),
            ], root / "result", timeout_seconds=1, cwd=root)
            self.assertEqual([r["outcome"] for r in result["checks"]], ["timeout", "success"])
            self.assertFalse(result["passed"])
            self.assertEqual((root / "result/logs/ci_after.log").read_text().strip(), "survived")

    def test_invalid_selection_does_not_create_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "not-created"
            with self.assertRaises(ValueError):
                run_checks([Check("ci_one", "one", "true\n")], target,
                           timeout_seconds=5, selected={"ci_missing"}, cwd=root)
            self.assertFalse(target.exists())

    def test_dirty_tree_cannot_impersonate_committed_candidate(self) -> None:
        head = "a" * 40
        self.assertEqual(revision_identity(head, dirty=False, expected=head,
                                           allow_dirty=False)["candidate_commit"], head)
        for expected, allow_dirty in ((None, False), (head, True)):
            with self.subTest(expected=expected, allow_dirty=allow_dirty):
                with self.assertRaisesRegex(ValueError, "dirty"):
                    revision_identity(head, dirty=True, expected=expected, allow_dirty=allow_dirty)
        exploratory = revision_identity(head, dirty=True, expected=None, allow_dirty=True)
        self.assertIsNone(exploratory["candidate_commit"])
        self.assertFalse(exploratory["working_tree_clean"])

    def test_cli_rejects_wrong_git_commit_before_execution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = subprocess.run([
                sys.executable, str(ROOT / "tools/replay_godot_ci.py"),
                "--output", str(root / "should-not-exist"),
                "--expected-commit", "0" * 40,
                "--check", "ci_04_fail_late_contract",
            ], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("differs from --expected-commit", result.stderr)
            self.assertFalse((root / "should-not-exist").exists())


if __name__ == "__main__":
    unittest.main()
