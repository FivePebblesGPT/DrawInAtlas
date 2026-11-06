"""Pinned, counterbalanced T-068 native brush timing / parity contracts."""
from __future__ import annotations

import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "t068_matched_brush", ROOT / "tools/benchmarks/t068_matched_brush.py")
assert SPEC is not None and SPEC.loader is not None
import sys
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
# dataclasses resolves __module__ through sys.modules.
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


class MatchedNativeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.saved = json.loads(module.EVIDENCE.read_text(encoding="utf-8"))

    def test_pinned_corpus_and_exact_parity(self) -> None:
        module.validate(self.saved)
        self.assertEqual(len(self.saved["cases"]), 10)
        self.assertEqual(len(self.saved["runs"]), 2)
        for run in self.saved["runs"]:
            for row in run:
                self.assertEqual(row["parity"]["scalar"]["pixel_mismatch"], 0)
                self.assertEqual(row["parity"]["scalar"]["missing"], 0)
                self.assertEqual(row["parity"]["scalar"]["extra"], 0)
        mismatches = {row["id"] for row in self.saved["runs"][0]
                      if row["parity"]["blend2d"]["missing"] or
                         row["parity"]["blend2d"]["extra"]}
        self.assertEqual(mismatches, {"large/round256", "large/cross64_sparse_erase",
                                      "large/transparent_noop"})

    def test_tampered_evidence_rejected(self) -> None:
        attacks = (
            lambda p: p["runs"].pop(),
            lambda p: p["runs"][0].pop(),
            lambda p: p["runs"][0].reverse(),
            lambda p: p["runs"][0][0]["parity"]["scalar"].update(missing=1),
            lambda p: p["runs"][0][0]["parity"]["scalar"].update(coverage_sha256="0" * 64),
            lambda p: p["runs"][0][0]["parity"]["blend2d"].update(missing=1),
            lambda p: p["runs"][0][0]["parity"]["blend2d"].update(pixels_sha256="0" * 64),
            lambda p: p["runs"][0][0]["call_ns"]["scalar"].pop(),
            lambda p: p["runs"][0][0]["call_ns"]["blend2d"].__setitem__(0, 0),
            lambda p: p["runs"][0][0]["median_ns"].update(scalar=1),
            lambda p: p["runs"][0][0]["order"].__setitem__(0, ["blend2d", "scalar"]),
            lambda p: p["runs"][1][0]["order"].__setitem__(0, ["scalar", "blend2d"]),
            lambda p: p["runs"][0][0].update(godot_coverage=-1),
            lambda p: p["sources"].update({next(iter(p["sources"])): "0" * 64}),
            lambda p: p.update(trials=4),
            lambda p: p["limitations"].clear(),
        )
        for attack in attacks:
            with self.subTest(attack=attack):
                tampered = copy.deepcopy(self.saved)
                attack(tampered)
                with self.assertRaises(ValueError):
                    module.validate(tampered)

    def test_no_runtime_dependency_for_fast_replay(self) -> None:
        expected = [c.key for c in module.workloads()]
        self.assertEqual(expected, self.saved["cases"])
        self.assertEqual(module.PINNED_SOURCE_SHA256,
                         self.saved["blend2d_archive_sha256"])

    @unittest.skipUnless(all(os.environ.get(name) for name in (
        "T068_BLEND2D_ARCHIVE", "T068_BLEND2D_SOURCE", "T068_BLEND2D_BUILD")),
        "Requires optional pinned Blend2D source/build and tarball")
    def test_live_matched_native_abi(self) -> None:
        module.verify_archive(Path(os.environ["T068_BLEND2D_ARCHIVE"]))
        with tempfile.TemporaryDirectory(prefix="t068-matched-tests-") as dest:
            temp = Path(dest)
            scalar = module.ScalarBrush(module.compile_kernel(temp))
            blend = module.NativeBrush(module.compile_bridge(
                Path(os.environ["T068_BLEND2D_SOURCE"]),
                Path(os.environ["T068_BLEND2D_BUILD"]), temp))
            fresh = module.screen(scalar, blend)
        module.validate(fresh)
        for fresh_run, saved_run in zip(fresh["runs"], self.saved["runs"]):
            self.assertEqual([r["parity"] for r in fresh_run],
                             [r["parity"] for r in saved_run])


if __name__ == "__main__":
    unittest.main()
