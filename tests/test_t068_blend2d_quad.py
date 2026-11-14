"""T-068 native convex four-corner selection with pinned Godot parity."""

from __future__ import annotations

import base64
import copy
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_blend2d_quad as QUAD  # noqa: E402
from t068_blend2d_brush import NativeBrush  # noqa: E402
from t068_blend2d_cpu import verify_archive  # noqa: E402
from t068_skia_brush import canonical_pixels  # noqa: E402
from t068_oracle_engine_compat import require_beta3_matches_pinned_beta2  # noqa: E402

EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_blend2d_quad.json"


class QuadEvidenceTests(unittest.TestCase):
    def test_pinned_complete_fixture_and_evidence(self) -> None:
        oracle = QUAD.load_oracle()
        self.assertEqual(len(oracle["cases"]), 15)
        self.assertEqual([r["allowed"] for r in oracle["cases"]],
                         [1056, 1008, 1397, 1258, 1505, 1059, 1600, 1600, 1600,
                          1600, 1600, 1104, 64, 4096, 0])
        evidence = json.loads(EVIDENCE.read_text())
        QUAD.validate_evidence(evidence)
        self.assertEqual(evidence["summary"], {"runs": 2, "cases_per_run": 15,
                                                "mismatched_cases": 0})

    def test_exact_edge_masks_have_independent_expected_pixels(self) -> None:
        """An exact 40² rectangle includes its four boundary corners; no fringe."""
        rows = {row["id"]: row for row in QUAD.load_oracle()["cases"]}
        square = bytes(int(12 <= x < 52 and 12 <= y < 52)
                       for y in range(QUAD.SIDE) for x in range(QUAD.SIDE))
        for name in ("edge_rect", "edge_rect_cw", "edge_rotated", "edge_sheared",
                     "edge_density"):
            with self.subTest(case=name):
                self.assertEqual(base64.b64decode(rows[name]["mask_base64"]), square)
        thin = bytes(int(x == 0) for _y in range(QUAD.SIDE)
                     for x in range(QUAD.SIDE))
        self.assertEqual(base64.b64decode(rows["edge_thin"]["mask_base64"]), thin)
        diamond = base64.b64decode(rows["edge_diamond"]["mask_base64"])
        self.assertEqual(diamond[32 * QUAD.SIDE + 31], 1)
        self.assertEqual(diamond[8 * QUAD.SIDE + 32], 0)  # corner alone cannot fit a full pixel
        self.assertEqual(diamond[32 * QUAD.SIDE + 8], 0)

    def test_invalid_evidence_is_rejected(self) -> None:
        evidence = json.loads(EVIDENCE.read_text())
        for change in (
            lambda p: p["runs"][0].pop(),
            lambda p: p["runs"][1][0].update(id="rotated"),
            lambda p: p["runs"][0][0].update(mask_sha256="0" * 64),
            lambda p: p["runs"][0][0].update(native_allowed=1057),
            lambda p: p["runs"][1][0].update(missing_indices=[0]),
            lambda p: p["runs"][1][0].update(extra_indices=[0, 0]),
            lambda p: p["runs"][1][0].update(extra_indices=[4096]),
            lambda p: p["summary"].update(mismatched_cases=9),
            lambda p: p.update(godot_oracle_sha256="0" * 64),
        ):
            with self.subTest(change=change):
                altered = copy.deepcopy(evidence)
                change(altered)
                with self.assertRaises(ValueError):
                    QUAD.validate_evidence(altered)

    def test_optional_godot_regeneration(self) -> None:
        executable = os.environ.get("T068_QUAD_GODOT")
        if not executable:
            self.skipTest("Set T068_QUAD_GODOT to regenerate native-scope oracle")
        with tempfile.TemporaryDirectory(prefix="t068-godot-quad-") as directory:
            output = Path(directory) / "oracle.json"
            process = subprocess.run([executable, "--headless", "--path", str(ROOT), "--script",
                                      "res://tests/drawing_t068_quad_scope_oracle.gd", "--", str(output)],
                                     capture_output=True, text=True, timeout=120, cwd=ROOT,
                                     env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"}, check=False)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertIn("T068_QUAD_SCOPE_ORACLE_PASSED: 15 cases", process.stdout)
            self.assertNotIn("SCRIPT ERROR", process.stdout + process.stderr)
            require_beta3_matches_pinned_beta2(QUAD.load_oracle(), json.loads(output.read_text()))


class NativeQuadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        archive = os.environ.get("T068_BLEND2D_ARCHIVE")
        source = os.environ.get("T068_BLEND2D_SOURCE")
        build = os.environ.get("T068_BLEND2D_BUILD")
        if not archive or not source or not build:
            raise unittest.SkipTest("Provide pinned Blend2D source, build and archive")
        verify_archive(Path(archive))
        cls.temporary = tempfile.TemporaryDirectory(prefix="t068-native-quad-")
        try:
            cls.library = QUAD.compile_bridge(Path(source), Path(build), Path(cls.temporary.name))
            cls.scope = QUAD.QuadScope(cls.library)
        except Exception:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_all_transformed_scopes_match_godot_twice(self) -> None:
        evidence = QUAD.screen(self.library)
        QUAD.validate_evidence(evidence)
        self.assertEqual(evidence["summary"]["mismatched_cases"], 0)
        for row in QUAD.load_oracle()["cases"]:
            with self.subTest(scope=row["id"]):
                self.assertEqual(self.scope.render(row), base64.b64decode(row["mask_base64"]))

    def test_native_brush_consumes_quad_selection_without_unselected_writes(self) -> None:
        brush = NativeBrush(self.library)
        source = bytes([41, 83, 107, 0, 255, 128, 49, 233]) * (QUAD.SIDE ** 2 // 2)
        for row in QUAD.load_oracle()["cases"]:
            with self.subTest(scope=row["id"]):
                selection = self.scope.render(row)
                output, covered, _, changed = brush.render(source, QUAD.SIDE,
                    [[12.0, 16.0], [50.0, 51.0]], 7.0, (129, 35, 200, 153),
                    False, selection, 128)
                self.assertTrue(all(selection[i] for i in covered))
                self.assertEqual(output, canonical_pixels(source, covered, (129, 35, 200, 153), False))
                self.assertEqual(changed, sum(output[i:i + 4] != source[i:i + 4]
                                              for i in range(0, len(source), 4)))
                if row["id"] == "empty_enabled":
                    self.assertEqual(output, source)
                    self.assertFalse(covered)

    def test_native_invalid_arguments_leave_output_unmodified(self) -> None:
        output = (ctypes.c_uint8 * 64)(*([0xA5] * 64))
        transform = (ctypes.c_double * 6)(1, 0, 0, 1, 0, 0)
        polygon = (ctypes.c_double * 8)(1.25, 1.25, 6.75, 1.25,
                                        6.75, 6.75, 1.25, 6.75)
        def call(**overrides: object) -> int:
            args: dict[str, object] = dict(output=output, output_bytes=64, side=8,
                coefficients=transform, coefficient_bytes=48, density=1.0,
                polygon=polygon, polygon_bytes=64, vertices=4, enabled=1)
            args.update(overrides)
            return self.scope.function(*args.values())
        self.assertGreater(call(), 0)
        for change, code in (
            ({"output_bytes": 63}, -1), ({"side": 2049}, -1),
            ({"coefficient_bytes": 40}, -1), ({"density": 0.0}, -1),
            ({"density": float("nan")}, -1), ({"polygon_bytes": 56}, -1),
            ({"vertices": 2, "polygon_bytes": 32}, -3),
            ({"enabled": 2}, -1), ({"output": polygon}, -1),
            ({"output": transform}, -1),
            ({"coefficients": (ctypes.c_double * 6)(0, 0, 0, 0, 0, 0)}, -1),
            ({"coefficients": (ctypes.c_double * 6)(float("inf"), 0, 0, 1, 0, 0)}, -1),
            ({"polygon": (ctypes.c_double * 8)(1, 1, 6, 6, 1, 6, 6, 1)}, -3),
            ({"polygon": (ctypes.c_double * 8)(1, 1, 1, 1, 6, 6, 1, 6)}, -3),
        ):
            output[:] = [0xA5] * 64
            with self.subTest(change=change):
                self.assertEqual(call(**change), code)
                self.assertEqual(bytes(output), bytes([0xA5] * 64))


if __name__ == "__main__":
    unittest.main()
