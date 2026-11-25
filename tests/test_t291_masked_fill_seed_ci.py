"""Require the real native masked-seed preflight within the existing T-068 CI gate."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from replay_godot_ci import WORKFLOW, extract_checks  # noqa: E402


class MaskedFillSeedCIContracts(unittest.TestCase):
    def test_required_fast_step_runs_native_masked_seed_oracle(self) -> None:
        checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
        self.assertEqual(len(checks), 46)
        native = next(check for check in checks if check.identifier == "ci_t068_stationary_dab_parity")
        script = native.script
        self.assertIn("res://tests/t291_masked_fill_seed_preflight.gd", script)
        self.assertIn("T291_MASKED_FILL_PASSED checks=33 failures=0", script)
        self.assertIn("check_godot_model_log.py /tmp/godot-t291-masked-fill.log", script)
        self.assertLess(script.index("t289_fill_preflight.gd"),
                        script.index("t291_masked_fill_seed_preflight.gd"))
        self.assertLess(script.index("t291_masked_fill_seed_preflight.gd"),
                        script.index("drawing_fill_verified_stage_smoke.gd"))


if __name__ == "__main__":
    unittest.main()
