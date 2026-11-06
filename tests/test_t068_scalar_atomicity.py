"""T-068 native brush cancellation / stale-publication integration contracts."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_atomicity.json"
SPEC = importlib.util.spec_from_file_location("t068_atomic_bridge", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ScalarAtomicityBridgeContracts(unittest.TestCase):
    def test_isolated_research_only_entrypoint_and_ci(self) -> None:
        script = (BRIDGE / "t068_scalar_atomicity_smoke.gd").read_text(encoding="utf-8")
        host = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text(
            encoding="utf-8")
        fast = (ROOT / ".github/workflows/godot-check.yml").read_text(encoding="utf-8")
        for snippet in (
            'extends "res://scalar_test.gd"', 'bridge.apply_scalar_brush_sparse(',
            'edit.cancel()', 'not edit.commit().ok', 'stale.code == "STALE_REVISION"',
            'rejected.code == "STALE_PIXEL"', 'rejected.code == "STALE_REVISION"',
            'doc.history_length() == source_history', '_tile(doc, layer) == source',
            'T068_SCALAR_ATOMICITY_EVIDENCE:',
        ):
            self.assertIn(snippet, script)
        for snippet in ('--atomic-only', 'validate_scalar_atomicity(cases)',
                        'res://scalar_atomicity.gd', 'atomicity_script_sha256'):
            self.assertIn(snippet, host)
        self.assertIn('test_t068_scalar_atomicity.py', fast)
        self.assertIn('--atomic-only', workflow)
        self.assertFalse(list(ROOT.rglob("*.gdextension")))

    def test_pinned_two_runs_match_independent_rgba8_oracle(self) -> None:
        record = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(record["ticket"], "T-068")
        self.assertIn(runner.EXPECTED_VERSION, record["godot_version"])
        for key, source in (
            ("bridge_sha256", BRIDGE / "t068_bridge.cpp"),
            ("atomicity_script_sha256", BRIDGE / "t068_scalar_atomicity_smoke.gd"),
            ("scalar_source_sha256", ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp"),
        ):
            self.assertEqual(record[key], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(len(record["runs"]), 2)
        for run in record["runs"]:
            runner.validate_scalar_atomicity(run["cases"])
            self.assertEqual(run["checks"], run["cases"][-1]["checks_after"])
            self.assertEqual(run["checks"], 37)
        self.assertEqual(record["runs"][0], record["runs"][1])

    def test_tampered_cases_fail_closed(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding="utf-8"))["runs"][0]["cases"]
        runner.validate_scalar_atomicity(cases)
        for field, value in (
            ("name", "stale_during"), ("changed", 62),
            ("payload_bytes", 4), ("source_sha256", "0" * 64),
            ("canonical_sha256", "f" * 64), ("checks_after", 40),
        ):
            with self.subTest(field=field):
                forged = copy.deepcopy(cases)
                forged[0][field] = value
                with self.assertRaises(ValueError):
                    runner.validate_scalar_atomicity(forged)
        for corruption in (
            lambda records: records.pop(),
            lambda records: records.reverse(),
            lambda records: records[0].pop("name"),
            lambda records: records[0].update(unexpected=1),
            lambda records: records[0].update(changed=True),
            lambda records: records[0].update(checks_after=False),
        ):
            forged = copy.deepcopy(cases)
            corruption(forged)
            with self.assertRaises(ValueError):
                runner.validate_scalar_atomicity(forged)
        for malformed in (None, [], "four", {}, [1, 2, 3, 4]):
            with self.assertRaises(ValueError):
                runner.validate_scalar_atomicity(malformed)

    def test_runner_exposes_only_explicit_atomicity_mode(self) -> None:
        self.assertEqual(runner.ATOMICITY_RE.search(
            "T068_SCALAR_ATOMICITY_PASSED: 37 checks").group(1), "37")
        self.assertIsNone(runner.ATOMICITY_RE.search("T068_SCALAR_ATOMICITY_FAILED: 1/37"))
        self.assertIsNotNone(runner.ATOMICITY_EVIDENCE_RE.search(
            'T068_SCALAR_ATOMICITY_EVIDENCE: [{"name":"cancel"}]'))
        self.assertIn('if atomic_only:', (BRIDGE / "run_bridge.py").read_text())


if __name__ == "__main__":
    unittest.main()
