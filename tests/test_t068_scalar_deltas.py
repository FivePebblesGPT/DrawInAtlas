"""T-068: scalar native sparse RGBA8 wire, parity and atomic failure paths."""
from __future__ import annotations

import copy
import ctypes
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_scalar_deltas as SPARSE  # noqa: E402
from t068_scalar_hard_brush import ScalarBrush, compile_kernel  # noqa: E402
from t068_scalar_rgba8 import fixtures  # noqa: E402
from t068_skia_brush import canonical_pixels  # noqa: E402


class ScalarDeltaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory(prefix="t068-scalar-deltas-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.brush = ScalarBrush(compile_kernel(Path(cls.temp.name)))

    def test_real_godot_and_large_oracle_cases_reconstruct_exact_bytes(self) -> None:
        evidence = json.loads(SPARSE.EVIDENCE.read_text(encoding="utf-8"))
        SPARSE.validate(evidence)
        self.assertEqual(evidence["summary"]["exact_sparse_rgba8"], 56)
        self.assertEqual(len(evidence["runs"][0]), 28)
        for case, row in zip(fixtures(), evidence["runs"][0], strict=True):
            identifier, side, source, path, width, selection, indices, paint, erase, oracle = case
            with self.subTest(identifier=identifier):
                wire = self.brush.deltas(source, side, path, width, selection,
                                         paint, erase, max_changes=min(65536, side * side))
                reference_row, reference_wire = SPARSE.reference(case)
                self.assertEqual(wire, reference_wire)
                self.assertEqual(row, reference_row)
                self.assertEqual(SPARSE.reconstruct(source, wire),
                                 canonical_pixels(source, indices, paint, erase))
                self.assertEqual(row["oracle"], "godot_pixels" if oracle is not None
                                 else "godot_coverage_python_rgba8")
                self.assertEqual(len(wire), 4 + row["changed_pixels"] * 12)
        no_op = next(row for row in evidence["runs"][0]
                     if row["id"] == "large/2048/transparent_noop")
        self.assertEqual((no_op["payload_bytes"], no_op["full_tile_bytes"]), (4, 16777216))
        sparse = next(row for row in evidence["runs"][0]
                      if row["id"] == "large/2048/hard4_long")
        self.assertEqual((sparse["changed_pixels"], sparse["payload_bytes"]), (460, 5524))

    def test_zero_capacity_and_dense_capacity_fail_without_writes(self) -> None:
        side = 8
        source = bytes([33, 44, 55, 77] * (side * side))
        selection = bytes([1] * (side * side))
        path = [[4.0, 4.0]]
        color = (250, 61, 75, 201)
        with self.assertRaises(BufferError):
            self.brush.deltas(source, side, path, 12.0, selection, color, False,
                              max_changes=0)
        full = self.brush.deltas(source, side, path, 12.0, selection, color, False,
                                 max_changes=side * side)
        self.assertGreater(struct.unpack_from("<I", full)[0], 0)
        self.assertEqual(SPARSE.reconstruct(source, full),
                         self.brush.composite(source, side, path, 12.0,
                                              selection, color, False)[0])
        no_op = self.brush.deltas(source, side, path, 12.0, selection,
                                  (1, 2, 3, 0), False, max_changes=0)
        self.assertEqual(no_op, b"\x00\x00\x00\x00")
        self.assertEqual(SPARSE.reconstruct(source, no_op), source)

    def test_native_rejection_is_atomic_even_with_partial_valid_changes(self) -> None:
        fn = self.brush.delta_function
        side = 8
        payload = (ctypes.c_uint8 * 772)(*([0xA7] * 772))
        original = (ctypes.c_uint8 * 256)(*([19, 27, 45, 86] * 64))
        selection = (ctypes.c_uint8 * 64)(*([1] * 64))
        invalid_selection = (ctypes.c_uint8 * 64)(*([1] * 63 + [2]))
        path = (ctypes.c_double * 2)(4.0, 4.0)
        bad_path = (ctypes.c_double * 2)(math.nan, 4.0)
        color = (ctypes.c_uint8 * 4)(201, 91, 51, 191)

        def check(**kw: object) -> int:
            settings = dict(payload=payload, capacity=772, source=original,
                            source_bytes=256, selection=selection,
                            selection_bytes=64, side=8, points=path,
                            point_bytes=16, point_count=1, width=12.0,
                            paint=color, paint_bytes=4, erase=0)
            settings.update(kw)
            return fn(*(settings[k] for k in (
                "payload", "capacity", "source", "source_bytes",
                "selection", "selection_bytes", "side", "points",
                "point_bytes", "point_count", "width", "paint",
                "paint_bytes", "erase")))

        errors = (
            ({"capacity": 4}, -5), ({"capacity": 3}, -1),
            ({"capacity": 773}, -1), ({"source_bytes": 255}, -1),
            ({"selection_bytes": 63}, -1), ({"point_bytes": 15}, -1),
            ({"paint_bytes": 3}, -1), ({"point_count": 0}, -1),
            ({"width": math.nan}, -1), ({"width": 0.0}, -1),
            ({"erase": 2}, -1), ({"selection": invalid_selection}, -3),
            ({"points": bad_path}, -1), ({"payload": original}, -1),
            ({"payload": selection}, -1), ({"payload": path}, -1),
            ({"payload": color}, -1),
        )
        for params, expected_code in errors:
            with self.subTest(params=params):
                payload[:] = [0xA7] * 772
                self.assertEqual(check(**params), expected_code)
                self.assertEqual(bytes(payload), bytes([0xA7] * 772))
                self.assertEqual(bytes(original), bytes([19, 27, 45, 86] * 64))
                self.assertEqual(bytes(selection), bytes([1] * 64))
        # A generously sized payload must not write past its actual record end.
        self.assertGreater(check(), 0)
        used = 4 + struct.unpack_from("<I", payload)[0] * 12
        self.assertEqual(bytes(payload[used:]), bytes([0xA7] * (772 - used)))

    def test_decoder_rejects_truncation_stale_and_unsorted_records(self) -> None:
        source = bytes([1, 2, 3, 4] * 4)
        wire = struct.pack("<I", 2)
        wire += struct.pack("<I", 1) + bytes([1, 2, 3, 4, 5, 6, 7, 8])
        wire += struct.pack("<I", 2) + bytes([1, 2, 3, 4, 9, 10, 11, 12])
        self.assertEqual(SPARSE.reconstruct(source, wire)[4:12],
                         bytes([5, 6, 7, 8, 9, 10, 11, 12]))
        invalid = [wire[:2], wire[:-1],
                   wire[:4] + wire[16:28] + wire[4:16],
                   wire[:4] + wire[4:16] * 2,
                   wire[:4] + struct.pack("<I", 4) + wire[8:],
                   wire[:8] + b"bad!" + wire[12:]]
        for bad in invalid:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                SPARSE.reconstruct(source, bad)

    def test_saved_evidence_rejects_tampered_rows_and_transfer_claims(self) -> None:
        original = json.loads(SPARSE.EVIDENCE.read_text(encoding="utf-8"))
        invalid = (
            lambda p: p["runs"].pop(),
            lambda p: p["runs"][0].pop(),
            lambda p: p["runs"][0][0].update(payload_sha256="0" * 64),
            lambda p: p["runs"][1][0].update(payload_bytes=99),
            lambda p: p["runs"][0][0].update(changed_pixels=0),
            lambda p: p["runs"][0][0].update(transfer_bytes_avoided=42),
            lambda p: p["runs"][0].reverse(),
            lambda p: p["summary"].update(total_payload_bytes_per_run=0),
            lambda p: p.update(native_source_sha256="0" * 64),
            lambda p: p.update(max_changed_pixels=1),
        )
        for mutate in invalid:
            payload = copy.deepcopy(original)
            mutate(payload)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                SPARSE.validate(payload)

    def test_two_run_evidence_reproduces_exactly(self) -> None:
        with tempfile.TemporaryDirectory(prefix="t068-scalar-deltas-replay-") as folder:
            output = Path(folder) / "sparse.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/benchmarks/t068_scalar_deltas.py"),
                 "--output", str(output)], capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("T068_SCALAR_DELTAS_PASSED: 56", result.stdout)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")),
                             json.loads(SPARSE.EVIDENCE.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
