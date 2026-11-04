"""T-068: validate matched Godot vs native document-publication evidence."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "tools/benchmarks/t068_bridge"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_publication.json"
SPEC = importlib.util.spec_from_file_location("t068_publication_runner", BRIDGE / "run_bridge.py")
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ScalarPublicationContracts(unittest.TestCase):
    def test_pinned_real_document_benchmark_is_opt_in(self) -> None:
        source = (BRIDGE / "t068_scalar_publication_profile.gd").read_text(encoding="utf-8")
        driver = (BRIDGE / "run_bridge.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/godot-native-t068-bridge.yml").read_text(
            encoding="utf-8")
        for marker in ("DrawingDocument.new", "paint_path(", "apply_scalar_brush_sparse(",
                       "_decode_sparse(", "decoded.bytes != expected", "_stage(",
                       "native.doc.undo()", "native.doc.redo()", "Time.get_ticks_usec()",
                       "T068_SCALAR_PUBLICATION_PASSED", "T068_SCALAR_PUBLICATION_TIMING"):
            self.assertIn(marker, source)
        for marker in ('"res://scalar_publication.gd"', "validate_scalar_publication(publication_cases)",
                       '"scalar_publication_cases": publication_cases',
                       '"scalar_publication_checks": int(publication_match.group(1))'):
            self.assertIn(marker, driver)
        self.assertIn("workflow_dispatch", workflow)
        self.assertNotIn("push:", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertNotIn("ImageTexture", source)
        self.assertFalse(list(ROOT.rglob("*.gdextension")))

    def test_two_live_runs_have_complete_source_pinned_evidence(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(evidence["ticket"], "T-068")
        self.assertEqual(evidence["schema_version"], 1)
        self.assertIn(runner.EXPECTED_VERSION, evidence["godot_version"])
        self.assertEqual(evidence["source_sha256"], hashlib.sha256(
            (ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp").read_bytes()).hexdigest())
        self.assertEqual(evidence["profile_sha256"], hashlib.sha256(
            (BRIDGE / "t068_scalar_publication_profile.gd").read_bytes()).hexdigest())
        self.assertEqual(len(evidence["runs"]), 2)
        for run in evidence["runs"]:
            self.assertEqual(run["checks"], 356)
            runner.validate_scalar_publication(run["cases"])
        first = {(case["side"], case["gesture"]): (case["changed"], case["sparse_bytes"])
                 for case in evidence["runs"][0]["cases"]}
        second = {(case["side"], case["gesture"]): (case["changed"], case["sparse_bytes"])
                  for case in evidence["runs"][1]["cases"]}
        self.assertEqual(first, second, "identical inputs must produce deterministic outputs")

    def test_bad_or_incomplete_evidence_fails_closed(self) -> None:
        cases = json.loads(EVIDENCE.read_text(encoding="utf-8"))["runs"][0]["cases"]
        changes = (
            lambda data: data.pop(),
            lambda data: data.append(copy.deepcopy(data[0])),
            lambda data: data[0].update(side=64),
            lambda data: data[0].update(side=32.0),
            lambda data: data[0].update(changed=True),
            lambda data: data[0].update(changed=0),
            lambda data: data[0].update(source_bytes=1),
            lambda data: data[0].update(path_bytes=12),
            lambda data: data[0].update(sparse_bytes=4),
            lambda data: data[0].update(invented=42),
            lambda data: data[0]["measurements_us"].pop("native_decode"),
            lambda data: data[0]["measurements_us"]["native_total"].update(trials=2),
            lambda data: data[0]["measurements_us"]["native_total"].update(min_us=-1),
            lambda data: data[0]["measurements_us"]["native_total"].update(max_us=0),
            lambda data: data[0]["measurements_us"]["godot_stage"].update(median_us=True),
        )
        for change in changes:
            with self.subTest(change=change):
                forged = copy.deepcopy(cases)
                change(forged)
                with self.assertRaises(ValueError):
                    runner.validate_scalar_publication(forged)
        for malformed in (None, [], {}, "results"):
            with self.assertRaises(ValueError):
                runner.validate_scalar_publication(malformed)

    def test_missing_markers_and_godot_diagnostics_are_rejected(self) -> None:
        self.assertEqual(runner.PUBLICATION_RE.search(
            "T068_SCALAR_PUBLICATION_PASSED: 356 checks").group(1), "356")
        self.assertIsNone(runner.PUBLICATION_RE.search(
            "T068_SCALAR_PUBLICATION_FAILED: 1/356"))
        self.assertIsNotNone(runner.PUBLICATION_TIMING_RE.search(
            'T068_SCALAR_PUBLICATION_TIMING: [{"side":32}]'))
        self.assertIn("T068_SCALAR_PUBLICATION_FAIL:",
                      (BRIDGE / "t068_scalar_publication_profile.gd").read_text())
        self.assertIn("T068_SCALAR_PUBLICATION_FAILED:",
                      (BRIDGE / "t068_scalar_publication_profile.gd").read_text())
        self.assertIn("T068_SCALAR_PUBLICATION_FAIL:",
                      (BRIDGE / "run_bridge.py").read_text())


if __name__ == "__main__":
    unittest.main()
