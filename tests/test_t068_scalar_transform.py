"""T-068: source-pinned transformed brush/mask parity via temporary Godot extension."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_transform.json"
SPEC = importlib.util.spec_from_file_location("t068_transform_runner", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ScalarTransformContracts(unittest.TestCase):
    def test_live_test_stays_opt_in_and_uses_real_document(self) -> None:
        script = (BRIDGE / "t068_scalar_transform_smoke.gd").read_text(encoding="utf-8")
        driver = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text(
            encoding="utf-8")
        for marker in (
            "DrawingDocument.new", "DrawingSelection.new", "selection.set_mask(",
            "selection.allows(", "affine_inverse()", "paint_path(",
            "apply_scalar_brush_sparse(", "_decode(", "decoded.bytes == expected",
            "native_edit._stage(", "native.doc.undo()", "native.doc.redo()",
            "T068_SCALAR_TRANSFORM_PASSED", "T068_SCALAR_TRANSFORM_EVIDENCE",
        ):
            self.assertIn(marker, script)
        for marker in (
            '"res://scalar_transform.gd"', "validate_scalar_transform(transform_cases)",
            '"scalar_transform_checks": int(transform_match.group(1))',
        ):
            self.assertIn(marker, driver)
        case_method = script.split("func _case(", 1)[1].split("func _initialize(", 1)[0]
        self.assertLess(case_method.index("decoded.bytes == expected"),
                        case_method.index("native.doc.begin_edit("),
                        "Never stage native output before checking complete Godot parity")
        self.assertIn("workflow_dispatch", workflow)
        self.assertNotIn("push:", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertFalse(list(ROOT.rglob("*.gdextension")))

    def test_two_godot_runs_pin_exact_masks_and_pixels(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(evidence["ticket"], "T-068")
        self.assertEqual(evidence["schema_version"], 1)
        self.assertIn(runner.EXPECTED_VERSION, evidence["godot_version"])
        self.assertEqual(evidence["scalar_source_sha256"], hashlib.sha256(
            (ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp").read_bytes()).hexdigest())
        self.assertEqual(evidence["profile_sha256"], hashlib.sha256(
            (BRIDGE / "t068_scalar_transform_smoke.gd").read_bytes()).hexdigest())
        self.assertEqual(len(evidence["runs"]), 2)
        for run in evidence["runs"]:
            self.assertEqual(run["checks"], 110)
            runner.validate_scalar_transform(run["cases"])
        self.assertEqual(evidence["runs"][0]["cases"], evidence["runs"][1]["cases"],
                         "Transformed sparse payloads and canonical hashes must be deterministic")
        self.assertIn("four-corner", " ".join(evidence["limitations"]))

    def test_missing_and_forged_comparisons_fail_closed(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding="utf-8"))["runs"][0]["cases"]
        alterations = (
            lambda data: data.pop(),
            lambda data: data.append(copy.deepcopy(data[0])),
            lambda data: data[0].update(name="invented"),
            lambda data: data[0].update(name=[]),
            lambda data: data[0].update(side=64),
            lambda data: data[0].update(side=True),
            lambda data: data[0].update(changed=0),
            lambda data: data[0].update(changed=True),
            lambda data: data[0].update(selected=1),
            lambda data: data[0].update(path_bytes=0),
            lambda data: data[0].update(source_bytes=4),
            lambda data: data[0].update(sparse_bytes=4),
            lambda data: data[0].update(canonical_sha256="0"),
            lambda data: data[0].update(canonical_sha256=[]),
            lambda data: data[0].update(unexpected=1),
        )
        for alteration in alterations:
            with self.subTest(alteration=alteration):
                modified = copy.deepcopy(cases)
                alteration(modified)
                with self.assertRaises(ValueError):
                    runner.validate_scalar_transform(modified)
        for invalid in (None, {}, [], "cases"):
            with self.assertRaises(ValueError):
                runner.validate_scalar_transform(invalid)

    def test_runner_rejects_missing_markers_and_godot_diagnostics(self) -> None:
        self.assertEqual(runner.TRANSFORM_RE.search(
            "T068_SCALAR_TRANSFORM_PASSED: 110 checks").group(1), "110")
        self.assertIsNone(runner.TRANSFORM_RE.search(
            "T068_SCALAR_TRANSFORM_FAILED: 1/110"))
        self.assertIsNotNone(runner.TRANSFORM_EVIDENCE_RE.search(
            'T068_SCALAR_TRANSFORM_EVIDENCE: [{"name":"identity_rect"}]'))
        self.assertIn("T068_SCALAR_TRANSFORM_FAIL:",
                      (BRIDGE / "run_bridge.py").read_text())


if __name__ == "__main__":
    unittest.main()
