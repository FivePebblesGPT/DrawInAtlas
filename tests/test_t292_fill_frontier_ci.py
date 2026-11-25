"""Fail-closed native frontier boundary evidence in existing required T-068 CI."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class FillFrontierCIContracts(unittest.TestCase):
    def test_required_native_step_checks_exact_boundary_witness(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        native = next(check for check in checks if check.identifier == "ci_t068_stationary_dab_parity")
        script = native.script
        self.assertIn("res://tests/t292_fill_frontier_bounds.gd", script)
        self.assertIn("T292_FRONTIER_PASSED checks=38 failures=0", script)
        self.assertIn("check_godot_model_log.py /tmp/godot-t292-fill-frontier.log", script)
        self.assertLess(script.index("t291_masked_fill_seed_preflight.gd"),
                        script.index("t292_fill_frontier_bounds.gd"))
        self.assertLess(script.index("t292_fill_frontier_bounds.gd"),
                        script.index("drawing_fill_verified_stage_smoke.gd"))


if __name__ == "__main__":
    unittest.main()
