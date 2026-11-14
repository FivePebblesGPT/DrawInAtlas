"""T-106: beta3 regeneration must not soften the beta2 source-byte oracle."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from t068_oracle_engine_compat import require_beta3_matches_pinned_beta2

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = (
    "t068_quad_scope_oracle.json",
    "t068_quad_differential_oracle.json",
    "t068_quad_stress_oracle.json",
    "t068_skia_brush_oracle.json",
)


class EngineCompatibilityTests(unittest.TestCase):
    def test_only_known_beta3_version_label_may_change(self) -> None:
        for name in FIXTURES:
            with self.subTest(fixture=name):
                pinned = json.loads((ROOT / "tools/benchmarks" / name).read_text())
                self.assertEqual(pinned["godot_version"], "4.8-beta2 (official)")
                regenerated = {**pinned, "godot_version": "4.8-beta3 (official)"}
                require_beta3_matches_pinned_beta2(pinned, regenerated)
                for mutation in (
                    lambda p: p.update(godot_version="4.8-beta2 (official)"),
                    lambda p: p.update(godot_version="4.8-beta4 (official)"),
                    lambda p: p.update(unexpected=True),
                    lambda p: p.pop("cases"),
                    lambda p: p["cases"].reverse(),
                    lambda p: p["cases"][0].update(id="replaced"),
                ):
                    changed = copy.deepcopy(regenerated)
                    mutation(changed)
                    with self.assertRaises(AssertionError):
                        require_beta3_matches_pinned_beta2(pinned, changed)
                altered_pinned = copy.deepcopy(pinned)
                altered_pinned["godot_version"] = "4.8-beta3 (official)"
                with self.assertRaises(AssertionError):
                    require_beta3_matches_pinned_beta2(altered_pinned, regenerated)


if __name__ == "__main__":
    unittest.main()
