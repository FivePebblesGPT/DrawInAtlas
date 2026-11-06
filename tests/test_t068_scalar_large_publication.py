"""Fail-closed T-068 512/1024/2048 real document publication evidence."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_large_publication.json"
SPEC = importlib.util.spec_from_file_location("t068_large_runner", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class LargeScalarPublicationContracts(unittest.TestCase):
    def test_research_only_bridge_and_phase_boundaries(self) -> None:
        source = (BRIDGE / "t068_scalar_large_publication.gd").read_text(encoding="utf-8")
        host = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text(
            encoding="utf-8")
        for marker in ('extends "res://scalar_publication.gd"', 'LARGE_SIDES: Array[int] = [512, 1024, 2048]',
                       '65536)', '_decode_sparse(', '_native_trial_large(',
                       '_godot_trial(', '_tile(native.doc, native.layer, side) == expected',
                       'native.doc.undo()', 'native.doc.redo()',
                       '"godot_first" if godot_first else "native_first"',
                       'T068_LARGE_PUBLICATION_TIMING', 'T068_LARGE_PUBLICATION_PASSED'):
            self.assertIn(marker, source)
        self.assertLess(source.index('var oracle_stroke: Dictionary = _godot_trial('),
                        source.index('for trial: int in range(LARGE_TRIALS + LARGE_WARMUPS):'))
        self.assertLess(source.index('decoded.get("bytes"'), source.index('native.doc.begin_edit('))
        for marker in ('--large-only', 'validate_large_publication(cases)',
                       '"res://scalar_large.gd"', '"profile_sha256"'):
            self.assertIn(marker, host)
        self.assertIn('workflow_dispatch', workflow)
        self.assertNotIn('push:', workflow)
        self.assertNotIn('pull_request:', workflow)
        self.assertFalse(list(ROOT.rglob('*.gdextension')))

    def test_two_complete_source_pinned_runs(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(evidence['schema_version'], 1)
        self.assertEqual(evidence['ticket'], 'T-068')
        self.assertIn(runner.EXPECTED_VERSION, evidence['godot_version'])
        for field, source in (
            ('scalar_source_sha256', ROOT / 'tools/benchmarks/t068_scalar_hard_brush.cpp'),
            ('bridge_source_sha256', BRIDGE / 't068_bridge.cpp'),
            ('profile_sha256', BRIDGE / 't068_scalar_large_publication.gd'),
        ):
            self.assertEqual(evidence[field], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(len(evidence['measurements']), 2)
        for run in evidence['measurements']:
            self.assertEqual(run['checks'], 146)
            runner.validate_large_publication(run['cases'])
        for first, second in zip(*[run['cases'] for run in evidence['measurements']]):
            self.assertEqual((first['side'], first['changed'], first['sparse_bytes'],
                              first['canonical_sha256']),
                             (second['side'], second['changed'], second['sparse_bytes'],
                              second['canonical_sha256']))
        self.assertTrue(any('physical GPU' in text for text in evidence['limitations']))

    def test_corrupted_evidence_rejected(self) -> None:
        baseline = json.loads(EVIDENCE.read_text(encoding='utf-8'))['measurements'][0]['cases']
        tamper = (
            lambda rows: rows.pop(),
            lambda rows: rows.append(copy.deepcopy(rows[0])),
            lambda rows: rows[0].update(side=1024),
            lambda rows: rows[0].update(side=True),
            lambda rows: rows[0].update(gesture='crossing'),
            lambda rows: rows[0].update(changed=1),
            lambda rows: rows[0].update(changed=True),
            lambda rows: rows[0].update(path_bytes=16),
            lambda rows: rows[0].update(source_bytes=123),
            lambda rows: rows[0].update(sparse_bytes=4),
            lambda rows: rows[0].update(canonical_sha256='0' * 64),
            lambda rows: rows[0].update(invented='ignored'),
            lambda rows: rows[0]['samples_us'].pop(),
            lambda rows: rows[0]['samples_us'][0].update(order='godot_first'),
            lambda rows: rows[0]['samples_us'][1].update(order='native_first'),
            lambda rows: rows[0]['samples_us'][1].update(trial=3),
            lambda rows: rows[0]['samples_us'][1].update(native_call=-1),
            lambda rows: rows[0]['samples_us'][1].update(native_call=True),
            lambda rows: rows[0]['samples_us'][2].update(native_total=0),
            lambda rows: rows[0]['measurements_us'].pop('native_decode'),
            lambda rows: rows[0]['measurements_us']['godot_total'].update(median_us=0),
        )
        for change in tamper:
            with self.subTest(change=change):
                records = copy.deepcopy(baseline)
                change(records)
                with self.assertRaises(ValueError):
                    runner.validate_large_publication(records)
        for malformed in (None, [], {}, 'cases'):
            with self.assertRaises(ValueError):
                runner.validate_large_publication(malformed)

    def test_fail_marker_will_stop_runner(self) -> None:
        self.assertEqual(runner.LARGE_PUBLICATION_RE.search(
            'T068_LARGE_PUBLICATION_PASSED: 146 checks').group(1), '146')
        self.assertIsNone(runner.LARGE_PUBLICATION_RE.search(
            'T068_LARGE_PUBLICATION_FAILED: 1/143'))
        self.assertIn('T068_LARGE_PUBLICATION_FAIL:',
                      (BRIDGE / 'run_bridge.py').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
