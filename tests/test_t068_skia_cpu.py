"""Optional CPU-only Skia 144.1 pixel/format contract, isolated from production."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_skia_cpu as MODULE  # noqa: E402


class SkiaHarnessContracts(unittest.TestCase):
    def test_wrong_wheel_tag_and_digest_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wrong = Path(directory) / "wrong.whl"
            wrong.write_bytes(b"not the uploaded wheel")
            with self.assertRaisesRegex(ValueError, "Wrong Skia wheel"):
                MODULE.verify_wheel(wrong)
            forged = Path(directory) / MODULE.WHEEL_NAME
            forged.write_bytes(b"not the SHA-pinned wheel")
            with self.assertRaisesRegex(ValueError, "Unexpected Skia wheel SHA-256"):
                MODULE.verify_wheel(forged)

    def test_full_matrix_includes_zero_alpha_replace_and_all_transfer_scopes(self) -> None:
        self.assertIn("transparent_replace", [case.name for case in MODULE.SKIA_CASES])
        self.assertEqual(MODULE.SCOPES, ("direct_rgba", "premul_full", "premul_region"))
        self.assertEqual(len(MODULE.SKIA_CASES), len(MODULE.CASES) + 1)

    def test_invalid_budget_fails_without_native_runtime(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.benchmark((0,), 3)
        with self.assertRaises(ValueError):
            MODULE.benchmark((513,), 3)
        with self.assertRaises(ValueError):
            MODULE.benchmark((16,), 2)
        with self.assertRaises(ValueError):
            MODULE.randomized_parity(None, 0)
        with self.assertRaises(ValueError):
            MODULE._validate(b"", 16, (1, 1, 4, 4), (1, 2, 3, 4), "replace")
        with self.assertRaises(ValueError):
            MODULE._validate(bytes(16 * 16 * 4), 16, (15, 15, 4, 4), (1, 2, 3, 4), "replace")
        with self.assertRaises(ValueError):
            MODULE._validate(bytes(16 * 16 * 4), 16, (1, 1, 4, 4), (-1, 2, 3, 4), "replace")


class SkiaLiveContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        wheel = os.environ.get("T068_SKIA_WHEEL")
        if not wheel:
            raise unittest.SkipTest("Set T068_SKIA_WHEEL and install the optional wheel to run live Skia tests")
        MODULE.verify_wheel(Path(wheel))
        try:
            cls.skia = MODULE.SkiaCPU()
        except (ImportError, OSError) as error:
            raise AssertionError(f"Pinned Skia wheel was requested but cannot load: {error}") from error

    def test_straight_rgba_raster_matches_common_rectangle_oracle(self) -> None:
        for side in (16, 32, 64):
            for case in MODULE.SKIA_CASES:
                with self.subTest(side=side, case=case.name):
                    source = MODULE.fixture(side, case.opaque_source)
                    rect = MODULE.region(side)
                    observed, duration = self.skia.render(source, side, rect,
                                                          case.paint, case.operation)
                    oracle = MODULE.reference_output(source, side, rect,
                                                     case.paint, case.operation)
                    delta = MODULE.mismatch_counts(observed, oracle, source, side, rect)
                    self.assertEqual(delta["untouched"], 0)
                    self.assertGreaterEqual(duration, 0)
                    if case.name == "transparent_replace":
                        self.assertGreater(delta["touched"], 0)
                        self.assertGreater(delta["lost_hidden_rgb"], 0)
                    else:
                        self.assertEqual(observed, oracle)
                    self.assertEqual(source, MODULE.fixture(side, case.opaque_source))

    def test_translucent_direct_pixels_preserve_hidden_outside_and_alpha_noop(self) -> None:
        source = MODULE.fixture(32, False)
        rect = MODULE.region(32)
        for operation, paint in (("source_over", (219, 41, 87, 129)),
                                 ("source_over", (101, 223, 52, 0))):
            rendered, _ = self.skia.render(source, 32, rect, paint, operation)
            self.assertEqual(rendered, MODULE.reference_output(source, 32, rect,
                                                               paint, operation))
        self.assertEqual(self.skia.render(source, 32, rect, (101, 223, 52, 0),
                                          "source_over")[0], source)

    def test_premultiplied_scopes_report_losses_but_region_preserves_outside(self) -> None:
        source = MODULE.fixture(32, False)
        rect = (3, 4, 13, 9)  # Non-square scoped conversion must remain supported.
        paint = (219, 41, 87, 129)
        expected = MODULE.reference_output(source, 32, rect, paint, "source_over")
        direct, _ = self.skia.render(source, 32, rect, paint, "source_over", "direct_rgba")
        self.assertEqual(direct, expected)
        for scope in ("premul_full", "premul_region"):
            with self.subTest(scope=scope):
                observed, _ = self.skia.render(source, 32, rect, paint, "source_over", scope)
                mismatches = MODULE.mismatch_counts(observed, expected, source, 32, rect)
                self.assertGreater(mismatches["touched"], 0)
                if scope == "premul_full":
                    self.assertGreater(mismatches["untouched"], 0)
                else:
                    self.assertEqual(mismatches["untouched"], 0)

    def test_invalid_inputs_are_rejected_without_touching_source(self) -> None:
        source = MODULE.fixture(16, False)
        for rect, operation, scope in (
            ((-1, 1, 3, 3), "replace", "direct_rgba"),
            ((15, 15, 3, 3), "erase", "premul_full"),
            ((1, 1, 3, 3), "unknown", "direct_rgba"),
            ((1, 1, 3, 3), "replace", "invalid"),
        ):
            with self.subTest(rect=rect, operation=operation, scope=scope):
                with self.assertRaises(ValueError):
                    self.skia.render(source, 16, rect, (1, 2, 3, 4), operation, scope)
        self.assertEqual(source, MODULE.fixture(16, False))

    def test_seeded_random_vectors_and_shape_aa_have_bounded_writes(self) -> None:
        result = MODULE.randomized_parity(self.skia, samples=16, side=32)
        self.assertEqual(result["vectors"], 48)
        self.assertEqual(result["untouched_mismatched_pixels"], 0)
        # Rounding discrepancies are recorded as research findings, never accepted.
        self.assertGreaterEqual(result["direct_mismatched_pixels"], 0)
        paths = MODULE.shape_screen(self.skia, side=64, trials=3)
        self.assertEqual([x["antialias"] for x in paths], [False, True])
        self.assertEqual(paths[0]["partially_covered_alpha_pixels"], 0)
        self.assertGreater(paths[1]["partially_covered_alpha_pixels"], 0)

    def test_checked_kernel_and_three_skia_scopes(self) -> None:
        report = MODULE.benchmark((16,), 3, randomized_vectors=3)
        self.assertEqual(len(report["measurements"]), len(MODULE.SKIA_CASES) * 3)
        self.assertEqual(report["skia_python_version"], "144.1")
        self.assertTrue(all(entry["kernel_median_us"] > 0
                            for entry in report["measurements"]))
        self.assertTrue(all(entry["pixel_mismatches"]["untouched"] == 0
                            for entry in report["measurements"]
                            if entry["scope"] != "premul_full"))
        zero = [entry for entry in report["measurements"]
                if entry["operation"] == "transparent_replace"
                and entry["scope"] == "direct_rgba"]
        self.assertEqual(len(zero), 1)
        self.assertGreater(zero[0]["pixel_mismatches"]["touched"], 0)


if __name__ == "__main__":
    unittest.main()
