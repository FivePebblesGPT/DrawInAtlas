"""T-286: reject workflow metadata that local Bash replay cannot reproduce."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


def step(*, script: str = "printf 'okay\\n'", extra: str = "") -> str:
    return (
        "      - name: Test check\n"
        "        id: ci_example\n"
        "        if: ${{ !cancelled() }}\n"
        "        continue-on-error: true\n"
        "        shell: bash\n"
        + extra
        + "        run: |\n"
        + f"          {script}\n"
    )


class StrictReplayStepMetadata(unittest.TestCase):
    def test_real_workflow_still_replays_46_checks_without_changes(self) -> None:
        self.assertEqual(len(extract_checks(WORKFLOW.read_text(encoding="utf-8"))), 46)

    def test_changes_to_execution_semantics_are_rejected(self) -> None:
        for metadata in (
            "        working-directory: drawing\n",
            "        timeout-minutes: 15\n",
            "        env:\n          GODOT: /tmp/unverified-godot\n",
            "        defaults:\n          run:\n            working-directory: drawing\n",
            "        shell: pwsh\n",
            "        if: ${{ false }}\n",
            "        continue-on-error: false\n",
            "        run: echo unexpected\n",
            "        id: ci_other\n",
            "        strategy: {}\n",
        ):
            with self.subTest(metadata=metadata):
                with self.assertRaises(ValueError):
                    extract_checks(step(extra=metadata))

    def test_unknown_step_level_construct_fails_closed(self) -> None:
        for metadata in ("        <<: *shared\n", "        ? ambiguous\n"):
            with self.subTest(metadata=metadata):
                with self.assertRaises(ValueError):
                    extract_checks(step(extra=metadata))

    def test_optional_bash_shell_and_ordinary_step_comments_remain_allowed(self) -> None:
        explicit = step(extra="        # Nonsemantic note\n")
        implicit = explicit.replace("        shell: bash\n", "")
        self.assertEqual(extract_checks(explicit)[0].script, "printf 'okay\\n'\n")
        self.assertEqual(extract_checks(implicit)[0].script, "printf 'okay\\n'\n")


if __name__ == "__main__":
    unittest.main()
