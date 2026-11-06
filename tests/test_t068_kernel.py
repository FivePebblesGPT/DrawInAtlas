"""Correctness gates for the optional T-068 C++ raster-kernel candidate."""
from __future__ import annotations

import random
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "benchmarks"))
from t068_native import (baseline_blend, build, call_batch, call_delta_batch,
                         materialize_deltas, open_kernel)  # noqa: E402


class RasterKernelTests(unittest.TestCase):
    """Verify byte-level batch semantics before any Godot integration decision."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(prefix="t068-compile-")
        cls.library = open_kernel(build(Path(cls.directory.name)))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def test_boundary_alphas_and_hidden_rgb(self) -> None:
        rng = random.Random(68011)
        samples = [(0x00aabbcc, 0x00332211), (0x00000000, 0x00aabbcc),
                   (0xff123456, 0x00ffffff), (0x01010203, 0xfeffffff)]
        samples += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(3000)]
        for source, destination in samples:
            self.assertEqual(self.library.draw_source_over(source, destination),
                             baseline_blend(source, destination))
        self.assertEqual(self.library.draw_source_over(0x00eeeeee, 0x00abcdef), 0x00abcdef)

    def test_overlap_once_and_ordered_deltas(self) -> None:
        source = bytearray(8 * 8 * 4)
        source[:4] = bytes((0x11, 0x22, 0x33, 0))
        first = 0x80663322
        count, output, deltas = call_batch(self.library, bytes(source), 8, 8,
                                            [(0, 0), (1, 1), (0, 0), (1, 1)], first)
        self.assertEqual(count, 2)
        self.assertEqual(len(deltas), 2)
        self.assertEqual(deltas[0].before, 0x00332211)
        self.assertEqual(deltas[0].after, baseline_blend(first, 0x00332211))
        self.assertEqual(output[:4], deltas[0].after.to_bytes(4, "little"))
        self.assertEqual(output[8:12], bytes(4))
        self.assertEqual(output[36:40], deltas[1].after.to_bytes(4, "little"))
        self.assertEqual(bytes(source[:4]), bytes((0x11, 0x22, 0x33, 0)))

    def test_mask_and_erase_preserve_rejected_bytes(self) -> None:
        source = bytes((0xA5, 0x78, 0x41, 0)) * 16
        mask = bytes((1, 0, 1, 0)) * 4
        coords = [(x, y) for y in range(4) for x in range(4)]
        count, output, deltas = call_batch(self.library, source, 4, 4, coords,
                                            0x00000000, operation=1, mask=mask)
        self.assertEqual(count, 8)
        self.assertEqual(len(deltas), 8)
        for i in range(16):
            self.assertEqual(output[4 * i:4 * i + 4], bytes(4) if mask[i] else source[4 * i:4 * i + 4])

    def test_cancel_as_no_publication_and_failures_atomic(self) -> None:
        raw = bytes((0x11, 0x33, 0x55, 0xff)) * 16
        count, result, delta = call_batch(self.library, raw, 4, 4,
                                          [(0, 0), (1, 0)], 0x88552211)
        self.assertEqual(count, 2)
        self.assertNotEqual(result, raw)
        # The caller can discard detached changes without publishing them.
        self.assertEqual(raw, bytes((0x11, 0x33, 0x55, 0xff)) * 16)
        error, rejected, no_delta = call_batch(self.library, raw, 4, 4,
                                               [(0, 0), (-1, 1)], 0x88552211)
        self.assertEqual(error, -2)
        self.assertEqual(rejected, bytes(64))
        self.assertEqual(no_delta, [])
        error, rejected, no_delta = call_batch(self.library, raw, 4, 4,
                                               [(0, 0), (1, 1)], 0x88552211, capacity=1)
        self.assertEqual(error, -3)
        self.assertEqual(rejected, bytes(64))
        self.assertEqual(no_delta, [])

    def test_exact_replace_and_zero_source_alpha(self) -> None:
        raw = bytes((0x77, 0x44, 0x33, 0)) * 4
        change, output, _ = call_batch(self.library, raw, 2, 2, [(1, 1)], 0x00112233, operation=2)
        self.assertEqual(change, 1)
        self.assertEqual(output[12:16], bytes((0x33, 0x22, 0x11, 0)))
        self.assertEqual(output[:12], raw[:12])
        unchanged, output, _ = call_batch(self.library, raw, 2, 2, [(1, 1)], 0x00ffffff, operation=0)
        self.assertEqual(unchanged, 0)
        self.assertEqual(output, raw)

    def test_region_independence_and_fixed_delta_format(self) -> None:
        for size in (128, 256):
            source = bytes((0, 0, 0, 0)) * (size * size)
            count, output, deltas = call_batch(self.library, source, size, size,
                                                [(0, 0), (size - 1, size - 1)], 0xff554433)
            self.assertEqual(count, 2)
            self.assertEqual(len(deltas), 2)
            self.assertEqual(output[4:-4], source[4:-4])
            self.assertEqual([d.index for d in deltas], [0, size * size - 1])


    def test_delta_only_matches_full_region_across_all_operations(self) -> None:
        raw = bytes(((index * 29 + 3) & 255) for index in range(32 * 32 * 4))
        coords = [(x, y) for x in range(32) for y in range(32)] + [(5, 5)] * 10
        mask = bytes((int(index % 3 != 0) for index in range(32 * 32)))
        for operation in (0, 1, 2):
            full_count, full_bytes, full_deltas = call_batch(
                self.library, raw, 32, 32, coords, 0x81457712,
                operation=operation, mask=mask)
            sparse_count, sparse_deltas = call_delta_batch(
                self.library, raw, 32, 32, coords, 0x81457712,
                operation=operation, mask=mask)
            self.assertEqual(full_count, sparse_count)
            self.assertEqual([(d.index, d.before, d.after) for d in full_deltas],
                             [(d.index, d.before, d.after) for d in sparse_deltas])
            self.assertEqual(full_bytes, materialize_deltas(raw, sparse_deltas))
            self.assertEqual(raw, bytes(((i * 29 + 3) & 255) for i in range(32 * 32 * 4)))

    def test_delta_only_rejection_is_atomic_with_sentinel_memory(self) -> None:
        width = height = 8
        raw = bytes((17, 29, 37, 0)) * (width * height)
        coords = [(1, 1), (2, 2), (1, 1)]
        count, delta = call_delta_batch(self.library, raw, width, height,
                                        coords, 0x80eeaa55, capacity=1)
        self.assertEqual((count, delta), (-3, []))
        count, delta = call_delta_batch(self.library, raw, width, height,
                                        [(1, 1), (8, 7)], 0x80eeaa55)
        self.assertEqual((count, delta), (-2, []))
        # The native API must not even touch output memory on failure.
        import ctypes
        from t068_native import Delta
        src = (ctypes.c_uint8 * len(raw)).from_buffer_copy(raw)
        candidate = (ctypes.c_int32 * 4)(1, 1, 2, 2)
        sentinels = (Delta * 1)()
        sentinels[0].index = 0x12345678
        sentinels[0].before = 0xabcdef01
        sentinels[0].after = 0xfedcba98
        result = self.library.draw_batch_deltas(src, width, height, candidate, 2,
                                                 0x80eeaa55, 0, None, sentinels, 1)
        self.assertEqual(result, -3)
        self.assertEqual((sentinels[0].index, sentinels[0].before, sentinels[0].after),
                         (0x12345678, 0xabcdef01, 0xfedcba98))

    def test_delta_only_preserves_hidden_rgb_and_guards_stale_apply(self) -> None:
        src = bytes((0x89, 0xAB, 0xCD, 0)) * 16
        count, deltas = call_delta_batch(self.library, src, 4, 4,
                                          [(0, 0), (0, 0), (2, 2)], 0x00000000)
        self.assertEqual((count, deltas), (0, []))
        count, deltas = call_delta_batch(self.library, src, 4, 4,
                                          [(0, 0), (2, 2)], 0x80887766)
        self.assertEqual(count, 2)
        revised = materialize_deltas(src, deltas)
        self.assertEqual(revised[4:8], src[4:8])
        with self.assertRaisesRegex(ValueError, "stale"):
            materialize_deltas(revised, deltas)
        self.assertEqual(src, bytes((0x89, 0xAB, 0xCD, 0)) * 16)

    def test_delta_only_large_tile_bounded_memory(self) -> None:
        # This tests correctness, not an asserted speedup: a 2048-wide edit
        # returns two deltas and no region-sized output allocation.
        size = 2048
        raw = bytes((0x22, 0x44, 0x66, 0)) * (size * size)
        count, deltas = call_delta_batch(self.library, raw, size, size,
                                          [(0, 0), (size - 1, size - 1)], 0xff114477)
        self.assertEqual(count, 2)
        self.assertEqual([d.index for d in deltas], [0, size * size - 1])
        self.assertEqual(len(raw), 16 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
