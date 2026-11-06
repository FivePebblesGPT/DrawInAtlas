"""T-068 native four-corner scope -> sparse brush -> document publication proof."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_quad_publication.json"
SPEC = importlib.util.spec_from_file_location("t068_quad_publication", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class QuadPublicationContracts(unittest.TestCase):
    def test_live_bridge_is_explicitly_opt_in(self) -> None:
        script = (BRIDGE / "t068_quad_publication_smoke.gd").read_text(encoding="utf-8")
        host = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text()
        fast = (ROOT / ".github/workflows/godot-check.yml").read_text()
        for snippet in (
            'bridge.build_quad_selection(', 'bridge.apply_scalar_brush_sparse(',
            'mask == oracle_mask', 'edit._stage(', 'document.undo()',
            'document.redo()', '"NO_CHANGE"', 'T068_QUAD_PUBLICATION_PASSED',
        ):
            self.assertIn(snippet, script)
        for snippet in ('--quad-publication-only', 'validate_quad_publication(cases)',
                        'res://quad_publication.gd', 'QUAD_PUBLICATION_EVIDENCE_RE'):
            self.assertIn(snippet, host)
        self.assertIn('test_t068_quad_publication.py', fast)
        self.assertIn('--quad-publication-only', workflow)
        self.assertIn('workflow_dispatch', workflow)
        self.assertNotIn('push:', workflow)
        self.assertNotIn('pull_request:', workflow)
        self.assertFalse(list(ROOT.rglob('*.gdextension')))

    def test_pinned_independent_two_run_publication(self) -> None:
        record = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(record['schema_version'], 1)
        self.assertEqual(record['ticket'], 'T-068')
        self.assertIn(runner.EXPECTED_VERSION, record['godot_version'])
        for key, path in (
            ('quad_source_sha256', ROOT / 'tools/benchmarks/t068_quad_scope_kernel.cpp'),
            ('scalar_source_sha256', ROOT / 'tools/benchmarks/t068_scalar_hard_brush.cpp'),
            ('bridge_source_sha256', BRIDGE / 't068_bridge.cpp'),
            ('profile_sha256', BRIDGE / 't068_quad_publication_smoke.gd'),
            ('oracle_sha256', ROOT / 'tools/benchmarks/t068_quad_scope_oracle.json'),
        ):
            self.assertEqual(record[key], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(len(record['runs']), 2)
        self.assertEqual(record['runs'][0], record['runs'][1])
        for run in record['runs']:
            runner.validate_quad_publication(run['cases'])
            self.assertEqual(run['checks'], 153)
            self.assertEqual(run['checks'], run['cases'][-1]['checks_after'])
            self.assertEqual(len(run['cases']), 15)
            self.assertEqual(run['cases'][-1]['history_delta'], 0)
            self.assertEqual(run['cases'][-1]['revision_delta'], 0)
        self.assertTrue(any('not production' in item.lower() for item in record['limitations']))

    def test_reject_incomplete_or_tampered_publication_evidence(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding='utf-8'))['runs'][0]['cases']
        runner.validate_quad_publication(cases)
        for key, value in (
            ('id', 'missing'), ('mask_sha256', '0' * 64), ('allowed', 1),
            ('changed', 1), ('sparse_bytes', 4), ('pixels_sha256', '0' * 64),
            ('source_sha256', '0' * 64), ('undo_sha256', '0' * 64),
            ('redo_sha256', '0' * 64), ('history_delta', 0),
            ('revision_delta', 0), ('checks_after', 100),
        ):
            with self.subTest(key=key):
                forged = copy.deepcopy(cases)
                forged[0][key] = value
                with self.assertRaises(ValueError):
                    runner.validate_quad_publication(forged)
        for mutation in (
            lambda rows: rows.pop(),
            lambda rows: rows.reverse(),
            lambda rows: rows[0].update(extra=1),
            lambda rows: rows[0].update(changed=True),
            lambda rows: rows[0].update(history_delta=True),
            lambda rows: rows[0].pop('source_sha256'),
            lambda rows: rows[0].update(checks_after=False),
        ):
            forged = copy.deepcopy(cases)
            mutation(forged)
            with self.assertRaises(ValueError):
                runner.validate_quad_publication(forged)
        for invalid in (None, [], {}, '15', list(range(15))):
            with self.assertRaises(ValueError):
                runner.validate_quad_publication(invalid)

    def test_no_change_cases_never_publish(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding='utf-8'))['runs'][0]['cases']
        by_name = {case['id']: case for case in cases}
        for name in ('empty_enabled', 'edge_thin'):
            with self.subTest(name=name):
                case = by_name[name]
                self.assertEqual(case['changed'], 0)
                self.assertEqual(case['sparse_bytes'], 4)
                self.assertEqual(case['history_delta'], 0)
                self.assertEqual(case['revision_delta'], 0)
                self.assertEqual(case['source_sha256'], case['pixels_sha256'])


if __name__ == '__main__':
    unittest.main()
