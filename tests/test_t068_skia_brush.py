"""T-068 Skia brush-contract checks; ordinary CI does not need Skia installed."""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_skia_brush as BRUSH  # noqa: E402
import t068_skia_cpu as SKIA  # noqa: E402


class BrushFixtureContracts(unittest.TestCase):
    def setUp(self) -> None:
        self.side, self.source, self.cases = BRUSH.load_oracle()

    def test_real_godot_fixture_is_independently_rgba8_exact(self) -> None:
        self.assertEqual(self.side, 32)
        self.assertEqual(len(self.cases), 11)
        self.assertTrue(any(c["selection"] == "sparse" for c in self.cases))
        self.assertTrue(any(c["selection"] == "inverted" for c in self.cases))
        self.assertTrue(any(c["erase"] for c in self.cases))
        self.assertTrue(any(c["paint"][3] == 0 for c in self.cases))
        for case in self.cases:
            with self.subTest(case=case["id"]):
                output = BRUSH.canonical_pixels(self.source, set(case["coverage_indices"]),
                                                tuple(case["paint"]), case["erase"])
                self.assertEqual(BRUSH._sha(output), case["after_sha256"])
                self.assertTrue(all(BRUSH._allowed(i, self.side, case["selection"])
                                    for i in case["coverage_indices"]))

    def test_unsigned_or_aliasing_anchor_is_not_accepted(self) -> None:
        payload = json.loads(BRUSH.ORACLE_FILE.read_text())
        payload["anchor_x"] = "9007199254740992"  # Loses the far-signed +1 bit.
        with self.assertRaisesRegex(ValueError, "signed anchor"):
            self._load_mutated(payload)

    def test_fixture_rejects_corrupt_sha_coverage_and_changes(self) -> None:
        payload = json.loads(BRUSH.ORACLE_FILE.read_text())
        with self.subTest("digest"):
            mutated = copy.deepcopy(payload)
            mutated["cases"][0]["after_sha256"] = "0" * 64
            with self.assertRaisesRegex(ValueError, "oracle disagrees"):
                self._load_mutated(mutated)
        with self.subTest("duplicate"):
            mutated = copy.deepcopy(payload)
            case = mutated["cases"][0]
            case["coverage_indices"].append(case["coverage_indices"][0])
            with self.assertRaisesRegex(ValueError, "pixel index"):
                self._load_mutated(mutated)
        with self.subTest("scope"):
            mutated = copy.deepcopy(payload)
            case = next(c for c in mutated["cases"] if c["id"] == "sparse_selection")
            case["coverage_indices"].append(31 * 32 + 31)
            with self.assertRaisesRegex(ValueError, "selected area"):
                self._load_mutated(mutated)
        with self.subTest("no_op"):
            mutated = copy.deepcopy(payload)
            next(c for c in mutated["cases"] if c["id"] == "zero_alpha_noop")["changed_indices"] = [1]
            with self.assertRaisesRegex(ValueError, "oracle disagrees"):
                self._load_mutated(mutated)

    def test_continuous_and_batched_brush_are_identical(self) -> None:
        cases = {case["id"]: case for case in self.cases}
        a = cases["self_crossing"]
        b = cases["self_crossing_batched"]
        for key in ("path", "paint", "after_sha256", "coverage_indices", "changed_indices"):
            self.assertEqual(a[key], b[key])
        self.assertGreater(len(cases["zero_alpha_noop"]["coverage_indices"]), 100)
        self.assertEqual(cases["zero_alpha_noop"]["changed_indices"], [])

    def test_godot_regenerates_exact_pinned_oracle_when_available(self) -> None:
        godot = os.environ.get("T068_GODOT")
        if not godot:
            self.skipTest("Set T068_GODOT to reproduce the fixture from the real DrawingEditSession")
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "regenerated.json"
            process = subprocess.run(
                [godot, "--headless", "--path", str(ROOT), "--script",
                 "res://tests/drawing_t068_skia_brush_oracle.gd", "--", str(destination)],
                capture_output=True, text=True, timeout=120, check=False,
            )
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertIn("T068_SKIA_BRUSH_ORACLE_PASSED: 11", process.stdout)
            self.assertEqual(json.loads(destination.read_text()),
                             json.loads(BRUSH.ORACLE_FILE.read_text()))

    def test_mask_predicates_cover_rect_sparse_and_inverted(self) -> None:
        inside = 12 * self.side + 12
        outside = 3 * self.side + 3
        self.assertTrue(BRUSH._allowed(inside, self.side, "rect"))
        self.assertTrue(BRUSH._allowed(inside, self.side, "sparse"))
        self.assertFalse(BRUSH._allowed(inside, self.side, "inverted"))
        self.assertFalse(BRUSH._allowed(outside, self.side, "rect"))
        self.assertTrue(BRUSH._allowed(outside, self.side, "inverted"))
        with self.assertRaises(ValueError):
            BRUSH._allowed(inside, self.side, "unknown")

    def test_screen_budget_validation_does_not_load_optional_skia(self) -> None:
        for invalid in (0, -1, 51):
            with self.subTest(trials=invalid), self.assertRaisesRegex(ValueError, "trial count"):
                BRUSH.screen(None, invalid)
        self.assertEqual(BRUSH._pixel_mismatch(b"abcd", b"abce"), 1)
        with self.assertRaises(ValueError):
            BRUSH._pixel_mismatch(b"abcd", b"abc")

    @staticmethod
    def _load_mutated(payload: dict) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.json"
            path.write_text(json.dumps(payload))
            BRUSH.load_oracle(path)


class BrushSkiaLiveContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        wheel = os.environ.get("T068_SKIA_WHEEL")
        if not wheel:
            raise unittest.SkipTest("Live Skia wheel is opt-in; ordinary CI validates fixture contracts")
        SKIA.verify_wheel(Path(wheel))
        cls.renderer = SKIA.SkiaCPU()

    def test_hard_coverage_has_documented_one_pixel_crossing_counterexample(self) -> None:
        report = BRUSH.screen(self.renderer, trials=3)
        cases = {c["id"]: c for c in report["cases"]}
        self.assertEqual(len(cases), 11)
        for name in ("stationary_dab", "horizontal_fractional", "vertical_reverse", "diagonal",
                     "rect_selection", "sparse_selection", "inverted_selection", "erase_hidden_rgb"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["missing_godot_coverage"], 0)
                self.assertEqual(cases[name]["extra_skia_coverage"], 0)
                self.assertEqual(cases[name]["direct_rgba8_mismatched_pixels"], 0)
        for name in ("self_crossing", "self_crossing_batched", "zero_alpha_noop"):
            with self.subTest(name=name):
                self.assertEqual(cases[name]["missing_godot_coverage"], 1)
                self.assertEqual(cases[name]["extra_skia_coverage"], 0)
        self.assertEqual(cases["self_crossing"]["direct_rgba8_mismatched_pixels"], 1)
        self.assertEqual(cases["zero_alpha_noop"]["direct_rgba8_mismatched_pixels"], 0)

    def test_independent_coverage_mask_and_direct_rgba_are_deterministic(self) -> None:
        side, source, cases = BRUSH.load_oracle()
        case = next(c for c in cases if c["id"] == "self_crossing")
        first, duration = BRUSH.skia_coverage(self.renderer, side, case)
        second, _ = BRUSH.skia_coverage(self.renderer, side, case)
        direct, direct_us = BRUSH.skia_direct(self.renderer, source, side, case)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 300)
        self.assertGreaterEqual(duration, 0)
        self.assertGreaterEqual(direct_us, 0)
        self.assertEqual(len(direct), len(source))
        self.assertGreater(BRUSH._pixel_mismatch(direct, source), 0)


if __name__ == "__main__":
    unittest.main()
