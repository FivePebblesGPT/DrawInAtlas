#!/usr/bin/env python3
"""T-068: matched preallocated Python-to-native ABI scalar/Blend2D diagnostic.

Detached Linux C++ libraries only. This deliberately excludes Godot document
publication, Python buffer preparation, texture upload and display latency.
Geometry and canonical straight-RGBA8 must be checked before timing is
interpreted; a faster non-parity candidate is not a valid backend substitute.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import math
import statistics
import tempfile
import time
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from t068_blend2d_brush import NativeBrush, compile_bridge
from t068_blend2d_cpu import PINNED_SOURCE_SHA256, verify_archive
from t068_blend2d_large_parity import ORACLE as LARGE_ORACLE, parse_oracle
from t068_blend2d_scale import CASES, selection_bytes, source_bytes
from t068_scalar_hard_brush import SOURCE as SCALAR_SOURCE, ScalarBrush, compile_kernel
from t068_skia_brush import (
    ORACLE_FILE as SMALL_ORACLE, _allowed, canonical_pixels, load_oracle, raster_path,
)

ROOT = Path(__file__).resolve().parents[2]
BLEND_SOURCE = ROOT / "tools/benchmarks/t068_blend2d_brush_bridge.cpp"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_matched_brush.json"
SOURCE_FILES = (SCALAR_SOURCE, BLEND_SOURCE, SMALL_ORACLE, LARGE_ORACLE)
SMALL_IDS: tuple[str, ...] = ("stationary_dab", "horizontal_fractional", "diagonal",
                              "self_crossing", "erase_hidden_rgb", "zero_alpha_noop")
LARGE_IDS: tuple[str, ...] = ("hard4_long", "round256", "cross64_sparse_erase", "transparent_noop")
TRIALS = 5
RUNS = 2

# Exact native witness from the pinned Blend2D 0.21.2 A8 threshold-128 build.
BLEND_REFERENCE = {
    "small/stationary_dab": ("58e3b928e0f2e7ba353d79bf946e9c5ee3dd6c8d4c9b7da47e9420055994ee8e", "a3b6a50cd3cd625b4123ba2e0937ff7050c41e194bbc0652f39d4a5d0eb507ed", 0, 0, 0),
    "small/horizontal_fractional": ("31fd68144229033593ebda45a2c56c5956914e10a52ecc2ffef81c55ba751a05", "3056e20038d0dc0fae53606a36b7c98510f37c7bb67b707afc3851c90435f646", 0, 0, 0),
    "small/diagonal": ("36addd61353a0254ededdabe6c1ffd265f9a8dcb822d76770282036546f43b4d", "5a9b25aee73bf2faf14bc2831439a96bdc2642ad50f5d03e989cebeb7f0ba624", 0, 0, 0),
    "small/self_crossing": ("326a278fd8da68e0345fcd581c22ca06f79cfb035a7c552bb2a4766892a594fc", "8021c0e6bf7510ffd5309b6ff4dd9bd3ad11b6ce1eeb00bacb27de8fed86d6d4", 0, 0, 0),
    "small/erase_hidden_rgb": ("36addd61353a0254ededdabe6c1ffd265f9a8dcb822d76770282036546f43b4d", "1af831f76cc2eafd4406400341d5f5ca155cd0765f8e84d5cdd9904637d866df", 0, 0, 0),
    "small/zero_alpha_noop": ("326a278fd8da68e0345fcd581c22ca06f79cfb035a7c552bb2a4766892a594fc", "904fd932f2de71c5ec802b55881a988c68ba351c60b77d003054633fad7c6790", 0, 0, 0),
    "large/hard4_long": ("c2df8098ab1a82e79d939ca17136aadc6084d8d7bc18a880b58d880d7052af93", "e7c90a4db72af761f690e6a648f97eaf7aeb5503b518e77ace7be00a55ce15a7", 0, 0, 0),
    "large/round256": ("fa0bfd3368a5695533e08cae0881e811b0b8747c462a470e49a409639c621c52", "16bc91b8cd2f91e0c924bc32109f1313871523341ef47dee6e45c054fa4db27e", 36, 0, 36),
    "large/cross64_sparse_erase": ("22b7c6b624037fb44694e2d1c6d3f79ef9abdd709684e14b7c0f8e729a2ba05f", "72ab60850dd661e5f0a2db5045769a282387396d3839dac8b285ea3029469543", 15, 0, 15),
    "large/transparent_noop": ("e6f646b019862ab645c3428c33e575776cfae7aec2cbae6be1e48f9fd4bd1fa7", "dfa71c660ce116360b883868b50d2ab38fbe192ed77653d8e56c1fd8abba5fcc", 22, 0, 0),
}
LIMITATIONS = (
    'Headless Linux CPU-call timing; no Godot document or GPU presentation',
    'Small sample; no p95, confidence interval, Windows, or hardware claims',
    'Blend2D uses 50%-A8 threshold and can disagree with Godot hard geometry',
    'Both ABIs receive prepared identical data, but internal allocation differs',
)



def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sources() -> dict[str, str]:
    return {str(p.relative_to(ROOT)): digest(p.read_bytes()) for p in SOURCE_FILES}


@dataclass(frozen=True)
class Workload:
    key: str
    side: int
    source: bytes
    selected: bytes
    path: list[list[float]]
    width: float
    paint: tuple[int, int, int, int]
    erase: bool
    godot_coverage: set[int]
    expected: bytes


@lru_cache(maxsize=1)
def workloads() -> list[Workload]:
    side, source, small = load_oracle()
    lookup = {c["id"]: c for c in small}
    result = []
    for key in SMALL_IDS:
        c = lookup[key]
        coverage = set(c["coverage_indices"])
        result.append(Workload(f"small/{key}", side, source,
            bytes(int(_allowed(i, side, c["selection"])) for i in range(side * side)),
            raster_path(c), float(c["width"]), tuple(c["paint"]), c["erase"],
            coverage, canonical_pixels(source, coverage, tuple(c["paint"]), c["erase"])))
    oracle = parse_oracle(json.loads(LARGE_ORACLE.read_text(encoding="utf-8")))
    side = 512  # Smallest storage-scale witness; 1024/2048 already have separate evidence.
    for c in CASES:
        if c["id"] not in LARGE_IDS:
            continue
        coverage = oracle[side, c["id"]]
        pixels = source_bytes(side)
        path = [[side / 2 + x, side / 2 + y] for x, y in c["path"]]
        result.append(Workload(f"large/{c['id']}", side, pixels,
            selection_bytes(side, c["selection"]), path, c["width"], c["paint"],
            c["erase"], coverage, canonical_pixels(pixels, coverage, c["paint"], c["erase"])))
    if len(result) != len(SMALL_IDS) + len(LARGE_IDS):
        raise ValueError("Missing pinned workload")
    return result


class Prepared:
    """Allocate both ABIs once; only native calls occur in the timed section."""

    def __init__(self, case: Workload, scalar: ScalarBrush, blend: NativeBrush) -> None:
        self.case = case
        self.src = (ctypes.c_uint8 * len(case.source)).from_buffer_copy(case.source)
        self.sel = (ctypes.c_uint8 * len(case.selected)).from_buffer_copy(case.selected)
        self.points = (ctypes.c_double * (len(case.path) * 2))(
            *(value for xy in case.path for value in xy))
        self.paint = (ctypes.c_uint8 * 4)(*case.paint)
        self.out_s = (ctypes.c_uint8 * len(case.source))()
        self.mask_s = (ctypes.c_uint8 * len(case.selected))()
        self.out_b = (ctypes.c_uint8 * len(case.source))()
        self.mask_b = (ctypes.c_uint8 * len(case.selected))()
        self.scalar = scalar.composite_function
        self.blend = blend.function
        self.argb = (case.paint[3] << 24 | case.paint[0] << 16 |
                     case.paint[1] << 8 | case.paint[2])
        self.draw_ns = ctypes.c_uint64()
        self.composite_ns = ctypes.c_uint64()

    def call(self, backend: str) -> int:
        c = self.case
        if backend == "scalar":
            return int(self.scalar(self.out_s, len(c.source), self.mask_s, len(c.selected),
                self.src, len(c.source), self.sel, len(c.selected), c.side,
                self.points, ctypes.sizeof(self.points), len(c.path), c.width,
                self.paint, 4, int(c.erase)))
        if backend == "blend2d":
            return int(self.blend(self.src, len(c.source), self.out_b, len(c.source),
                self.mask_b, len(c.selected), self.sel, len(c.selected), c.side,
                self.points, ctypes.sizeof(self.points), len(c.path), c.width,
                self.argb, int(c.erase), 128, ctypes.byref(self.draw_ns),
                ctypes.byref(self.composite_ns)))
        raise ValueError("Unknown native backend")

    def check(self, backend: str, status: int) -> dict[str, Any]:
        c = self.case
        if status < 0:
            raise AssertionError(f"{c.key}: native {backend} status {status}")
        coverage_bytes = bytes(self.mask_s if backend == "scalar" else self.mask_b)
        if any(v not in (0, 255) for v in coverage_bytes):
            raise AssertionError(f"{c.key}: nonbinary native coverage")
        coverage = {i for i, covered in enumerate(coverage_bytes) if covered}
        if any(not c.selected[i] for i in coverage):
            raise AssertionError(f"{c.key}: native escaped selection")
        pixels = bytes(self.out_s if backend == "scalar" else self.out_b)
        expected_from_coverage = canonical_pixels(c.source, coverage, c.paint, c.erase)
        if pixels != expected_from_coverage:
            raise AssertionError(f"{c.key}: native {backend} RGBA8 composition mismatch")
        if backend == "scalar" and status != len(coverage):
            raise AssertionError("Scalar API coverage status mismatch")
        if backend == "blend2d" and status != sum(
            pixels[i:i+4] != c.source[i:i+4] for i in range(0, len(pixels), 4)):
            raise AssertionError("Blend2D API changed-pixel status mismatch")
        missing = c.godot_coverage - coverage
        extra = coverage - c.godot_coverage
        if backend == "scalar" and (missing or extra or pixels != c.expected):
            raise AssertionError(f"{c.key}: scalar violates Godot oracle")
        return {"coverage_sha256": digest(coverage_bytes), "pixels_sha256": digest(pixels),
                "missing": len(missing), "extra": len(extra),
                "pixel_mismatch": sum(pixels[i:i+4] != c.expected[i:i+4]
                                      for i in range(0, len(pixels), 4))}


def screen(scalar: ScalarBrush, blend: NativeBrush) -> dict[str, Any]:
    cases = workloads()
    runs: list[list[dict[str, Any]]] = []
    for run_idx in range(RUNS):
        rows = []
        for case in cases:
            prepared = Prepared(case, scalar, blend)
            # Untimed warm-up; every call must overwrite the entire output.
            for backend in ("scalar", "blend2d"):
                prepared.check(backend, prepared.call(backend))
            measurements: dict[str, list[int]] = {"scalar": [], "blend2d": []}
            baseline: dict[str, dict[str, Any]] = {}
            orders: list[list[str]] = []
            for trial in range(TRIALS):
                order = ["scalar", "blend2d"] if (trial + run_idx) % 2 == 0 else ["blend2d", "scalar"]
                orders.append(order)
                for backend in order:
                    start = time.perf_counter_ns()
                    status = prepared.call(backend)
                    elapsed = time.perf_counter_ns() - start
                    if elapsed <= 0:
                        raise AssertionError("Nonpositive native-call time")
                    measurements[backend].append(elapsed)
                    parity = prepared.check(backend, status)
                    if backend in baseline and parity != baseline[backend]:
                        raise AssertionError(f"Nondeterministic output for {case.key}/{backend}")
                    baseline[backend] = parity
            if bytes(prepared.src) != case.source or bytes(prepared.sel) != case.selected:
                raise AssertionError(f"Native call changed immutable inputs: {case.key}")
            rows.append({"id": case.key, "side": case.side,
                         "godot_coverage": len(case.godot_coverage),
                         "godot_pixels_sha256": digest(case.expected),
                         "parity": baseline, "order": orders,
                         "call_ns": measurements,
                         "median_ns": {k: statistics.median(v) for k, v in measurements.items()}})
        runs.append(rows)
    return {"schema": 1, "blend2d_archive_sha256": PINNED_SOURCE_SHA256,
            "sources": sources(), "cases": [c.key for c in cases],
            "runs": runs, "trials": TRIALS,
            "limitations": list(LIMITATIONS)}


def validate(record: dict[str, Any]) -> None:
    expected = [c.key for c in workloads()]
    if (type(record) is not dict or record.get("schema") != 1 or
            record.get("blend2d_archive_sha256") != PINNED_SOURCE_SHA256 or
            record.get("sources") != sources() or record.get("cases") != expected or
            record.get("trials") != TRIALS or not isinstance(record.get("limitations"), list)
            or record["limitations"] != list(LIMITATIONS) or len(record.get("runs", [])) != RUNS):
        raise ValueError("Invalid matched native benchmark metadata")
    oracle = {c.key: c for c in workloads()}
    for run_idx, rows in enumerate(record["runs"]):
        if not isinstance(rows, list) or [r.get("id") for r in rows] != expected:
            raise ValueError("Missing or unordered native comparison")
        for row in rows:
            c = oracle[row["id"]]
            if (type(row.get("side")) is not int or row["side"] != c.side or
                    type(row.get("godot_coverage")) is not int or row["godot_coverage"] != len(c.godot_coverage)
                    or row.get("godot_pixels_sha256") != digest(c.expected)):
                raise ValueError("Invalid Godot fixture reference")
            for backend in ("scalar", "blend2d"):
                parity = row.get("parity", {}).get(backend, {})
                if (set(parity) != {"coverage_sha256", "pixels_sha256", "missing", "extra", "pixel_mismatch"}
                        or any(type(parity[k]) is not int or not 0 <= parity[k] <= c.side**2
                               for k in ("missing", "extra", "pixel_mismatch"))
                        or any(not isinstance(parity[k], str) or len(parity[k]) != 64
                               or any(ch not in "0123456789abcdef" for ch in parity[k])
                               for k in ("coverage_sha256", "pixels_sha256"))):
                    raise ValueError("Malformed native parity record")
                if backend == "scalar" and (parity["missing"] or parity["extra"] or
                         parity["pixel_mismatch"] or parity["pixels_sha256"] != digest(c.expected)):
                    raise ValueError("False scalar geometry parity")
                if backend == "scalar":
                    mask = bytes(255 if i in c.godot_coverage else 0
                                 for i in range(c.side * c.side))
                    if parity["coverage_sha256"] != digest(mask):
                        raise ValueError("Scalar coverage hash does not match Godot fixture")
                elif tuple(parity[k] for k in ("coverage_sha256", "pixels_sha256",
                         "missing", "extra", "pixel_mismatch")) != BLEND_REFERENCE[c.key]:
                    raise ValueError("Blend2D result changed from pinned native witness")
                series = row.get("call_ns", {}).get(backend)
                if (not isinstance(series, list) or len(series) != TRIALS or
                        any(type(v) is not int or v <= 0 for v in series) or
                        row.get("median_ns", {}).get(backend) != statistics.median(series)):
                    raise ValueError("Invalid native-call timing")
            orders = row.get("order")
            if orders != [["scalar", "blend2d"] if (i + run_idx) % 2 == 0 else
                          ["blend2d", "scalar"] for i in range(TRIALS)]:
                raise ValueError("Native backend order was not counterbalanced")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive", type=Path)
    p.add_argument("--source", type=Path)
    p.add_argument("--library-dir", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--replay", action="store_true", help="Check pinned evidence without native libraries")
    args = p.parse_args()
    if args.replay:
        validate(json.loads(args.output.read_text(encoding="utf-8")))
        print("T068_MATCHED_NATIVE_REPLAY_PASSED")
        return
    if not all([args.archive, args.source, args.library_dir]):
        p.error("--archive, --source and --library-dir required for a live run")
    verify_archive(args.archive)
    with tempfile.TemporaryDirectory(prefix="t068-matched-native-") as directory:
        path = Path(directory)
        scalar = ScalarBrush(compile_kernel(path))
        blend = NativeBrush(compile_bridge(args.source, args.library_dir, path))
        record = screen(scalar, blend)
    validate(record)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T068_MATCHED_NATIVE_PASSED: " + str(RUNS * len(record["cases"])) + " paired workloads")


if __name__ == "__main__":
    main()
