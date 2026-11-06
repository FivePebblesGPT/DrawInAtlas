"""T-094: hosted CI artifacts are sanitized, complete and fail closed."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from export_godot_ci_evidence import build_evidence, main, verify_evidence  # noqa: E402
from report_godot_ci import WORKFLOW, expected_check_ids  # noqa: E402

COMMIT = "a" * 40
RUN_ID = "42140327784"
ENGINE = "4.8.beta2.official.cafc17a19"
WORKFLOW_TEXT = WORKFLOW.read_text(encoding="utf-8")
IDS = expected_check_ids(WORKFLOW_TEXT)


def make_record(*, steps: dict | None = None, **overrides: object) -> dict:
    options: dict = dict(
        commit=COMMIT, run_id=RUN_ID, attempt="1", runner_os="Linux",
        godot_version=ENGINE, workflow=WORKFLOW_TEXT,
    )
    options.update(overrides)
    return build_evidence(steps if steps is not None else
                          {key: {"outcome": "success"} for key in IDS}, **options)


class HostedCIEvidenceTests(unittest.TestCase):
    def test_complete_pass_covers_all_workflow_ids_and_pinned_identity(self) -> None:
        evidence = make_record()
        self.assertEqual(evidence["expected_check_count"], 46)
        self.assertEqual(evidence["recorded_check_count"], 46)
        self.assertEqual(evidence["outcome"], "all_checks_succeeded")
        self.assertEqual(verify_evidence(evidence, workflow=WORKFLOW_TEXT,
                                         expected_commit=COMMIT, expected_run_id=RUN_ID), [])
        self.assertIn("not-owner-acceptance", evidence["kind"])

    def test_failed_original_outcome_beats_masked_success_conclusion(self) -> None:
        steps = {key: {"outcome": "success"} for key in IDS}
        steps[IDS[4]] = {"outcome": "failure", "conclusion": "success"}
        evidence = make_record(steps=steps)
        self.assertFalse(evidence["all_required_checks_succeeded"])
        self.assertEqual(evidence["checks"][4]["outcome"], "failure")
        self.assertEqual(verify_evidence(evidence, workflow=WORKFLOW_TEXT), [])

    def test_missing_skipped_and_unknown_checks_cannot_show_green(self) -> None:
        original = {key: {"outcome": "success"} for key in IDS}
        for steps in (
            {key: value for key, value in original.items() if key != IDS[0]},
            {**original, IDS[-1]: {"outcome": "skipped"}},
            {**original, "ci_unknown_token_please_do_not_export": {"outcome": "success"}},
        ):
            with self.subTest(case=list(steps)[-1]):
                evidence = make_record(steps=steps)
                self.assertFalse(evidence["all_required_checks_succeeded"])
                self.assertEqual(verify_evidence(evidence, workflow=WORKFLOW_TEXT), [])
        self.assertEqual(make_record(steps={})["recorded_check_count"], 0)

    def test_sensitive_step_outputs_never_enter_evidence(self) -> None:
        secret = "sensitive-steps-output-should-not-be-published"
        steps = {key: {"outcome": "success", "conclusion": "success",
                       "outputs": {"password": secret}} for key in IDS}
        steps["ci_unknown_token_please_do_not_export"] = {"outcome": "success", "outputs": {"token": secret}}
        steps["setup"] = {"output": secret}
        encoded = json.dumps(make_record(steps=steps))
        self.assertNotIn(secret, encoded)
        self.assertNotIn("ci_unknown_token", encoded)
        self.assertIn('"unexpected_check_count": 1', encoded)

    def test_mismatched_workflow_commit_run_engine_or_order_rejected(self) -> None:
        valid = make_record()
        for changes, fragment in (
            ({"workflow_sha256": "b" * 64}, "Workflow hash"),
            ({"candidate_commit": "b" * 40}, "Candidate commit"),
            ({"github_run_id": "10"}, "GitHub run ID"),
            ({"godot_version": "4.9.beta1.official.test"}, "Godot"),
            ({"checks": list(reversed(valid["checks"]))}, "check IDs"),
            ({"recorded_check_count": 45}, "counts"),
            ({"all_required_checks_succeeded": False}, "overall verdict"),
            ({"outcome": "failed_or_incomplete"}, "overall verdict"),
        ):
            with self.subTest(fragment=fragment):
                invalid = {**valid, **changes}
                self.assertIn(fragment, " ".join(verify_evidence(
                    invalid, workflow=WORKFLOW_TEXT,
                    expected_commit=COMMIT, expected_run_id=RUN_ID)))

    def test_ungrounded_identity_is_not_green(self) -> None:
        for key, value in (
            ("commit", None), ("commit", "not-a-sha"),
            ("run_id", "0"), ("attempt", "a"),
            ("runner_os", "maybe"), ("godot_version", "4.8.0-stable"),
        ):
            with self.subTest(key=key, value=value):
                evidence = make_record(**{key: value})
                self.assertFalse(evidence["all_required_checks_succeeded"])
                self.assertTrue(verify_evidence(evidence, workflow=WORKFLOW_TEXT))

    def test_cli_verify_downloaded_artifact_against_explicit_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            artifact = Path(temp) / "hosted.json"
            artifact.write_text(json.dumps(make_record()), encoding="utf-8")
            command = [sys.executable, str(ROOT / "tools/export_godot_ci_evidence.py"),
                       "--verify", str(artifact), "--expected-commit", COMMIT,
                       "--expected-run-id", RUN_ID]
            ok = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
            self.assertIn("not owner approval", ok.stdout)
            wrong = subprocess.run(command[:-1] + ["1111111"], text=True, capture_output=True)
            self.assertEqual(wrong.returncode, 1)
            self.assertIn("run ID mismatch", wrong.stdout)
            artifact.write_text("{" + "not json", encoding="utf-8")
            corrupt = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(corrupt.returncode, 2)

    def test_cli_export_persists_red_without_leaking_output_data(self) -> None:
        secret = "must-not-appear-in-hosted-json"
        steps = {key: {"outcome": "success", "outputs": {"token": secret}} for key in IDS}
        steps[IDS[0]]["outcome"] = "failure"
        env = {"GODOT_CI_STEPS_JSON": json.dumps(steps), "GITHUB_SHA": COMMIT,
               "GITHUB_RUN_ID": RUN_ID, "GITHUB_RUN_ATTEMPT": "2", "RUNNER_OS": "Linux"}
        with tempfile.TemporaryDirectory() as temp:
            artifact = Path(temp) / "ci-evidence.json"
            with patch.dict(os.environ, env), patch("export_godot_ci_evidence._engine_version", return_value=ENGINE):
                self.assertEqual(main(["--output", str(artifact)]), 0)
            raw = artifact.read_text(encoding="utf-8")
            self.assertNotIn(secret, raw)
            evidence = json.loads(raw)
            self.assertEqual(evidence["outcome"], "failed_or_incomplete")
            self.assertEqual(evidence["github_run_attempt"], "2")
            self.assertEqual(verify_evidence(evidence, workflow=WORKFLOW_TEXT), [])
            evidence["runner_os"] = []
            self.assertIn("Invalid runner OS", verify_evidence(evidence, workflow=WORKFLOW_TEXT))

    def test_workflow_uploads_red_and_green_artifacts_after_summary(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(workflow.count("actions/upload-artifact@v4"), 1)
        self.assertLess(workflow.index("name: Summarize CI failures"),
                        workflow.index("name: Export sanitized hosted CI evidence"))
        self.assertLess(workflow.index("name: Export sanitized hosted CI evidence"),
                        workflow.index("name: Upload hosted CI evidence"))
        self.assertIn("run: python3 tools/export_godot_ci_evidence.py --output ci-evidence/godot-fast-ci.json", workflow)
        self.assertIn("path: ci-evidence/godot-fast-ci.json", workflow)
        self.assertEqual(workflow.count("if: ${{ always() }}"), 2)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertEqual(len(IDS), 46)


if __name__ == "__main__":
    unittest.main()
