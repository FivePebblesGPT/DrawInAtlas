"""Pinned, fail-closed T-068 GCC/Clang selection ABI/compiler contract."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/benchmarks/t068_quad_compiler_matrix.py'
EVIDENCE = ROOT / 'docs/benchmarks/T068_2026-11-04_quad_compiler_matrix.json'
spec = importlib.util.spec_from_file_location('t068_quad_compiler_matrix', SCRIPT)
assert spec is not None and spec.loader is not None
import sys
sys.path.insert(0, str(SCRIPT.parent))
compiler_matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler_matrix)


class QuadCompilerMatrixTests(unittest.TestCase):
    def test_pinned_six_builds_and_failure_atomicity(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding='utf-8'))
        compiler_matrix.validate(data)
        self.assertEqual(len(data['profiles']), 6)
        self.assertEqual(sum(len(row['runs'][0]) + len(row['runs'][1])
                             for row in data['profiles']), 576)
        self.assertEqual(sum(len(row['rejections']) for row in data['profiles']), 42)
        self.assertEqual(data['unsafe_builds_rejected'], ['g++', 'clang++'])

    def test_evidence_tampering_fails_closed(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding='utf-8'))
        mutations = (
            lambda obj: obj['profiles'].pop(),
            lambda obj: obj['profiles'].reverse(),
            lambda obj: obj['profiles'][0].update(optimization='-Ofast'),
            lambda obj: obj['profiles'][0].update(version=''),
            lambda obj: obj['profiles'][0]['runs'][1].pop(),
            lambda obj: obj['profiles'][0]['runs'][1].__setitem__(1, '0' * 64),
            lambda obj: obj['profiles'][0]['rejections'].pop('nan_transform'),
            lambda obj: obj['profiles'][0]['rejections'].update(nan_density=0),
            lambda obj: obj['profiles'][0]['rejections'].update(nan_density=True),
            lambda obj: obj.update(quad_source_sha256='0' * 64),
            lambda obj: obj.update(godot_oracle_sha256='0' * 64),
            lambda obj: obj.update(unsafe_builds_rejected=['g++']),
            lambda obj: obj.update(extra='forged'),
        )
        for change in mutations:
            with self.subTest(change=change):
                forged = copy.deepcopy(data)
                change(forged)
                with self.assertRaises(ValueError):
                    compiler_matrix.validate(forged)

    @unittest.skipUnless(shutil.which('g++') and shutil.which('clang++'),
                         'Requires GCC and Clang for a live Linux toolchain matrix')
    def test_live_compiler_parity_guards_and_invalid_buffers(self) -> None:
        live = compiler_matrix.screen()
        compiler_matrix.validate(live)
        self.assertEqual([row['runs'] for row in live['profiles']],
                         [row['runs'] for row in json.loads(
                             EVIDENCE.read_text(encoding='utf-8'))['profiles']])
        self.assertEqual([row['rejections'] for row in live['profiles']],
                         [row['rejections'] for row in json.loads(
                             EVIDENCE.read_text(encoding='utf-8'))['profiles']])


if __name__ == '__main__':
    unittest.main()
