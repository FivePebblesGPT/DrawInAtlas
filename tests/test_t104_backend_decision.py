"""T-104: prevent selecting a backend from non-parity or timing-only evidence."""
from __future__ import annotations

import copy
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/benchmarks/t104_backend_decision.py"
sys.path.insert(0, str(SOURCE.parent))
spec = importlib.util.spec_from_file_location("t104_backend_decision", SOURCE)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class DecisionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.record = json.loads(module.OUTPUT.read_text(encoding="utf-8"))

    def test_full_pinned_evidence_rebuilds(self) -> None:
        module.validate(self.record)
        cases = self.record["matching_corpus"]["cases"]
        self.assertEqual(len(cases), 10)
        self.assertEqual(self.record["matching_corpus"]["blend2d_exact_cases"], 7)
        self.assertEqual({c["case"] for c in cases if not c["blend2d_exact"]}, {
            "large/round256", "large/cross64_sparse_erase", "large/transparent_noop"})
        self.assertEqual({r["side"] for r in self.record["memory"]["native_workers"]},
                         {512, 1024, 2048})
        self.assertEqual(len(self.record["decisions"]), 6)
        self.assertEqual(self.record["skia"]["cases"], 16)
        self.assertEqual(set(self.record["skia"]["noncomparable_cases"]), {
            "self_crossing", "self_crossing_batched", "zero_alpha_noop", "mirrored_crossing"})
        self.assertEqual(len(self.record["memory"]["native_workers"]), 6)

    def test_nonparity_never_becomes_a_drop_in(self) -> None:
        self.assertTrue(all(r["default"].startswith(("choose_", "defer_"))
                            for r in self.record["decisions"]))
        self.assertTrue(all("not_comparable" in r["blend2d"] or
                            r["blend2d"].startswith(("reject_", "defer_"))
                            for r in self.record["decisions"]))
        changed = copy.deepcopy(self.record)
        changed["decisions"][0]["blend2d"] = "choose_native_default"
        with self.assertRaises(ValueError):
            module.validate(changed)

    def test_mutated_evidence_or_overstated_percentiles_fails_closed(self) -> None:
        mutations = (
            lambda d: d["matching_corpus"].update(blend2d_exact_cases=10),
            lambda d: d["matching_corpus"]["cases"][7].update(blend2d_exact=True),
            lambda d: d["matching_corpus"]["cases"][0]["warm_native_only_us"]["scalar"].update(p95=1),
            lambda d: d["memory"]["native_workers"][0]["linux_python_process_hwm_kib"].update(p95=0),
            lambda d: d["skia"].update(noncomparable_cases=[]),
            lambda d: d["editor_boundary"].update(physical_input_to_photon="proven"),
            lambda d: d.update(limitations=[]),
        )
        for mutate in mutations:
            record = copy.deepcopy(self.record)
            mutate(record)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                module.validate(record)

    def test_pinned_source_tampering_rejected_before_analysis(self) -> None:
        original = module.EVIDENCE
        with tempfile.TemporaryDirectory() as temporary:
            new_path = Path(temporary)
            first, _ = module.FILES["matched"]
            raw = (original / first).read_bytes()
            (new_path / first).write_bytes(raw + b" ")
            with patch.object(module, "EVIDENCE", new_path):
                with self.assertRaisesRegex(ValueError, "Unpinned matched evidence"):
                    module.load_pinned("matched")

    def test_retained_raw_logs_and_fail_closed_exit_accounting(self) -> None:
        folder = ROOT / "docs/evidence/t104-raw-logs"
        manifest = json.loads((folder / "manifest.json").read_text())
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(len(manifest["logs"]), 6)
        for row in manifest["logs"]:
            import hashlib
            raw = (folder / row["file"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row["sha256"])
            if row["process_exit_code"] == 0:
                self.assertEqual(row["strict_checker_exit_code"], 0)
                self.assertEqual(raw.count(b"T095_FULL_CANVAS_PASSED"), 1)
                self.assertNotIn(b"T095_FULL_CANVAS_FAILED", raw)
            elif row["process_exit_code"] == 1:
                self.assertEqual(row["strict_checker_exit_code"], 1)
                self.assertEqual(raw.count(b"T095_FULL_CANVAS_FAILED"), 4)
                self.assertNotIn(b"T095_FULL_CANVAS_PASSED", raw)
            else:
                self.assertIsNone(row["strict_checker_exit_code"])
                self.assertIn(b"T095_FULL_CANVAS_PASSED", raw)
                self.assertIn("NOT a verified pass", row["interpretation"])

    def test_pointer_gate_waits_for_progressive_display(self) -> None:
        pointer = (ROOT / "drawing/tests/t095_full_canvas_brush_native.gd").read_text()
        self.assertIn("T104_DISPLAY_SETTLE", pointer)
        self.assertIn("canvas._cold_population_pending", pointer)
        self.assertIn("cold_tiles_deferred", pointer)
        self.assertIn("check_all_red(doc, layer", pointer)
        self.assertIn("doc.undo().ok", pointer)


if __name__ == "__main__":
    unittest.main()
