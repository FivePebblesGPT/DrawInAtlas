"""Correctness gates for the optional T-068 C++ raster-kernel candidate."""
from __future__ import annotations

import random
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "benchmarks"))
from t068_native import baseline_blend, build, call_batch, open_kernel  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
