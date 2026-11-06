"""T-068 large native A8 vs Godot-authored hard-brush coverage contracts."""

from __future__ import annotations

import base64
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_blend2d_large_parity as PARITY  # noqa: E402
from t068_blend2d_scale import _unpack_coverage, source_bytes  # noqa: E402
from t068_skia_brush import canonical_pixels  # noqa: E402

RESULT = ROOT / "docs/benchmarks/T068_2026-11-04_blend2d_large_parity.json"


class LargeOracleContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.oracle = json.loads(PARITY.ORACLE.read_text(encoding="utf-8"))
        cls.native = json.loads(PARITY.SCALE.read_text(encoding="utf-8"))
        cls.result = json.loads(RESULT.read_text(encoding="utf-8"))
        cls.coverages = PARITY.parse_oracle(cls.oracle)

    def test_godot_large_coverage_is_bounded_and_invertible(self) -> None:
        self.assertEqual(len(self.coverages), 12)
        for side in (512, 1024, 2048):
            with self.subTest(side=side):
                self.assertEqual(len(self.coverages[side, "hard4_long"]), 460)
                self.assertEqual(len(self.coverages[side, "round256"]), 51468)
                self.assertGreater(len(self.coverages[side, "cross64_sparse_erase"]), 27000)
                self.assertEqual(len(self.coverages[side, "transparent_noop"]), 7068)
        # Coverage is observed even if an erase or transparent brush would not
        # publish any pixel change from the initially empty DrawingDocument.
        for case in self.oracle["cases"]:
            if case["erase"] or case["paint"][3] == 0:
                self.assertEqual(case["blank_source_changed_pixels"], 0)

    def test_full_two_run_comparison_replays(self) -> None:
        PARITY.validate_comparison(self.result, self.oracle, self.native)
        self.assertEqual(self.result["runs"], 2)
        self.assertEqual(self.result["comparisons"], 24)
        for side in (512, 1024, 2048):
            for run in (1, 2):
                rows = {(r["side"], r["id"], r["run"]): r for r in self.result["rows"]}
                hard = rows[side, "hard4_long", run]
                self.assertEqual((hard["missing_count"], hard["extra_count"],
                                  hard["rgba8_mismatched_pixels"]), (0, 0, 0))
                round_dab = rows[side, "round256", run]
                self.assertEqual((round_dab["missing_count"], round_dab["extra_count"],
                                  round_dab["rgba8_mismatched_pixels"]), (36, 0, 36))
                transparent = rows[side, "transparent_noop", run]
                self.assertGreater(transparent["missing_count"], 0)
                self.assertEqual(transparent["rgba8_mismatched_pixels"], 0)
        self.assertEqual(self.result["summary"]["total_extra_pixels"], 0)

    def test_pixel_mismatch_count_independently_matches_full_rgba8(self) -> None:
        # An independent full-buffer reference for an erase, opaque/alpha
        # source-over and an alpha-zero case. Coverage-only mismatches must not
        # incorrectly be reported as visible RGBA8 differences.
        evidence = {(r["side"], r["id"]): r for r in self.native["runs"][0]["rows"]}
        summaries = {(r["side"], r["id"]): r for r in self.result["rows"] if r["run"] == 1}
        for name, paint, erase in (("round256", (29, 207, 15, 128), False),
                                   ("cross64_sparse_erase", (13, 99, 183, 0), True),
                                   ("transparent_noop", (255, 127, 17, 0), False)):
            with self.subTest(case=name):
                side = 512
                native_coverage = _unpack_coverage(side, evidence[side, name]["coverage_zlib_base64"])
                godot_coverage = self.coverages[side, name]
                source = source_bytes(side)
                actual = canonical_pixels(source, native_coverage, paint, erase)
                expected = canonical_pixels(source, godot_coverage, paint, erase)
                mismatch = sum(actual[i:i + 4] != expected[i:i + 4]
                               for i in range(0, len(source), 4))
                self.assertEqual(mismatch, summaries[side, name]["rgba8_mismatched_pixels"])

    def test_malformed_oracle_fails_closed(self) -> None:
        changes = (
            lambda j: j["cases"].pop(),
            lambda j: j["cases"][0].update(side=4096),
            lambda j: j["cases"][0].update(coverage_deflate_base64="invalid"),
            lambda j: j["cases"][0].update(coverage_deflate_base64=base64.b64encode(
                zlib.compress(b"\x01" * 12)).decode()),
            lambda j: j["cases"][0].update(coverage_count=0),
            lambda j: j["cases"][0].update(transform=[1.0, 0, 0, 1.0, 0, 0]),
            lambda j: j["cases"][0]["view_path"][0].__setitem__(0, 9999),
            lambda j: j.update(anchor_x="9007199254740992"),
        )
        for change in changes:
            with self.subTest(change=changes.index(change)):
                altered = copy.deepcopy(self.oracle)
                change(altered)
                with self.assertRaises(ValueError):
                    PARITY.parse_oracle(altered)
        # Valid-length nonbinary bitmap is not equivalent to a binary mask.
        altered = copy.deepcopy(self.oracle)
        altered["cases"][0]["coverage_deflate_base64"] = base64.b64encode(
            zlib.compress(b"\x02" + b"\x00" * (512 * 512 - 1))).decode()
        with self.assertRaises(ValueError):
            PARITY.parse_oracle(altered)

    def test_evidence_mutations_rejected(self) -> None:
        for change in (
            lambda j: j["summary"].update(nonparity_rgba8=0),
            lambda j: j["rows"][0].update(missing_count=100),
            lambda j: j["rows"][1].update(first_missing=[19]),
            lambda j: j["rows"].pop(),
            lambda j: j.update(native_scale_sha256="0" * 64),
        ):
            with self.subTest(change=change):
                altered = copy.deepcopy(self.result)
                change(altered)
                with self.assertRaises(ValueError):
                    PARITY.validate_comparison(altered, self.oracle, self.native)
        altered_native = copy.deepcopy(self.native)
        altered_native["runs"][0]["rows"][0]["changed_pixels"] = -1
        with self.assertRaises(ValueError):
            PARITY.compare(self.oracle, altered_native)

    def test_optional_live_godot_fixture_regeneration(self) -> None:
        executable = os.environ.get("T068_LARGE_GODOT")
        if not executable:
            self.skipTest("Set T068_LARGE_GODOT to regenerate 12 actual Godot brush gestures")
        with tempfile.TemporaryDirectory(prefix="t068-large-godot-") as temporary:
            output = Path(temporary) / "oracle.json"
            completed = subprocess.run([
                executable, "--headless", "--path", str(ROOT), "--script",
                "res://tests/drawing_t068_blend2d_large_oracle.gd", "--", str(output),
            ], cwd=ROOT, capture_output=True, text=True, timeout=240,
                env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"}, check=False)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("T068_LARGE_ORACLE_PASSED: 12 cases", completed.stdout)
            self.assertNotIn("SCRIPT ERROR:", completed.stdout + completed.stderr)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), self.oracle)


if __name__ == "__main__":
    unittest.main()
