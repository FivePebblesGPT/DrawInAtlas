#!/usr/bin/env python3
"""T-068: standalone scalar native hard-brush geometry vs real Godot oracles.

This is an opt-in, *detached* C++17 comparison: no app GDExtension,
Blend2D, backend choice, GPU timings, or real stroke-to-frame measurement.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import math
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from t068_blend2d_large_parity import ORACLE as LARGE_ORACLE, parse_oracle
from t068_blend2d_scale import CASES, SIDES, points_for, selection_bytes
from t068_skia_brush import ORACLE_FILE as SMALL_ORACLE, _allowed, canonical_pixels, load_oracle, raster_path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/benchmarks/t068_scalar_hard_brush.cpp"
SMALL_SHA256 = "b023d44c022e947effe0e688f7a4d0c2da3f51b3bd621dd7a9de02fd5b4d8784"
LARGE_SHA256 = "a7d0a30589cbb559e9bafcb6639acd1a9a8c8d3cfbd31bf7b2602785f9dbb9b2"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_scalar_hard_brush.json"


def compile_kernel(destination: Path) -> Path:
    """Compile a local research shared library without third-party dependencies."""
    compiler = shutil.which("g++")
    if not compiler:
        raise RuntimeError("C++17 g++ required for the native scalar comparison")
    output = destination / "libt068_scalar_hard_brush.so"
    subprocess.run([compiler, "-std=c++17", "-O2", "-shared", "-fPIC", "-Wall",
                    "-Wextra", "-Werror", str(SOURCE), "-o", str(output)],
                   check=True, capture_output=True, text=True, timeout=90)
    return output


class ScalarBrush:
    """Checked ctypes facade; a detached mask is never trusted without bounds."""

    def __init__(self, library: Path) -> None:
        native = ctypes.CDLL(str(library))
        self.function = native.t068_scalar_hard_brush
        self.function.restype = ctypes.c_int32
        self.function.argtypes = (ctypes.c_void_p, ctypes.c_uint64,
                                  ctypes.c_void_p, ctypes.c_uint64,
                                  ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64,
                                  ctypes.c_int32, ctypes.c_double)
        self.delta_function = native.t068_scalar_hard_brush_deltas
        self.delta_function.restype = ctypes.c_int32
        self.delta_function.argtypes = (
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32, ctypes.c_double,
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32)
        self.composite_function = native.t068_scalar_hard_brush_rgba8
        self.composite_function.restype = ctypes.c_int32
        self.composite_function.argtypes = (
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
            ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
            ctypes.c_double, ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32)

    def deltas(self, source: bytes, side: int, path: list[list[float]],
               width: float, selection: bytes, paint: tuple[int, int, int, int],
               erase: bool, *, max_changes: int) -> bytes:
        """Return a checked LE sparse wire record stream, with a caller budget.

        A capacity error is not retried implicitly: callers must explicitly
        raise their bounded changed-pixel budget before invoking native again.
        """
        if (not 1 <= side <= 2048 or len(source) != side * side * 4 or
                len(selection) != side * side or
                selection.count(0) + selection.count(1) != len(selection) or
                not 1 <= len(path) <= 128 or not math.isfinite(width) or
                not 0 < width <= 512 or
                any(len(p) != 2 or any(not math.isfinite(v) or
                    not -2 * side <= v <= 3 * side for v in p) for p in path) or
                len(paint) != 4 or any(type(c) is not int or not 0 <= c <= 255 for c in paint) or
                type(max_changes) is not int or not 0 <= max_changes <= side * side):
            raise ValueError("Invalid sparse brush inputs or changed-pixel budget")
        coordinates = (ctypes.c_double * (2 * len(path)))(*(v for pair in path for v in pair))
        source_array = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
        selection_array = (ctypes.c_uint8 * len(selection)).from_buffer_copy(selection)
        color = (ctypes.c_uint8 * 4)(*paint)
        capacity = 4 + max_changes * 12
        payload = (ctypes.c_uint8 * capacity)()
        changed = self.delta_function(
            payload, capacity, source_array, len(source_array),
            selection_array, len(selection_array), side, coordinates,
            ctypes.sizeof(coordinates), len(path), width, color, 4, int(erase))
        if changed == -5:
            raise BufferError("Native delta payload exceeded changed-pixel budget")
        if changed < 0:
            raise RuntimeError(f"Native scalar delta function returned {changed}")
        used = 4 + changed * 12
        if used > capacity or struct.unpack_from("<I", payload, 0)[0] != changed:
            raise AssertionError("Malformed native scalar delta count")
        result = bytes(payload[:used])
        previous = -1
        for offset in range(4, used, 12):
            index = struct.unpack_from("<I", result, offset)[0]
            if index <= previous or index >= side * side:
                raise AssertionError("Nonordered/out-of-range native delta index")
            previous = index
            at = index * 4
            if (result[offset + 4:offset + 8] != source[at:at + 4] or
                    result[offset + 4:offset + 8] == result[offset + 8:offset + 12]):
                raise AssertionError("Incorrect original or unchanged native delta")
        return result

    def render(self, side: int, path: list[list[float]], width: float,
               selection: bytes) -> bytes:
        if (not 1 <= side <= 2048 or len(selection) != side * side or
                selection.count(0) + selection.count(1) != len(selection) or
                not 1 <= len(path) <= 128 or not math.isfinite(width) or not 0 < width <= 512 or
                any(len(p) != 2 or any(not math.isfinite(v) or not -2 * side <= v <= 3 * side
                                        for v in p) for p in path)):
            raise ValueError("Invalid scalar brush parameters")
        points = (ctypes.c_double * (2 * len(path)))(*(v for pair in path for v in pair))
        mask = (ctypes.c_uint8 * len(selection)).from_buffer_copy(selection)
        output = (ctypes.c_uint8 * len(selection))()
        count = self.function(output, len(output), mask, len(mask), side,
                              points, ctypes.sizeof(points), len(path), width)
        if count < 0:
            raise RuntimeError(f"Native scalar brush returned {count}")
        coverage = bytes(output)
        if (coverage.count(255) != count or
                coverage.count(0) + coverage.count(255) != len(coverage)):
            raise AssertionError("Incomplete/nonbinary native scalar coverage")
        return coverage

    def composite(self, source: bytes, side: int, path: list[list[float]],
                  width: float, selection: bytes, paint: tuple[int, int, int, int],
                  erase: bool) -> tuple[bytes, bytes]:
        """Return canonical pixels and complete coverage from one native call."""
        if (len(source) != side * side * 4 or len(selection) != side * side or
                any(type(channel) is not int or not 0 <= channel <= 255 for channel in paint)
                or len(paint) != 4):
            raise ValueError("Invalid native scalar compositing buffers")
        # Reuse the public coverage facade's parameter checks without a second
        # raster call; the C++ entrypoint independently validates all inputs.
        if (not 1 <= side <= 2048 or not 1 <= len(path) <= 128 or
                not math.isfinite(width) or not 0 < width <= 512 or
                selection.count(0) + selection.count(1) != len(selection) or
                any(len(p) != 2 or any(not math.isfinite(v) or not -2 * side <= v <= 3 * side
                                        for v in p) for p in path)):
            raise ValueError("Invalid native scalar compositing parameters")
        points = (ctypes.c_double * (2 * len(path)))(*(v for pair in path for v in pair))
        selected = (ctypes.c_uint8 * len(selection)).from_buffer_copy(selection)
        original = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
        color = (ctypes.c_uint8 * 4)(*paint)
        pixels = (ctypes.c_uint8 * len(source))()
        coverage = (ctypes.c_uint8 * len(selection))()
        count = self.composite_function(
            pixels, len(pixels), coverage, len(coverage), original, len(original),
            selected, len(selected), side, points, ctypes.sizeof(points),
            len(path), width, color, 4, int(erase))
        if count < 0:
            raise RuntimeError(f"Native scalar compositor returned {count}")
        mask = bytes(coverage)
        if count != mask.count(255) or mask.count(0) + count != len(mask):
            raise AssertionError("Incomplete native scalar coverage")
        return bytes(pixels), mask


def pinned_oracles() -> tuple[int, bytes, list[dict[str, Any]], dict[tuple[int, str], set[int]]]:
    """Require the exact two independently Godot-generated fixture files."""
    if (hashlib.sha256(SMALL_ORACLE.read_bytes()).hexdigest() != SMALL_SHA256 or
            hashlib.sha256(LARGE_ORACLE.read_bytes()).hexdigest() != LARGE_SHA256):
        raise ValueError("Native scalar test fixture differs from pinned Godot output")
    side, source, small = load_oracle()
    large = parse_oracle(json.loads(LARGE_ORACLE.read_text(encoding="utf-8")))
    return side, source, small, large


def expected_mask(side: int, indices: set[int]) -> bytes:
    expected = bytearray(side * side)
    for index in indices:
        expected[index] = 255
    return bytes(expected)


def inputs() -> list[tuple[str, int, list[list[float]], float, bytes, set[int], str | None]]:
    """Fixed order, small and large; no Python-generated geometry as oracle."""
    side, source, small, large = pinned_oracles()
    rows = []
    for case in small:
        selection = bytes(int(_allowed(i, side, case["selection"])) for i in range(side * side))
        indices = set(case["coverage_indices"])
        pixels = canonical_pixels(source, indices, tuple(case["paint"]), case["erase"])
        rows.append((f"small/{case['id']}", side, raster_path(case), case["width"],
                     selection, indices, hashlib.sha256(pixels).hexdigest()))
    for tile in SIDES:
        for case in CASES:
            rows.append((f"large/{tile}/{case['id']}", tile, points_for(tile, case),
                         case["width"], selection_bytes(tile, case["selection"]),
                         large[tile, case["id"]], None))
    return rows


def screen(library: Path) -> dict[str, Any]:
    """Two independent passes; report complete coverage discrepancies, if any."""
    native = ScalarBrush(library)
    fixtures = inputs()
    all_runs = []
    for _ in range(2):
        run = []
        for identifier, side, path, width, selection, covered, final_sha in fixtures:
            result = native.render(side, path, width, selection)
            expected = expected_mask(side, covered)
            if result == expected:
                missing, extra = [], []
            else:
                missing = [i for i in covered if result[i] == 0]
                extra = [i for i, value in enumerate(result) if value == 255 and expected[i] == 0]
            run.append({"id": identifier, "side": side, "covered": result.count(255),
                        "mask_sha256": hashlib.sha256(result).hexdigest(),
                        "missing_indices": sorted(missing), "extra_indices": extra,
                        "canonical_rgba8_sha256": final_sha})
        all_runs.append(run)
    mismatches = sum(bool(r["missing_indices"] or r["extra_indices"])
                     for run in all_runs for r in run)
    payload = {"schema": 1, "method": "local float32 pixel-center to round swept-segment distance; binary selections",
               "native_source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
               "small_oracle_sha256": SMALL_SHA256, "large_oracle_sha256": LARGE_SHA256,
               "runs": all_runs,
               "summary": {"runs": 2, "cases_per_run": len(fixtures), "mismatched_cases": mismatches},
               "limitations": ["Detached scalar C++ coverage; no Godot-to-native marshaling or publication",
                               "Small fixture includes independently checked canonical RGBA8; large fixture is empty-source coverage only",
                               "No physical Windows/Linux input-to-visible p95, memory, GPU or standalone export validation"]}
    validate_evidence(payload)
    return payload


def validate_evidence(payload: dict[str, Any]) -> None:
    """Reconstruct every reported mask from pinned Godot pixels; fail closed."""
    fixtures = inputs()
    runs = payload.get("runs")
    if (payload.get("schema") != 1 or
            payload.get("native_source_sha256") != hashlib.sha256(SOURCE.read_bytes()).hexdigest() or
            payload.get("small_oracle_sha256") != SMALL_SHA256 or
            payload.get("large_oracle_sha256") != LARGE_SHA256 or
            not isinstance(runs, list) or len(runs) != 2):
        raise ValueError("Bad native scalar evidence envelope")
    signature: list[tuple[Any, ...]] | None = None
    mismatched = 0
    for rows in runs:
        if (not isinstance(rows, list) or
                [row.get("id") for row in rows] != [entry[0] for entry in fixtures]):
            raise ValueError("Missing/duplicate/unsorted native scalar comparison")
        current = []
        for row, (identifier, side, _path, _width, selection, covered, final_sha) in zip(rows, fixtures):
            missing, extra = row.get("missing_indices"), row.get("extra_indices")
            if (row.get("side") != side or row.get("canonical_rgba8_sha256") != final_sha or
                    not isinstance(missing, list) or not isinstance(extra, list) or
                    any(type(i) is not int or not 0 <= i < side * side for i in missing + extra) or
                    missing != sorted(set(missing)) or extra != sorted(set(extra)) or
                    not set(missing).issubset(covered) or set(extra).intersection(covered) or
                    any(selection[i] == 0 for i in extra)):
                raise ValueError(f"Malformed scalar discrepancy row: {identifier}")
            reconstructed = (covered - set(missing)) | set(extra)
            blob = expected_mask(side, reconstructed)
            if (row.get("covered") != len(reconstructed) or
                    row.get("mask_sha256") != hashlib.sha256(blob).hexdigest()):
                raise ValueError(f"Scalar discrepancy row does not replay: {identifier}")
            mismatched += bool(missing or extra)
            current.append((identifier, row["mask_sha256"], row["covered"], tuple(missing), tuple(extra)))
        if signature is not None and signature != current:
            raise ValueError("Native scalar runs disagree")
        signature = current
    if payload.get("summary") != {"runs": 2, "cases_per_run": len(fixtures),
                                   "mismatched_cases": mismatched}:
        raise ValueError("Scalar coverage summary inconsistent")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="t068-scalar-") as temporary:
        evidence = screen(compile_kernel(Path(temporary)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"T068_SCALAR_BRUSH_PASSED: {evidence['summary']['cases_per_run'] * 2} "
          f"native/Godot comparisons; {evidence['summary']['mismatched_cases']} mismatched cases")


if __name__ == "__main__":
    main()
