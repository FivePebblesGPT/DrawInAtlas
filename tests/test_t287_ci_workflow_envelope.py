"""T-287: local replay must not attest unmodeled workflow/job settings."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class ReplayWorkflowEnvelopeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_current_workflow_remains_replayable(self) -> None:
        steps = extract_checks(self.workflow)
        self.assertEqual(len(steps), 46)
        self.assertEqual(steps[0].identifier, "ci_02_enforce_explicit_types_in_owned_gdscript_and_skill_examples")

    def test_unmodeled_root_and_job_execution_configuration_is_rejected(self) -> None:
        original = self.workflow
        mutations = {
            "root environment": original.replace("jobs:\n", "env:\n  GODOT: /tmp/other-godot\njobs:\n", 1),
            "root defaults": original.replace("jobs:\n", "defaults:\n  run:\n    shell: pwsh\njobs:\n", 1),
            "root permissions": original.replace("jobs:\n", "permissions: read-all\njobs:\n", 1),
            "root concurrency": original.replace("jobs:\n", "concurrency: global-lock\njobs:\n", 1),
            "other event": original.replace("  pull_request:\n", "  pull_request:\n  workflow_dispatch:\n", 1),
            "noncanonical event filter indent": original.replace("  pull_request:\n", "  pull_request:\n   branches: [main]\n", 1),
            "event filters": original.replace("  pull_request:\n", "  pull_request:\n    branches: [main]\n", 1),
            "noncanonical job indent": original.replace("    steps:\n", "     env: inline\n    steps:\n", 1),
            "job environment": original.replace("    steps:\n", "    env:\n      GODOT: /tmp/other-godot\n    steps:\n", 1),
            "job defaults": original.replace("    steps:\n", "    defaults:\n      run:\n        working-directory: drawing\n    steps:\n", 1),
            "job container": original.replace("    steps:\n", "    container: ubuntu:latest\n    steps:\n", 1),
            "job matrix": original.replace("    steps:\n", "    strategy:\n      matrix:\n        os: [ubuntu, windows]\n    steps:\n", 1),
            "job timeout": original.replace("    steps:\n", "    timeout-minutes: 20\n    steps:\n", 1),
            "job condition": original.replace("    steps:\n", "    if: ${{ false }}\n    steps:\n", 1),
            "different runner": original.replace("runs-on: ubuntu-latest", "runs-on: windows-latest", 1),
            "duplicated runner": original.replace("    steps:\n", "    runs-on: ubuntu-latest\n    steps:\n", 1),
            "second job": original + "\n  unrelated:\n    runs-on: windows-latest\n    steps: []\n",
        }
        for label, altered in mutations.items():
            with self.subTest(label=label):
                self.assertNotEqual(altered, original)
                with self.assertRaises(ValueError):
                    extract_checks(altered)

    def test_noop_comments_and_step_only_unit_fixtures_work(self) -> None:
        modified = self.workflow.replace(
            "    runs-on: ubuntu-latest\n",
            "    # The runner label is deliberately checked by local replay.\n"
            "    runs-on: ubuntu-latest\n",
            1,
        )
        self.assertEqual(extract_checks(modified), extract_checks(self.workflow))
        renamed = self.workflow.replace("name: Godot GDScript checks (fast desktop)",
                                        "name: Drawing fast checks", 1)
        self.assertEqual(extract_checks(renamed), extract_checks(self.workflow))
        minimal = (
            "      - name: Synthetic\n"
            "        id: ci_synthetic\n"
            "        if: ${{ !cancelled() }}\n"
            "        continue-on-error: true\n"
            "        run: echo okay\n"
        )
        self.assertEqual(extract_checks(minimal)[0].script, "echo okay\n")


if __name__ == "__main__":
    unittest.main()
