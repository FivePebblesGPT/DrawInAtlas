#!/usr/bin/env python3
"""Opt-in native Blend2D 0.21.2 hard-brush and selection parity screen.

This deliberately does not link or ship a production Drawing backend. It uses
Godot-generated, independently checked straight-RGBA8 brush fixtures; a native
Blend2D A8 path is thresholded, selected, and composed once into a detached
canonical RGBA8 tile. Timing excludes Godot publication and the physical GPU.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import math
import platform
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from t068_blend2d_cpu import PINNED_SOURCE_SHA256, ROOT, verify_archive
from t068_skia_brush import _allowed, canonical_pixels, load_oracle, raster_path


class NativeBrush:
    """Checked C ABI facade for the detached Blend2D A8 stroke screen."""

    def __init__(self, library: Path) -> None:
        native = ctypes.CDLL(str(library))
        version = native.t068_blend2d_brush_abi_version
        version.restype = ctypes.c_int32
        version.argtypes = ()
        if version() != 1:
            raise RuntimeError("Unexpected native Blend2D brush ABI version")
        self.function = native.t068_blend2d_brush
        self.function.restype = ctypes.c_int32
        self.function.argtypes = (
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
            ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
            ctypes.c_int32, ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
            ctypes.c_double, ctypes.c_uint32, ctypes.c_int32,
            ctypes.c_int32, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint64),
        )

    def render(self, source: bytes, side: int, path: list[list[float]],
               width: float, paint: tuple[int, int, int, int], erase: bool,
               selection: bytes, threshold: int) -> tuple[bytes, set[int], dict[str, float], int]:
        """Return detached canonical pixels, postselection mask, timings, changes."""
        if (side < 1 or side > 512 or len(source) != side * side * 4
                or len(selection) != side * side or any(c not in (0, 1) for c in selection)
                or not 1 <= len(path) <= 128 or not 0 < width <= 512
                or not 1 <= threshold <= 255 or len(paint) != 4
                or any(type(c) is not int or not 0 <= c <= 255 for c in paint)
                or any(len(point) != 2 or any(not math.isfinite(v) for v in point) for point in path)):
            raise ValueError("Invalid native brush input")
        start = time.perf_counter_ns()
        source_buffer = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
        selection_buffer = (ctypes.c_uint8 * len(selection)).from_buffer_copy(selection)
        path_buffer = (ctypes.c_double * (len(path) * 2))(*(v for point in path for v in point))
        output_buffer = (ctypes.c_uint8 * len(source))()
        mask_buffer = (ctypes.c_uint8 * (side * side))()
        prepared = time.perf_counter_ns()
        render_ns = ctypes.c_uint64(0)
        composite_ns = ctypes.c_uint64(0)
        argb = (paint[3] << 24) | (paint[0] << 16) | (paint[1] << 8) | paint[2]
        count = self.function(source_buffer, len(source), output_buffer, len(source),
                              mask_buffer, len(selection), selection_buffer,
                              len(selection), side, path_buffer, ctypes.sizeof(path_buffer),
                              len(path), width, argb, int(erase), threshold,
                              ctypes.byref(render_ns), ctypes.byref(composite_ns))
        returned = time.perf_counter_ns()
        if count < 0:
            raise RuntimeError(f"Native Blend2D brush failed: {count}")
        output = bytes(output_buffer)
        selected = {index for index, value in enumerate(mask_buffer) if value == 255}
        if any(v not in (0, 255) for v in mask_buffer):
            raise AssertionError("Native returned nonbinary postselection coverage")
        unpacked = time.perf_counter_ns()
        timings = {"prep_us": (prepared - start) / 1000.0,
                   "call_us": (returned - prepared) / 1000.0,
                   "output_unpack_us": (unpacked - returned) / 1000.0,
                   "native_stencil_us": render_ns.value / 1000.0,
                   "native_composite_us": composite_ns.value / 1000.0}
        return output, selected, timings, count


def compile_bridge(source: Path, library_dir: Path, destination: Path) -> Path:
    """Build the opt-in shim against a locally compiled, external Blend2D."""
    if not (source / "blend2d/blend2d.h").is_file() or not (library_dir / "libblend2d.so").is_file():
        raise FileNotFoundError("Pinned Blend2D headers/library must be built first")
    compiler = shutil.which("g++")
    if not compiler:
        raise RuntimeError("g++ required for the native Blend2D comparison")
    output = destination / "libt068_blend2d_brush.so"
    subprocess.run([compiler, "-std=c++17", "-O2", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                    "-I", str(source), str(ROOT / "tools/benchmarks/t068_blend2d_brush_bridge.cpp"),
                    "-L", str(library_dir), "-Wl,-rpath," + str(library_dir),
                    "-lblend2d", "-o", str(output)], check=True, capture_output=True, text=True, timeout=90)
    return output


def screen(bridge: Path, *, trials: int = 7) -> dict[str, Any]:
    """Run 16 Godot brush contracts at two explicitly different AA thresholds."""
    if not 3 <= trials <= 101:
        raise ValueError("Trials must be between 3 and 101")
    side, source, cases = load_oracle()
    native = NativeBrush(bridge)
    rows: list[dict[str, Any]] = []
    for threshold in (1, 128):
        for case in cases:
            path = raster_path(case)
            selection = bytes(int(_allowed(i, side, case["selection"])) for i in range(side * side))
            expected_coverage = set(case["coverage_indices"])
            expected = canonical_pixels(source, expected_coverage, tuple(case["paint"]), case["erase"])
            first: tuple[bytes, set[int], int] | None = None
            series: dict[str, list[float]] = {name: [] for name in (
                "prep_us", "call_us", "output_unpack_us", "native_stencil_us", "native_composite_us")}
            for _ in range(trials):
                result, coverage, timings, changed = native.render(
                    source, side, path, case["width"], tuple(case["paint"]),
                    case["erase"], selection, threshold)
                if first is not None and (result, coverage, changed) != first:
                    raise AssertionError(f"Native brush nondeterminism: {case['id']}")
                first = result, coverage, changed
                for name, timing in timings.items():
                    if not math.isfinite(timing) or timing < 0:
                        raise AssertionError(f"Invalid native timing: {name}")
                    series[name].append(timing)
            assert first is not None
            result, coverage, changed = first
            # Independent source-over oracle constrains the C++ compositor,
            # even when Blend2D geometry disagrees with Godot coverage.
            if result != canonical_pixels(source, coverage, tuple(case["paint"]), case["erase"]):
                raise AssertionError(f"Native compositor disagrees with canonical RGBA8: {case['id']}")
            if any(not _allowed(i, side, case["selection"]) for i in coverage):
                raise AssertionError(f"Native selection leaked: {case['id']}")
            if changed != sum(result[i:i + 4] != source[i:i + 4] for i in range(0, len(source), 4)):
                raise AssertionError(f"Native changed count inaccurate: {case['id']}")
            missing = sorted(expected_coverage - coverage)
            extra = sorted(coverage - expected_coverage)
            mismatched = sum(result[i:i + 4] != expected[i:i + 4] for i in range(0, len(source), 4))
            rows.append({
                "id": case["id"], "threshold": threshold,
                "coverage_count": len(coverage), "godot_coverage_count": len(expected_coverage),
                "coverage_missing": len(missing), "coverage_extra": len(extra),
                "coverage_missing_indices": missing, "coverage_extra_indices": extra,
                "canonical_mismatched_pixels": mismatched, "changed_pixels": changed,
                "result_sha256": hashlib.sha256(result).hexdigest(),
                "godot_result_sha256": case["after_sha256"],
                "median_us": {key: round(statistics.median(values), 3) for key, values in series.items()},
            })
    return {"schema": 1, "benchmark": "T-068 detached native Blend2D hard-brush/selection parity",
            "godot_oracle_sha256": hashlib.sha256(
                (ROOT / "tools/benchmarks/t068_skia_brush_oracle.json").read_bytes()).hexdigest(),
            "blend2d_version": "0.21.2", "source_sha256": PINNED_SOURCE_SHA256,
            "godot_oracle": "tools/benchmarks/t068_skia_brush_oracle.json",
            "side": side, "trials": trials, "thresholds": [1, 128], "cases": rows,
            "summary": {"comparisons": len(rows),
                        "nonparity_coverage": sum(bool(r["coverage_missing"] or r["coverage_extra"]) for r in rows),
                        "nonparity_rgba8": sum(r["canonical_mismatched_pixels"] > 0 for r in rows)},
            "limitations": ["native Blend2D A8 coverage is antialiased and thresholded; not Drawing's hard-brush geometry",
                            "native selection is tested as pixel-local eligibility, not transformed four-corner quad clipping",
                            "no Godot/GDExtension calls, document publication, physical GPU, or input-to-visible timing",
                            "Python ctypes input preparation and output extraction measured separately from native draw/composite"]}


def validate_evidence(payload: dict[str, Any]) -> None:
    """Refuse missing/inconsistent runs, case sets, hashes and mismatch totals."""
    side, source, cases = load_oracle()
    expected_ids = {(threshold, case["id"]) for threshold in (1, 128) for case in cases}
    oracle_sha = hashlib.sha256((ROOT / "tools/benchmarks/t068_skia_brush_oracle.json")
                                .read_bytes()).hexdigest()
    runs = payload.get("runs")
    if (payload.get("schema") != 1 or not isinstance(runs, list) or not 1 <= len(runs) <= 3):
        raise ValueError("Invalid native Blend2D brush evidence envelope")
    signatures: list[dict[tuple[int, str], tuple[Any, ...]]] = []
    for run in runs:
        rows = run.get("cases", [])
        summary = run.get("summary")
        if (run.get("schema") != 1 or run.get("side") != side or
                run.get("trials", 0) < 3 or run.get("thresholds") != [1, 128] or
                run.get("source_sha256") != PINNED_SOURCE_SHA256 or
                run.get("godot_oracle_sha256") != oracle_sha or
                not isinstance(rows, list) or len(rows) != len(expected_ids) or
                not isinstance(summary, dict)):
            raise ValueError("Invalid native brush run or unpinned source/fixture")
        keys = [(row.get("threshold"), row.get("id")) for row in rows]
        if set(keys) != expected_ids or len(set(keys)) != len(keys):
            raise ValueError("Missing or duplicate native brush case")
        cases_by_id = {case["id"]: case for case in cases}
        signature: dict[tuple[int, str], tuple[Any, ...]] = {}
        for row in rows:
            key = (row["threshold"], row["id"])
            case = cases_by_id[row["id"]]
            n = row.get("coverage_count")
            missing = row.get("coverage_missing")
            extra = row.get("coverage_extra")
            mismatch = row.get("canonical_mismatched_pixels")
            miss_ids = row.get("coverage_missing_indices")
            extra_ids = row.get("coverage_extra_indices")
            if (not all(type(x) is int and x >= 0 for x in (n, missing, extra, mismatch, row.get("changed_pixels")))
                    or not isinstance(miss_ids, list) or not isinstance(extra_ids, list)
                    or miss_ids != sorted(set(miss_ids)) or extra_ids != sorted(set(extra_ids))
                    or len(miss_ids) != missing or len(extra_ids) != extra
                    or any(type(i) is not int or not 0 <= i < side * side for i in miss_ids + extra_ids)
                    or not set(miss_ids).issubset(set(case["coverage_indices"]))
                    or set(extra_ids).intersection(set(case["coverage_indices"]))
                    or not 0 <= n <= side * side or n + missing - extra != len(case["coverage_indices"])
                    or not 0 <= mismatch <= side * side or row.get("godot_coverage_count") != len(case["coverage_indices"])
                    or row.get("godot_result_sha256") != case["after_sha256"]
                    or not isinstance(row.get("result_sha256"), str) or len(row["result_sha256"]) != 64
                    or not isinstance(row.get("median_us"), dict)
                    or set(row["median_us"]) != {"prep_us", "call_us", "output_unpack_us",
                                                  "native_stencil_us", "native_composite_us"}
                    or any(type(v) not in (int, float) or not math.isfinite(v) or v < 0
                           for v in row["median_us"].values())):
                raise ValueError(f"Malformed native brush case evidence: {key}")
            covered = (set(case["coverage_indices"]) - set(miss_ids)) | set(extra_ids)
            if any(not _allowed(i, side, case["selection"]) for i in covered):
                raise ValueError(f"Native brush selection leak in evidence: {key}")
            replay = canonical_pixels(source, covered, tuple(case["paint"]), case["erase"])
            canonical = canonical_pixels(source, set(case["coverage_indices"]),
                                         tuple(case["paint"]), case["erase"])
            if (hashlib.sha256(replay).hexdigest() != row["result_sha256"]
                    or sum(replay[i:i + 4] != source[i:i + 4] for i in range(0, len(source), 4)) != row["changed_pixels"]
                    or sum(replay[i:i + 4] != canonical[i:i + 4] for i in range(0, len(source), 4)) != mismatch):
                raise ValueError(f"Native brush evidence does not replay canonically: {key}")
            signature[key] = (n, tuple(miss_ids), tuple(extra_ids), mismatch,
                              row["changed_pixels"], row["result_sha256"])
        if summary != {"comparisons": len(rows),
                       "nonparity_coverage": sum(bool(row["coverage_missing"] or row["coverage_extra"]) for row in rows),
                       "nonparity_rgba8": sum(row["canonical_mismatched_pixels"] > 0 for row in rows)}:
            raise ValueError("Native brush summary inconsistent with cases")
        signatures.append(signature)
    if any(signature != signatures[0] for signature in signatures[1:]) or payload.get("summary") != runs[0]["summary"]:
        raise ValueError("Native brush outcomes differ between runs")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--library-dir", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=7)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.runs <= 3:
        parser.error("Runs must be between 1 and 3")
    verify_archive(args.archive)
    with tempfile.TemporaryDirectory(prefix="t068-blend2d-brush-") as temporary:
        bridge = compile_bridge(args.source, args.library_dir, Path(temporary))
        reports = [screen(bridge, trials=args.trials) for _ in range(args.runs)]
    result = {"schema": 1, "runs": reports, "summary": reports[0]["summary"],
              "platform": {"system": platform.system(), "machine": platform.machine(),
                           "release": platform.release(), "python": platform.python_version()},
              "measurement_scope": "native Blend2D A8 stencil, C++ canonical compositing, ctypes marshal; no Godot/UI/GPU"}
    validate_evidence(result)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary = result["summary"]
    print(f"T068_BLEND2D_BRUSH_PASSED: {summary['comparisons'] * args.runs} comparisons across "
          f"{args.runs} runs; {summary['nonparity_coverage']} coverage nonparity and "
          f"{summary['nonparity_rgba8']} RGBA8 nonparity per run")


if __name__ == "__main__":
    main()
