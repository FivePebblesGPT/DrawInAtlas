"""Fail-closed contracts for optional full-size native Blend2D CPU scaling evidence."""

from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_blend2d_scale as SCALE  # noqa: E402
from t068_blend2d_brush import NativeBrush, compile_bridge  # noqa: E402
from t068_blend2d_cpu import verify_archive  # noqa: E402
from t068_skia_brush import canonical_pixels  # noqa: E402

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_blend2d_scale.json"


class ScaleEvidenceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_all_two_run_evidence_replays_exact_rgba8(self) -> None:
        SCALE.validate_evidence(self.evidence)
        self.assertEqual(len(self.evidence["runs"]), 2)
        for run in self.evidence["runs"]:
            self.assertEqual(len(run["rows"]), 12)
            self.assertEqual(run["sides"], [512, 1024, 2048])
            for row in run["rows"]:
                if row["id"] == "transparent_noop":
                    self.assertGreater(row["coverage_count"], 0)
                    self.assertEqual(row["changed_pixels"], 0)
                    self.assertTrue(all(r["touched_tiles"] == 0
                                        for r in row["display_regions"].values()))

    def test_tampering_rejected(self) -> None:
        changes = (
            ("missing case", lambda p: p["runs"][0]["rows"].pop()),
            ("duplicate case", lambda p: p["runs"][0]["rows"][1].update(
                id=p["runs"][0]["rows"][0]["id"])),
            ("wrong source", lambda p: p["runs"][0]["rows"][0].update(source_sha256="0" * 64)),
            ("forged output", lambda p: p["runs"][0]["rows"][0].update(output_sha256="0" * 64)),
            ("missing selected pixel", lambda p: p["runs"][0]["rows"][0].update(changed_pixels=0)),
            ("fake upload", lambda p: p["runs"][0]["rows"][0]["display_regions"]["128"].update(
                hypothetical_full_upload_bytes=0)),
            ("invalid coverage", lambda p: p["runs"][0]["rows"][0].update(
                coverage_zlib_base64="invalid compressed coverage")),
            ("negative timing", lambda p: p["runs"][0]["rows"][0]["samples_us"]["call_us"].__setitem__(0, -1)),
            ("unpinned source", lambda p: p["runs"][0].update(source_sha256="0" * 64)),
        )
        for description, change in changes:
            with self.subTest(description=description):
                payload = copy.deepcopy(self.evidence)
                change(payload)
                with self.assertRaises(ValueError):
                    SCALE.validate_evidence(payload)

    def test_selection_regions_source_and_bounded_decompression(self) -> None:
        for side in SCALE.SIDES:
            source = SCALE.source_bytes(side)
            self.assertEqual(len(source), side * side * 4)
            self.assertEqual(source[0:4], bytes((23, 45, 67, 0)))
            for selection in ("rect128", "rect256", "sparse256"):
                mask = SCALE.selection_bytes(side, selection)
                self.assertEqual(len(mask), side * side)
                self.assertEqual(mask[0], 0)
                self.assertEqual(mask[-1], 0)
                self.assertTrue(all(v in (0, 1) for v in mask))
        for selection in ("unknown", "", "rect512"):
            with self.assertRaises(ValueError):
                SCALE.selection_bytes(512, selection)
        with self.assertRaises(ValueError):
            SCALE.source_bytes(4096)
        with self.assertRaisesRegex(ValueError, "coverage"):
            SCALE._unpack_coverage(512, "A" * 200_001)
        with self.assertRaisesRegex(ValueError, "coverage"):
            SCALE._unpack_coverage(512, SCALE._pack_coverage(512, {7}) + "AAAA")
        self.assertEqual(SCALE._unpack_coverage(512, SCALE._pack_coverage(512, {7, 19})), {7, 19})


class ScaleLiveContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = os.environ.get("T068_BLEND2D_SOURCE")
        build = os.environ.get("T068_BLEND2D_BUILD")
        archive = os.environ.get("T068_BLEND2D_ARCHIVE")
        if not (source and build and archive):
            raise unittest.SkipTest("Live native scaling requires pinned archive/source/build")
        verify_archive(Path(archive))
        cls.temporary = tempfile.TemporaryDirectory(prefix="t068-blend2d-scale-test-")
        try:
            cls.native = NativeBrush(compile_bridge(Path(source), Path(build), Path(cls.temporary.name)))
        except Exception:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_real_full_size_2048_256_brush_and_512_transparent_noop(self) -> None:
        for side, case_id in ((2048, "round256"), (512, "transparent_noop")):
            with self.subTest(side=side, case=case_id):
                case = next(case for case in SCALE.CASES if case["id"] == case_id)
                source = SCALE.source_bytes(side)
                selection = SCALE.selection_bytes(side, case["selection"])
                result, coverage, timings, changed = self.native.render(
                    source, side, SCALE.points_for(side, case), case["width"],
                    case["paint"], case["erase"], selection, 128)
                self.assertEqual(result, canonical_pixels(source, coverage, case["paint"], case["erase"]))
                self.assertEqual(changed, sum(source[i*4:i*4+4] != result[i*4:i*4+4] for i in coverage))
                self.assertTrue(all(selection[i] for i in coverage))
                self.assertTrue(all(value >= 0 for value in timings.values()))
                self.assertGreater(len(coverage), 0)
                if case_id == "transparent_noop":
                    self.assertEqual(result, source)
                    self.assertEqual(changed, 0)


if __name__ == "__main__":
    unittest.main()
