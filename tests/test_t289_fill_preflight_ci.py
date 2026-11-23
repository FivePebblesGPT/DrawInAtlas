"""Required native fast-CI coverage for the invalid flood-fill preflight."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class FillPreflightCIContracts(unittest.TestCase):
    def test_required_step_keeps_native_smoke_and_fail_closed_log(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        step = next(check for check in checks if check.identifier == "ci_t068_stationary_dab_parity")
        self.assertIn("res://tests/t289_fill_preflight.gd", step.script)
        self.assertIn("T289_FILL_PREFLIGHT_PASSED checks=23 failures=0", step.script)
        self.assertIn("check_godot_model_log.py /tmp/godot-t289-fill-preflight.log", step.script)
        self.assertLess(step.script.index("drawing_fill_frontier_smoke.gd"),
                        step.script.index("t289_fill_preflight.gd"))



if __name__ == "__main__":
    unittest.main()
