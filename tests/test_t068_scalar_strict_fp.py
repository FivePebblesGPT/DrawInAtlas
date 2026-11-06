"""T-068 detached scalar ABI must reject fast-math and invalid NaN inputs."""
from __future__ import annotations

import ctypes
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/benchmarks/t068_scalar_hard_brush.cpp'
FLAGS = ('-std=c++17', '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror')
GUARD = 'T-068 scalar brush requires strict floating-point semantics'


class ScalarStrictFpContracts(unittest.TestCase):
    def test_fast_math_is_rejected_at_compile_time(self) -> None:
        text = SOURCE.read_text(encoding='utf-8')
        self.assertIn('#if defined(__FAST_MATH__)', text)
        self.assertIn(GUARD, text)
        for compiler, optimization in (('g++', '-Ofast'), ('clang++', '-O3 -ffast-math')):
            self.assertIsNotNone(shutil.which(compiler), f'{compiler} required for T-068 compiler check')
            with self.subTest(compiler=compiler):
                with tempfile.TemporaryDirectory(prefix='t068-scalar-strict-') as temp:
                    command = [compiler, *FLAGS, *optimization.split(), str(SOURCE),
                               '-o', str(Path(temp) / 'rejected.so')]
                    result = subprocess.run(command, capture_output=True, text=True,
                                            timeout=50, check=False)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(GUARD, result.stderr)
                    self.assertFalse((Path(temp) / 'rejected.so').exists())

    def test_strict_optimization_keeps_all_outputs_unchanged_for_nan(self) -> None:
        for compiler in ('g++', 'clang++'):
            self.assertIsNotNone(shutil.which(compiler), f'{compiler} required for T-068 compiler check')
            for optimization in ('-O0', '-O2', '-O3'):
                with self.subTest(compiler=compiler, optimization=optimization):
                    with tempfile.TemporaryDirectory(prefix='t068-scalar-strict-') as temp:
                        library = Path(temp) / 'scalar.so'
                        subprocess.run([compiler, *FLAGS, optimization, str(SOURCE),
                                        '-o', str(library)], capture_output=True,
                                       text=True, check=True, timeout=60)
                        handle = ctypes.CDLL(str(library))
                        coverage = handle.t068_scalar_hard_brush
                        coverage.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p,
                                             ctypes.c_uint64, ctypes.c_int32, ctypes.c_void_p,
                                             ctypes.c_uint64, ctypes.c_int32, ctypes.c_double)
                        coverage.restype = ctypes.c_int32
                        rgba = handle.t068_scalar_hard_brush_rgba8
                        rgba.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p,
                                         ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
                                         ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                                         ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                                         ctypes.c_double, ctypes.c_void_p, ctypes.c_uint64,
                                         ctypes.c_int32)
                        rgba.restype = ctypes.c_int32
                        sparse = handle.t068_scalar_hard_brush_deltas
                        sparse.argtypes = (ctypes.c_void_p, ctypes.c_uint64,
                                           ctypes.c_void_p, ctypes.c_uint64,
                                           ctypes.c_void_p, ctypes.c_uint64,
                                           ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64,
                                           ctypes.c_int32, ctypes.c_double,
                                           ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32)
                        sparse.restype = ctypes.c_int32
                        sentinel = bytes([0xa7] * 64)
                        coverage_sentinel = bytes([0xb3] * 16)
                        covered = (ctypes.c_uint8 * 16).from_buffer_copy(coverage_sentinel)
                        result = (ctypes.c_uint8 * 64).from_buffer_copy(sentinel)
                        selection = (ctypes.c_uint8 * 16)(*([1] * 16))
                        source = (ctypes.c_uint8 * 64)(*([13, 29, 61, 88] * 16))
                        points = (ctypes.c_double * 2)(1.5, 1.5)
                        paint = (ctypes.c_uint8 * 4)(200, 50, 80, 160)
                        for width, coordinates in (
                                (float('nan'), (1.5, 1.5)),
                                (float('inf'), (1.5, 1.5)),
                                (4.0, (float('nan'), 1.5)),
                                (4.0, (float('inf'), 1.5)),
                        ):
                            points[0], points[1] = coordinates
                            self.assertEqual(coverage(result, 16, selection, 16,
                                                      4, points, 16, 1, width), -1)
                            self.assertEqual(bytes(result), sentinel)
                            self.assertEqual(rgba(result, 64, covered, 16, source, 64,
                                                  selection, 16, 4, points, 16, 1, width,
                                                  paint, 4, 0), -1)
                            self.assertEqual(bytes(result), sentinel)
                            self.assertEqual(bytes(covered), coverage_sentinel)
                            self.assertEqual(sparse(result, 64, source, 64, selection,
                                                    16, 4, points, 16, 1, width, paint,
                                                    4, 0), -1)
                            self.assertEqual(bytes(result), sentinel)


if __name__ == '__main__':
    unittest.main()
