"""Required native CI witnesses that invalid bulk edits are side-effect free."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class BulkEditPreflightCIContracts(unittest.TestCase):
    def test_required_native_step_runs_bulk_preflight_fail_closed(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        step = next(check for check in checks if check.identifier == "ci_t068_stationary_dab_parity")
        self.assertIn("res://tests/t290_bulk_edit_preflight.gd", step.script)
        self.assertIn("T290_BULK_PREFLIGHT_PASSED checks=28 failures=0", step.script)
        self.assertIn(
            "check_godot_model_log.py /tmp/godot-t290-bulk-preflight.log",
            step.script,
        )
        self.assertLess(
            step.script.index("t289_fill_preflight.gd"),
            step.script.index("t290_bulk_edit_preflight.gd"),
        )


if __name__ == "__main__":
    unittest.main()
