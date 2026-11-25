"""T-106: current regeneration must not soften the beta2 source-byte oracle."""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from t068_oracle_engine_compat import (
    BRUSH_NATIVE_ANCHORS,
    require_current_engine_matches_pinned_beta2,
    require_native_brush_matches_pinned_beta2,
)

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = (
    "t068_quad_scope_oracle.json",
    "t068_quad_differential_oracle.json",
    "t068_quad_stress_oracle.json",
    "t068_skia_brush_oracle.json",
)


class EngineCompatibilityTests(unittest.TestCase):
    def test_only_pinned_engine_version_label_may_change(self) -> None:
        for name in FIXTURES:
            with self.subTest(fixture=name):
                pinned = json.loads((ROOT / "tools/benchmarks" / name).read_text())
                self.assertEqual(pinned["godot_version"], "4.8-beta2 (official)")
                regenerated = {**pinned, "godot_version": "4.8-beta4 (official)"}
                require_current_engine_matches_pinned_beta2(pinned, regenerated)
                for mutation in (
                    lambda p: p.update(godot_version="4.8-beta2 (official)"),
                    lambda p: p.update(godot_version="4.8-beta3 (official)"),
                    lambda p: p.update(unexpected=True),
                    lambda p: p.pop("cases"),
                    lambda p: p["cases"].reverse(),
                    lambda p: p["cases"][0].update(id="replaced"),
                ):
                    changed = copy.deepcopy(regenerated)
                    mutation(changed)
                    with self.assertRaises(AssertionError):
                        require_current_engine_matches_pinned_beta2(pinned, changed)
                altered_pinned = copy.deepcopy(pinned)
                altered_pinned["godot_version"] = "4.8-beta4 (official)"
                with self.assertRaises(AssertionError):
                    require_current_engine_matches_pinned_beta2(altered_pinned, regenerated)

    def test_native_brush_relocation_preserves_every_historical_pixel(self) -> None:
        pinned = json.loads((ROOT / "tools/benchmarks/t068_skia_brush_oracle.json").read_text())
        live = copy.deepcopy(pinned)
        live["godot_version"] = "4.8-beta4 (official)"
        live["anchor_x"], live["anchor_y"] = BRUSH_NATIVE_ANCHORS
        require_native_brush_matches_pinned_beta2(pinned, live)

        for mutation in (
            lambda value: value.update(anchor_x="9007199254740993"),
            lambda value: value.update(anchor_y="-1125899906842624"),
            lambda value: value.update(anchor_x="1125899906842626"),
            lambda value: value["cases"][0]["changed_indices"].pop(),
            lambda value: value["cases"][0].update(after_sha256="0" * 64),
            lambda value: value["cases"][0]["coverage_indices"].pop(),
            lambda value: value["cases"].reverse(),
        ):
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(live)
                mutation(changed)
                with self.assertRaises(AssertionError):
                    require_native_brush_matches_pinned_beta2(pinned, changed)

        altered_pinned = copy.deepcopy(pinned)
        altered_pinned["anchor_y"] = "-9007199254740992"
        with self.assertRaises(AssertionError):
            require_native_brush_matches_pinned_beta2(altered_pinned, live)


if __name__ == "__main__":
    unittest.main()
