"""T-068: detached native hard-brush RGBA8, failure atomicity, and evidence."""

from __future__ import annotations

import copy
import ctypes
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_scalar_rgba8 as RGBA8  # noqa: E402
from t068_cairo_cpu import fixture, source_over  # noqa: E402
from t068_scalar_hard_brush import ScalarBrush, compile_kernel, expected_mask  # noqa: E402
from t068_skia_brush import canonical_pixels  # noqa: E402


class ScalarRgba8Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory(prefix="t068-scalar-rgba8-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.brush = ScalarBrush(compile_kernel(Path(cls.temp.name)))

    def test_all_pinned_small_and_large_cases_match_pixels_and_coverage(self) -> None:
        saved = json.loads(RGBA8.EVIDENCE.read_text(encoding="utf-8"))
        RGBA8.validate(saved)
        self.assertEqual(saved["summary"], {"runs": 2, "cases_per_run": 28,
                                              "exact_coverage_and_rgba8": 56})
        cases = RGBA8.fixtures()
        self.assertEqual(len(cases), 28)
        for case in cases:
            identifier, side, source, path, width, selection, indices, paint, erase, oracle = case
            with self.subTest(identifier=identifier):
                output, coverage = self.brush.composite(
                    source, side, path, width, selection, paint, erase)
                expected = RGBA8.expected_row(case)
                self.assertEqual(output, canonical_pixels(source, indices, paint, erase))
                self.assertEqual(hashlib.sha256(output).hexdigest(), expected["output_sha256"])
                self.assertEqual(coverage, expected_mask(side, indices))
                self.assertEqual(expected["godot_output_sha256"], oracle)
                # Every out-of-coverage pixel must retain exact RGBA8 bytes,
                # even transparent RGB and unselected pixels.
                for index in (0, side - 1, side * (side - 1)):
                    if index not in indices:
                        self.assertEqual(output[index * 4:index * 4 + 4],
                                         source[index * 4:index * 4 + 4])

    def test_native_source_over_erase_noop_and_hidden_rgb(self) -> None:
        side = 8
        source = fixture(side, False)
        path = [[3.5, 3.5]]
        selection = bytes([1] * (side * side))
        for color, erase in (((219, 41, 87, 129), False),
                             ((0, 0, 0, 0), True),
                             ((255, 127, 17, 0), False)):
            with self.subTest(color=color, erase=erase):
                output, coverage = self.brush.composite(source, side, path, 4.0,
                                                         selection, color, erase)
                touched = {i for i, value in enumerate(coverage) if value == 255}
                self.assertTrue(touched)
                expected = bytearray(source)
                for index in touched:
                    offset = index * 4
                    old = tuple(source[offset:offset + 4])
                    expected[offset:offset + 4] = bytes((0, 0, 0, 0) if erase
                                                        else source_over(color, old))
                self.assertEqual(output, bytes(expected))
                if color[3] == 0 and not erase:
                    self.assertEqual(output, source)
                self.assertEqual(source, fixture(side, False))

    def test_atomic_rejection_of_malformed_input_and_all_output_aliases(self) -> None:
        fn = self.brush.composite_function
        original = (ctypes.c_uint8 * 256)(*range(256))
        output = (ctypes.c_uint8 * 256)(*([0xB2] * 256))
        coverage = (ctypes.c_uint8 * 64)(*([0xA5] * 64))
        selection = (ctypes.c_uint8 * 64)(*([1] * 64))
        invalid_mask = (ctypes.c_uint8 * 64)(*([2] * 64))
        points = (ctypes.c_double * 2)(4.0, 4.0)
        paint = (ctypes.c_uint8 * 4)(219, 41, 87, 129)

        def call(**overrides: object) -> int:
            args: dict[str, object] = dict(
                output=output, output_bytes=256, coverage=coverage, coverage_bytes=64,
                source=original, source_bytes=256, selection=selection,
                selection_bytes=64, side=8, points=points,
                point_bytes=16, point_count=1, width=4.0,
                paint=paint, paint_bytes=4, erase=0)
            args.update(overrides)
            return fn(*(args[k] for k in (
                "output", "output_bytes", "coverage", "coverage_bytes",
                "source", "source_bytes", "selection", "selection_bytes",
                "side", "points", "point_bytes", "point_count", "width",
                "paint", "paint_bytes", "erase")))

        errors = (
            ({"output_bytes": 255}, -1), ({"coverage_bytes": 63}, -1),
            ({"source_bytes": 255}, -1), ({"selection_bytes": 63}, -1),
            ({"paint_bytes": 3}, -1), ({"erase": 2}, -1),
            ({"point_bytes": 15}, -1), ({"point_count": 0}, -1),
            ({"width": math.inf}, -1), ({"width": 0.0}, -1),
            ({"selection": invalid_mask}, -3),
            ({"output": original}, -1), ({"output": selection}, -1),
            ({"output": paint}, -1), ({"output": points}, -1),
            ({"coverage": original}, -1), ({"coverage": selection}, -1),
            ({"coverage": paint}, -1), ({"coverage": points}, -1),
            ({"output": coverage}, -1), ({"source": output}, -1),
            ({"paint": output}, -1), ({"points": output}, -1),
            ({"selection": output}, -1), ({"selection": coverage}, -1),
            ({"paint": coverage}, -1), ({"points": coverage}, -1),
        )
        for modifications, error in errors:
            with self.subTest(modifications=modifications):
                output[:] = [0xB2] * 256
                coverage[:] = [0xA5] * 64
                self.assertEqual(call(**modifications), error)
                # Except where a test explicitly points an output into a
                # separate input buffer, both official outputs stay untouched.
                self.assertEqual(bytes(output), bytes([0xB2] * 256))
                self.assertEqual(bytes(coverage), bytes([0xA5] * 64))
        self.assertEqual(bytes(original), bytes(range(256)))
        self.assertEqual(bytes(selection), bytes([1] * 64))
        self.assertEqual(bytes(paint), bytes([219, 41, 87, 129]))

    def test_evidence_tampering_is_rejected(self) -> None:
        saved = json.loads(RGBA8.EVIDENCE.read_text(encoding="utf-8"))
        changes = (
            lambda p: p["runs"].pop(),
            lambda p: p["runs"][1].pop(),
            lambda p: p["runs"][0][0].update(output_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(source_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(changed_pixels=99),
            lambda p: p["runs"][0][0].update(coverage_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(godot_output_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(selection_sha256="0" * 64),
            lambda p: p["runs"][0].reverse(),
            lambda p: p["summary"].update(exact_coverage_and_rgba8=55),
            lambda p: p.update(native_source_sha256="0" * 64),
        )
        for mutate in changes:
            candidate = copy.deepcopy(saved)
            mutate(candidate)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                RGBA8.validate(candidate)

    def test_two_run_evidence_reproduces_exactly(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-scalar-rgba8-result-") as folder:
            output = Path(folder) / "evidence.json"
            command = [sys.executable, str(ROOT / "tools/benchmarks/t068_scalar_rgba8.py"),
                       "--output", str(output)]
            done = subprocess.run(command, capture_output=True, text=True,
                                  timeout=150, check=False)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("T068_SCALAR_RGBA8_PASSED: 56", done.stdout)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")),
                             json.loads(RGBA8.EVIDENCE.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
