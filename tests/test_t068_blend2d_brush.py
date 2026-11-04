"""Fail-closed contracts for the optional native Blend2D hard-brush screen."""

from __future__ import annotations

import copy
import ctypes
import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
import t068_blend2d_brush as BRUSH  # noqa: E402
from t068_blend2d_cpu import fixture  # noqa: E402
from t068_skia_brush import _allowed, canonical_pixels, load_oracle, raster_path  # noqa: E402


class BrushContracts(unittest.TestCase):
    def test_pinned_godot_oracle_is_consistent(self) -> None:
        side, source, cases = load_oracle()
        self.assertEqual(side, 32)
        self.assertEqual(len(cases), 16)
        self.assertEqual(source, fixture(side, False))
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertEqual(hashlib.sha256(canonical_pixels(
                    source, set(case["coverage_indices"]), tuple(case["paint"]),
                    case["erase"])).hexdigest(), case["after_sha256"])
                self.assertEqual(len(raster_path(case)), len(case["path"]))

    def test_pinned_two_run_evidence_fails_closed_on_corruption(self) -> None:
        evidence = ROOT / "docs/benchmarks/T068_2026-11-04_blend2d_brush.json"
        payload = json.loads(evidence.read_text(encoding="utf-8"))
        BRUSH.validate_evidence(payload)
        for description, mutate in (
                ("missing", lambda p: p["runs"][1]["cases"].pop()),
                ("repeated", lambda p: p["runs"][0]["cases"][1].update(
                    id=p["runs"][0]["cases"][0]["id"])),
                ("summary", lambda p: p["summary"].update(nonparity_coverage=999)),
                ("source", lambda p: p["runs"][0].update(source_sha256="0" * 64)),
                ("oracle", lambda p: p["runs"][0].update(godot_oracle_sha256="0" * 64)),
                ("result", lambda p: p["runs"][0]["cases"][0].update(result_sha256="0" * 64)),
                ("time", lambda p: p["runs"][0]["cases"][0]["median_us"].update(call_us=-1))):
            with self.subTest(description=description):
                mutated = copy.deepcopy(payload)
                mutate(mutated)
                with self.assertRaisesRegex(ValueError, "(Invalid|Missing|Malformed|inconsistent|differ|replay)"):
                    BRUSH.validate_evidence(mutated)

    def test_missing_sources_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(FileNotFoundError, "Pinned Blend2D"):
                BRUSH.compile_bridge(root, root, root)
        with self.assertRaisesRegex(ValueError, "Trials"):
            BRUSH.screen(Path("nonexistent"), trials=2)

    def test_source_integrity_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tampered.tar.gz"
            path.write_bytes(b"not Blend2D")
            with self.assertRaises(ValueError):
                BRUSH.verify_archive(path)


class NativeBlend2DBrushContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = os.environ.get("T068_BLEND2D_SOURCE")
        build = os.environ.get("T068_BLEND2D_BUILD")
        archive = os.environ.get("T068_BLEND2D_ARCHIVE")
        if not (source and build and archive):
            raise unittest.SkipTest("Enable native tests with pinned source/build/archive")
        BRUSH.verify_archive(Path(archive))
        cls.temporary = tempfile.TemporaryDirectory(prefix="t068-blend2d-brush-live-")
        try:
            bridge = BRUSH.compile_bridge(Path(source), Path(build), Path(cls.temporary.name))
            cls.native = BRUSH.NativeBrush(bridge)
        except Exception:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_all_cases_match_canonical_compositing_for_native_coverage(self) -> None:
        side, source, cases = load_oracle()
        for threshold in (1, 128):
            for case in cases:
                with self.subTest(threshold=threshold, case=case["id"]):
                    selection = bytes(int(_allowed(i, side, case["selection"])) for i in range(side * side))
                    result, coverage, elapsed, count = self.native.render(
                        source, side, raster_path(case), case["width"], tuple(case["paint"]),
                        case["erase"], selection, threshold)
                    self.assertEqual(result, canonical_pixels(
                        source, coverage, tuple(case["paint"]), case["erase"]))
                    self.assertEqual(count, sum(result[i:i + 4] != source[i:i + 4]
                                                for i in range(0, len(source), 4)))
                    self.assertTrue(all(selection[i] == 1 for i in coverage))
                    self.assertTrue(all(value >= 0 for value in elapsed.values()))
                    self.assertTrue(all(result[i * 4:i * 4 + 4] == source[i * 4:i * 4 + 4]
                                        for i in range(side * side) if i not in coverage))

    def test_selection_is_native_and_does_not_touch_unselected_hidden_rgb(self) -> None:
        side, source, cases = load_oracle()
        case = next(c for c in cases if c["id"] == "diagonal")
        for selection in (bytes(side * side), bytes([1] * (side * side)),
                          bytes([int(i % 7 == 0) for i in range(side * side)])):
            result, coverage, _, changed = self.native.render(
                source, side, raster_path(case), case["width"], tuple(case["paint"]),
                case["erase"], selection, 128)
            self.assertTrue(all(selection[i] for i in coverage))
            self.assertTrue(all(source[i * 4:i * 4 + 4] == result[i * 4:i * 4 + 4]
                                for i in range(side * side) if selection[i] == 0))
            if not any(selection):
                self.assertEqual(result, source)
                self.assertEqual(changed, 0)

    def test_alpha_zero_is_true_noop_even_on_hidden_rgb(self) -> None:
        side, source, cases = load_oracle()
        case = next(c for c in cases if c["id"] == "zero_alpha_noop")
        result, coverage, _, changed = self.native.render(
            source, side, raster_path(case), case["width"], tuple(case["paint"]),
            False, bytes([1] * side * side), 1)
        self.assertGreater(len(coverage), 0)
        self.assertEqual(changed, 0)
        self.assertEqual(result, source)

    def test_failures_leave_all_native_outputs_and_times_untouched(self) -> None:
        source = (ctypes.c_uint8 * 256)(*([13] * 256))
        output = (ctypes.c_uint8 * 256)(*([113] * 256))
        coverage = (ctypes.c_uint8 * 64)(*([77] * 64))
        selection = (ctypes.c_uint8 * 64)(*([1] * 64))
        path = (ctypes.c_double * 2)(4.0, 4.0)
        draw = ctypes.c_uint64(12345)
        comp = ctypes.c_uint64(98765)
        def invoke(**changes: object) -> int:
            args: dict[str, object] = dict(
                source=source, source_bytes=256, output=output, output_bytes=256,
                coverage=coverage, coverage_bytes=64, selection=selection,
                selection_bytes=64, side=8, points=path,
                point_bytes=16, point_count=1, width=3.0, argb=0xFFAA5500, erase=0, threshold=128,
                draw_ns=ctypes.byref(draw), composite_ns=ctypes.byref(comp))
            args.update(changes)
            return self.native.function(*args.values())
        for kwargs, expected in (({"source_bytes": 252}, -1),
                                 ({"output_bytes": 255}, -1),
                                 ({"coverage_bytes": 63}, -1),
                                 ({"selection_bytes": 63}, -1),
                                 ({"point_bytes": 15}, -1),
                                 ({"point_count": 0}, -1),
                                 ({"width": float("nan")}, -1),
                                 ({"threshold": 0}, -1),
                                 ({"threshold": 256}, -1),
                                 ({"erase": 2}, -1),
                                 ({"output": source}, -1),
                                 ({"coverage": source}, -1),
                                 ({"output": coverage}, -1),
                                 ({"coverage": selection}, -1),
                                 ({"side": 513}, -1)):
            with self.subTest(kwargs=kwargs):
                self.assertEqual(invoke(**kwargs), expected)
                self.assertEqual(bytes(output), bytes([113] * 256))
                self.assertEqual(bytes(coverage), bytes([77] * 64))
                self.assertEqual((draw.value, comp.value), (12345, 98765))
        selection[5] = 3
        self.assertEqual(invoke(), -3)
        self.assertEqual(bytes(output), bytes([113] * 256))
        self.assertEqual(bytes(coverage), bytes([77] * 64))
        self.assertEqual((draw.value, comp.value), (12345, 98765))

    def test_exact_godot_coverage_and_reproducible_two_thresholds(self) -> None:
        result = BRUSH.screen(self.native_library(), trials=3)
        self.assertEqual(result["summary"]["comparisons"], 32)
        self.assertEqual(result["summary"]["nonparity_coverage"], 18)
        self.assertEqual(result["summary"]["nonparity_rgba8"], 17)
        rows = {(r["threshold"], r["id"]): r for r in result["cases"]}
        self.assertEqual(rows[(128, "self_crossing")]["canonical_mismatched_pixels"], 0)
        self.assertEqual(rows[(128, "mirrored_crossing")]["canonical_mismatched_pixels"], 0)
        self.assertEqual(rows[(128, "inverted_selection")]["coverage_missing"], 1)
        self.assertGreater(rows[(1, "stationary_dab")]["coverage_extra"], 0)
        self.assertEqual(rows[(1, "zero_alpha_noop")]["canonical_mismatched_pixels"], 0)

    @classmethod
    def native_library(cls) -> Path:
        return Path(cls.temporary.name) / "libt068_blend2d_brush.so"


if __name__ == "__main__":
    unittest.main()
