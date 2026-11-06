"""Contracts for an opt-in, pinned-source Blend2D CPU parity comparator."""

from __future__ import annotations

import ctypes
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_blend2d_cpu as MODULE  # noqa: E402


class Blend2DFormatContracts(unittest.TestCase):
    def test_roundtrip_patch_preserves_all_outside_bytes(self) -> None:
        original = MODULE.fixture(16, False)
        rect = (2, 3, 4, 4)
        cropped = MODULE.crop_rgba(original, 16, rect)
        self.assertEqual(MODULE.paste_rgba(original, 16, rect, cropped), original)
        self.assertEqual(len(cropped), 4 * 4 * 4)

    def test_patch_changes_only_selected_rows_and_columns(self) -> None:
        original = MODULE.fixture(16, False)
        rect = (7, 5, 2, 3)
        result = MODULE.paste_rgba(original, 16, rect, bytes([0, 1, 2, 3] * 6))
        self.assertEqual(result, MODULE.reference_output(original, 16, rect,
                                                         (0, 1, 2, 3), "replace"))
        self.assertEqual(MODULE.mismatch_counts(result, original, original, 16, rect)["untouched"], 0)

    def test_bad_patch_or_parameters_rejected(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.paste_rgba(bytes(16 * 16 * 4), 16, (2, 2, 4, 4), b"x")
        with self.assertRaises(ValueError):
            MODULE.benchmark(Path("unused"), trials=2)
        with self.assertRaises(ValueError):
            MODULE.benchmark(Path("unused"), sides=(513,))

    def test_source_digest_is_enforced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bad = Path(directory) / "bad.tar.gz"
            bad.write_bytes(b"not the pinned release")
            with self.assertRaisesRegex(ValueError, "Unexpected Blend2D archive"):
                MODULE.verify_archive(bad)

    def test_missing_library_refuses_to_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with self.assertRaises(FileNotFoundError):
                MODULE.compile_bridge(path, path, path)


class Blend2DLiveContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = os.environ.get("T068_BLEND2D_SOURCE")
        build = os.environ.get("T068_BLEND2D_BUILD")
        archive = os.environ.get("T068_BLEND2D_ARCHIVE")
        if not (source and build and archive):
            raise unittest.SkipTest("Set source/build/archive env to enable optional Blend2D live tests")
        MODULE.verify_archive(Path(archive))
        cls.temporary = tempfile.TemporaryDirectory(prefix="t068-blend2d-test-")
        try:
            bridge = MODULE.compile_bridge(Path(source), Path(build), Path(cls.temporary.name))
            cls.renderer = MODULE.Blend2DCPU(bridge)
            cls.bridge = bridge
        except Exception:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_opaque_exact_parity_under_both_scopes(self) -> None:
        original = MODULE.fixture(16, True)
        rect = MODULE.region(16)
        for operation in ("source_over", "replace"):
            for scope in ("full_tile", "region_only"):
                with self.subTest(operation=operation, scope=scope):
                    result, elapsed = self.renderer.render(original, 16, rect,
                                                           (219, 41, 87, 255), operation, scope)
                    self.assertEqual(result, MODULE.reference_output(original, 16, rect,
                                                                     (219, 41, 87, 255), operation))
                    self.assertGreaterEqual(elapsed, 0.0)

    def test_region_preserves_hidden_rgb_outside_but_not_translucent_parity(self) -> None:
        original = MODULE.fixture(16, False)
        rect = MODULE.region(16)
        paint = (219, 41, 87, 129)
        expected = MODULE.reference_output(original, 16, rect, paint, "source_over")
        for scope in ("full_tile", "region_only"):
            result, _ = self.renderer.render(original, 16, rect, paint, "source_over", scope)
            discrepancies = MODULE.mismatch_counts(result, expected, original, 16, rect)
            self.assertGreater(discrepancies["touched"], 0)
            if scope == "region_only":
                self.assertEqual(discrepancies["untouched"], 0)
            else:
                self.assertGreater(discrepancies["untouched"], 0)

    def test_alpha_zero_library_call_is_not_canonical_noop(self) -> None:
        original = MODULE.fixture(16, False)
        rect = MODULE.region(16)
        result, _ = self.renderer.render(original, 16, rect, (101, 223, 52, 0),
                                         "source_over", "region_only")
        discrepancy = MODULE.mismatch_counts(result, original, original, 16, rect)
        self.assertGreater(discrepancy["touched"], 0)
        self.assertEqual(discrepancy["untouched"], 0)
        # A future adapter must short-circuit this operation before any premultiplication.
        self.assertEqual(MODULE.reference_output(original, 16, rect,
                                                 (101, 223, 52, 0), "source_over"), original)

    def test_canonical_clear_and_patch_are_exact(self) -> None:
        original = MODULE.fixture(16, False)
        rect = MODULE.region(16)
        result, _ = self.renderer.render(original, 16, rect, (0, 0, 0, 0),
                                         "erase", "region_only")
        self.assertEqual(result, MODULE.reference_output(original, 16, rect,
                                                         (0, 0, 0, 0), "erase"))

    def test_native_bridge_rejects_declared_short_buffer_without_writing(self) -> None:
        payload = bytearray([1, 2, 3, 4] * 256)
        original = bytes(payload)
        raw = (ctypes.c_uint8 * len(payload)).from_buffer(payload)
        elapsed = ctypes.c_uint64(999)
        result = self.renderer._draw(raw, len(payload) - 1, 16, 0, 0, 8, 8,
                                     0xFF123456, 0, ctypes.byref(elapsed))
        self.assertEqual(result, -1)
        self.assertEqual(bytes(payload), original)
        self.assertEqual(elapsed.value, 999)

    def test_invalid_operation_or_rectangle_fails_closed(self) -> None:
        source = MODULE.fixture(16, True)
        with self.assertRaises(ValueError):
            self.renderer.render(source, 16, (15, 15, 4, 4), (1, 2, 3, 4), "replace")
        with self.assertRaises(ValueError):
            self.renderer.render(source, 16, (2, 2, 5, 4), (1, 2, 3, 4),
                                 "replace", "region_only")
        with self.assertRaises(ValueError):
            self.renderer.render(source, 16, (4, 4, 8, 8), (1, 2, 3, 4),
                                 "replace", "unknown")

    def test_benchmark_reports_scoped_losses(self) -> None:
        result = MODULE.benchmark(self.bridge, (16,), trials=3)
        self.assertEqual(len(result["measurements"]), len(MODULE.CASES) * 2)
        self.assertTrue(all(row["pixel_mismatches"]["untouched"] == 0
                            for row in result["measurements"] if row["scope"] == "region_only"))
        self.assertTrue(all(row["kernel_median_us"] > 0 for row in result["measurements"]))
        self.assertEqual(result["source_sha256"], MODULE.PINNED_SOURCE_SHA256)


if __name__ == "__main__":
    unittest.main()
