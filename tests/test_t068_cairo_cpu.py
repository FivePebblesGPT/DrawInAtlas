"""Deterministic contracts for the opt-in Cairo CPU benchmark and pixel loss."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/benchmarks/t068_cairo_cpu.py"
SPEC = importlib.util.spec_from_file_location("t068_cairo_cpu", SOURCE)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CairoFormatContracts(unittest.TestCase):
    def test_canonical_noop_preserves_hidden_rgb(self) -> None:
        opaque = (7, 21, 83, 255)
        hidden = (17, 49, 123, 0)
        self.assertEqual(MODULE.source_over((200, 23, 19, 0), hidden), hidden)
        self.assertEqual(MODULE.source_over((200, 23, 19, 255), opaque),
                         (200, 23, 19, 255))
        self.assertEqual(MODULE.source_over((200, 23, 19, 128), (0, 0, 0, 0)),
                         (200, 23, 19, 128))

    def test_opaque_roundtrip_exact(self) -> None:
        source = MODULE.fixture(16, True)
        self.assertEqual(MODULE.premultiplied_bgra_to_rgba(
            MODULE.rgba_to_premultiplied_bgra(source)), source)

    def test_transparent_hidden_rgb_is_not_reversible(self) -> None:
        source = bytes([33, 91, 211, 0, 12, 45, 78, 255])
        premultiplied = MODULE.rgba_to_premultiplied_bgra(source)
        self.assertEqual(bytes(premultiplied), bytes([0, 0, 0, 0, 78, 45, 12, 255]))
        restored = MODULE.premultiplied_bgra_to_rgba(premultiplied)
        self.assertEqual(restored, bytes([0, 0, 0, 0, 12, 45, 78, 255]))
        self.assertNotEqual(restored, source)

    def test_mismatch_counts_separate_changed_and_untouched(self) -> None:
        original = bytes([18, 31, 42, 0] * 64)
        expected = original
        changed = bytearray(original)
        changed[0:4] = b"\x00\x00\x00\x00"  # untouched top-left, hidden RGB lost
        target = (2 * 8 + 2) * 4
        changed[target:target + 4] = b"\x00\x00\x00\x00"  # touched rectangle
        self.assertEqual(MODULE.mismatch_counts(bytes(changed), expected,
                                                 original, 8, (2, 2, 4, 4)),
                         {"touched": 1, "untouched": 1, "lost_hidden_rgb": 2})

    def test_invalid_measurement_parameters_rejected(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.fixture(2, True)
        with self.assertRaises(ValueError):
            MODULE.benchmark((8,), trials=0)
        with self.assertRaises(ValueError):
            MODULE.mismatch_counts(b"\x00" * 3, b"\x00" * 4, b"\x00" * 4, 1,
                                   (0, 0, 1, 1))


class CairoLiveContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        try:
            cls.renderer = MODULE.CairoCPU()
        except (OSError, RuntimeError) as exc:
            raise unittest.SkipTest(f"Optional Cairo runtime unavailable: {exc}") from exc

    def test_opaque_operation_matches_exact_canonical_bytes(self) -> None:
        side = 16
        source = MODULE.fixture(side, True)
        rect = MODULE.region(side)
        for operation in ("source_over", "replace"):
            with self.subTest(operation=operation):
                paint = (47, 177, 201, 255)
                result, draw_us = self.renderer.render(source, side, rect, paint, operation)
                self.assertEqual(result, MODULE.reference_output(source, side, rect,
                                                                 paint, operation))
                self.assertGreaterEqual(draw_us, 0)

    def test_alpha_zero_keeps_opaque_pixels(self) -> None:
        side = 16
        source = MODULE.fixture(side, True)
        actual, _ = self.renderer.render(source, side, MODULE.region(side),
                                         (200, 70, 11, 0), "source_over")
        self.assertEqual(actual, source)

    def test_transparent_hidden_rgb_loss_cannot_be_accepted(self) -> None:
        side = 16
        source = MODULE.fixture(side, False)
        actual, _ = self.renderer.render(source, side, MODULE.region(side),
                                         (200, 70, 11, 0), "source_over")
        lost = MODULE.mismatch_counts(actual, source, source, side, MODULE.region(side))
        self.assertGreater(lost["lost_hidden_rgb"], 0)
        self.assertGreater(lost["untouched"], 0)

    def test_bad_inputs_fail_closed(self) -> None:
        with self.assertRaises(ValueError):
            self.renderer.render(b"", 16, (1, 1, 4, 4), (1, 2, 3, 255), "replace")
        with self.assertRaises(ValueError):
            self.renderer.render(b"\x00" * 1024, 16, (15, 15, 4, 4),
                                 (1, 2, 3, 255), "replace")

    def test_checked_cpp_and_cairo_matrix_is_reproducible(self) -> None:
        result = MODULE.benchmark((8,), trials=3)
        self.assertEqual(len(result["measurements"]), len(MODULE.CASES))
        parity = {row["operation"]: row["pixel_mismatches"]
                  for row in result["measurements"]}
        self.assertEqual(parity["opaque_replace"],
                         {"touched": 0, "untouched": 0, "lost_hidden_rgb": 0})
        self.assertEqual(parity["opaque_over"],
                         {"touched": 0, "untouched": 0, "lost_hidden_rgb": 0})
        self.assertGreater(parity["translucent_over"]["untouched"], 0)
        self.assertGreater(parity["translucent_replace"]["touched"], 0)
        self.assertIn("cairo_version", result)
        self.assertTrue(all(row["kernel_median_us"] > 0 for row in result["measurements"]))


if __name__ == "__main__":
    unittest.main()
