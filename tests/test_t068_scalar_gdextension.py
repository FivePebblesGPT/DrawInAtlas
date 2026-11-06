"""T-068: fail-closed contracts for the opt-in scalar Godot GDExtension boundary."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
SOURCE = BRIDGE / "run_bridge.py"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_gdextension.json"
SPEC = importlib.util.spec_from_file_location("t068_scalar_bridge_runner", SOURCE)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ScalarGodotBridgeContracts(unittest.TestCase):
    def test_isolated_pinned_native_source_and_no_shipped_extension(self) -> None:
        cpp = (BRIDGE / "t068_bridge.cpp").read_text(encoding="utf-8")
        script = (BRIDGE / "t068_scalar_sparse_smoke.gd").read_text(encoding="utf-8")
        build = SOURCE.read_text(encoding="utf-8")
        for marker in ("apply_scalar_brush_sparse", "process_scalar",
                       "ptrcall_scalar", "call_scalar", "max_changes > 65536",
                       "t068_scalar_hard_brush_deltas", "GDEXTENSION_VARIANT_TYPE_FLOAT",
                       "GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY"):
            self.assertIn(marker, cpp)
        for marker in ("paint_path(", "_stage(", "edit.commit()", "staging.commit()",
                       "actual.doc.undo()", "actual.doc.redo()", "source == source_copy",
                       "T068_SCALAR_BRIDGE_PASSED", "T068_SCALAR_BRIDGE_EVIDENCE",
                       "non-binary selection rejected", "source includes alpha-zero"):
            self.assertIn(marker, script)
        self.assertIn('str(ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp")', build)
        self.assertIn('"res://scalar_test.gd"', build)
        self.assertIn('shutil.copyfile(BRIDGE / "t068_scalar_sparse_smoke.gd"', build)
        self.assertFalse(list(ROOT.rglob("*.gdextension")),
                         "No experimental descriptor may be committed into the app")

    def test_two_run_evidence_is_complete_and_source_pinned(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(data["ticket"], "T-068")
        self.assertIn(runner.EXPECTED_VERSION, data["godot_version"])
        self.assertEqual(data["scalar_source_sha256"], hashlib.sha256(
            (ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp").read_bytes()).hexdigest())
        self.assertEqual(len(data["runs"]), 2)
        for observation in data["runs"]:
            runner.validate_scalar_evidence(observation["scalar_evidence"])
            self.assertEqual(observation["scalar_checks"],
                             observation["scalar_evidence"]["checks"])
            self.assertGreaterEqual(observation["legacy_bridge_checks"], 440)
            self.assertGreaterEqual(observation["legacy_sparse_checks"], 170)
            self.assertGreaterEqual(observation["canonical_document_checks"], 200)
            self.assertGreaterEqual(observation["revision_checks"], 300)
            self.assertGreaterEqual(observation["marshal_checks"], 700)
            self.assertGreaterEqual(observation["batch_checks"], 120)
        self.assertEqual(data["runs"][0]["scalar_evidence"],
                         data["runs"][1]["scalar_evidence"])

    def test_truncated_or_forged_wire_metrics_fail_closed(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        record = data["runs"][0]["scalar_evidence"]
        for mutation in (
            lambda value: value.pop("changed"),
            lambda value: value.update(changed=0),
            lambda value: value.update(sparse_bytes=0),
            lambda value: value.update(masked_sparse_bytes=4),
            lambda value: value.update(no_op_bytes=0),
            lambda value: value.update(erase_sparse_bytes=4),
            lambda value: value.update(path_bytes=32),
            lambda value: value.update(source_bytes=1),
            lambda value: value.update(checks=3),
            lambda value: value.update(changed=True),
            lambda value: value.update(invented=42),
        ):
            with self.subTest(mutation=mutation):
                forged = copy.deepcopy(record)
                mutation(forged)
                with self.assertRaises(ValueError):
                    runner.validate_scalar_evidence(forged)
        for malformed in (None, [], "yes", {"checks": 31}):
            with self.assertRaises(ValueError):
                runner.validate_scalar_evidence(malformed)

    def test_runner_rejects_scalar_diagnostics_and_missing_markers(self) -> None:
        self.assertEqual(runner.SCALAR_RE.search(
            "T068_SCALAR_BRIDGE_PASSED: 31 checks").group(1), "31")
        self.assertIsNone(runner.SCALAR_RE.search("T068_SCALAR_BRIDGE_FAILED: 1/31"))
        self.assertIsNotNone(runner.SCALAR_EVIDENCE_RE.search(
            'T068_SCALAR_BRIDGE_EVIDENCE: {"changed": 63}'))
        source = SOURCE.read_text(encoding="utf-8")
        for marker in ("scalar_match is None or scalar_evidence is None",
                       "validate_scalar_evidence(scalar_record)",
                       'int(scalar_match.group(1)) != scalar_record["checks"]',
                       "T068_SCALAR_BRIDGE_FAIL:", "T068_SCALAR_BRIDGE_FAILED:"):
            self.assertIn(marker, source)


if __name__ == "__main__":
    unittest.main()
