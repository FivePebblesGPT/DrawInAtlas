#!/usr/bin/env python3
"""T-068: isolated Linux CPU-process RSS screen for two detached brush ABIs.

Each side/backend/repetition runs in a fresh Python process. Memory is sampled
before buffer preparation, immediately before native entry, and after return;
VmHWM additionally catches transient allocations during the native call.
The resulting numbers are NOT per-library allocations, Godot RSS, VRAM, or
physical input-to-visible latency. No candidate is treated as production-ready.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from functools import lru_cache
from types import SimpleNamespace
from typing import Any

from t068_blend2d_cpu import PINNED_SOURCE_SHA256, verify_archive
from t068_blend2d_brush import NativeBrush, compile_bridge
from t068_blend2d_large_parity import ORACLE, parse_oracle
from t068_blend2d_scale import CASES, SIDES, points_for, selection_bytes, source_bytes
from t068_matched_brush import Prepared, Workload
from t068_scalar_hard_brush import SOURCE as SCALAR_SOURCE, ScalarBrush, compile_kernel
from t068_skia_brush import canonical_pixels

ROOT = Path(__file__).resolve().parents[2]
BRIDGE_SOURCE = ROOT / "tools/benchmarks/t068_blend2d_brush_bridge.cpp"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_native_process_memory.json"
CASE = next(case for case in CASES if case["id"] == "hard4_long")
BACKENDS = ("scalar", "blend2d")
REPETITIONS = 2
LIMITATIONS = (
    "Linux /proc VmRSS/VmHWM of a fresh Python worker, not isolated C++ heap allocation",
    "Preparation includes Python/ctypes buffers; native high-water growth may be zero if below prior peak",
    "Only 4px long strokes that both native backends render identically to the pinned Godot oracle",
    "No Godot publication, display texture, GPU VRAM, Windows RSS, or physical input-to-visible measurements",
)


def fingerprint() -> dict[str, str]:
    paths = (SCALAR_SOURCE, BRIDGE_SOURCE, ORACLE)
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def memory_snapshot() -> dict[str, int]:
    """Read exact Linux process RSS/high-water KiB; fail if /proc is unavailable."""
    values: dict[str, int] = {}
    for line in Path("/proc/self/status").read_text(encoding="ascii").splitlines():
        key, _, value = line.partition(":")
        if key in ("VmRSS", "VmHWM"):
            parts = value.strip().split()
            if len(parts) != 2 or parts[1] != "kB":
                raise ValueError(f"Unsupported {key} units")
            values[key] = int(parts[0])
    if set(values) != {"VmRSS", "VmHWM"} or any(v <= 0 for v in values.values()):
        raise ValueError("Missing Linux process RSS/HWM")
    if values["VmHWM"] < values["VmRSS"]:
        raise ValueError("VmHWM below VmRSS")
    return values


@lru_cache(maxsize=3)
def reference(side: int) -> Workload:
    oracle = parse_oracle(json.loads(ORACLE.read_text(encoding="utf-8")))
    coverage = oracle[side, CASE["id"]]
    source = source_bytes(side)
    return Workload(
        f"large/{CASE['id']}", side, source, selection_bytes(side, CASE["selection"]),
        points_for(side, CASE), float(CASE["width"]), tuple(CASE["paint"]),
        bool(CASE["erase"]), coverage,
        canonical_pixels(source, coverage, CASE["paint"], CASE["erase"]),
    )


@lru_cache(maxsize=3)
def expected(side: int) -> dict[str, Any]:
    case = reference(side)
    return {
        "side": side, "case": CASE["id"], "source_sha256": hashlib.sha256(case.source).hexdigest(),
        "selection_sha256": hashlib.sha256(case.selected).hexdigest(),
        "coverage_count": len(case.godot_coverage),
        "coverage_sha256": hashlib.sha256(bytes(
            255 if i in case.godot_coverage else 0 for i in range(side * side))).hexdigest(),
        "pixels_sha256": hashlib.sha256(case.expected).hexdigest(),
        "input_bytes": len(case.source) + len(case.selected),
        "full_output_bytes": len(case.source),
    }


def worker(backend: str, side: int, library: Path) -> dict[str, Any]:
    if backend not in BACKENDS or side not in SIDES or not library.is_file():
        raise ValueError("Unsupported native worker configuration")
    if sys.platform != "linux":
        raise RuntimeError("Linux /proc is required")
    native = ScalarBrush(library) if backend == "scalar" else NativeBrush(library)
    before_prep = memory_snapshot()
    # Prepare only input/mask/output buffers before the measured call. Constructing
    # the 2048² independent pixel oracle allocates and copies large Python
    # buffers; it must not inflate the native-call high-water baseline.
    case = Workload(
        f"large/{CASE['id']}", side, source_bytes(side),
        selection_bytes(side, CASE["selection"]), points_for(side, CASE),
        float(CASE["width"]), tuple(CASE["paint"]), bool(CASE["erase"]), set(), b"",
    )
    stub = SimpleNamespace(composite_function=None, function=None)
    prepared = Prepared(case, native if backend == "scalar" else stub,
                        native if backend == "blend2d" else stub)
    before_call = memory_snapshot()
    status = prepared.call(backend)
    after_call = memory_snapshot()  # Snapshot BEFORE expensive independent parity verification.
    case = reference(side)
    prepared.case = case  # Oracle/verification never contaminates measured native RSS.
    parity = prepared.check(backend, status)
    if any(parity[k] for k in ("missing", "extra", "pixel_mismatch")):
        raise AssertionError(f"Native {backend} not equivalent to Godot at {side}²")
    expected_status = (len(case.godot_coverage) if backend == "scalar" else
                       sum(case.source[i:i+4] != case.expected[i:i+4]
                           for i in range(0, len(case.source), 4)))
    if status != expected_status:
        raise AssertionError("Native status not consistent with exact Godot output")
    if bytes(prepared.src) != case.source or bytes(prepared.sel) != case.selected:
        raise AssertionError("Native input modified")
    return {
        "backend": backend, **expected(side), "native_status": status,
        "rss_before_prep_kib": before_prep["VmRSS"],
        "rss_before_call_kib": before_call["VmRSS"],
        "rss_after_call_kib": after_call["VmRSS"],
        "hwm_before_prep_kib": before_prep["VmHWM"],
        "hwm_before_call_kib": before_call["VmHWM"],
        "hwm_after_call_kib": after_call["VmHWM"],
        "hwm_native_growth_kib": after_call["VmHWM"] - before_call["VmHWM"],
    }


def live(archive: Path, source: Path, library_dir: Path) -> dict[str, Any]:
    if sys.platform != "linux":
        raise RuntimeError("This native process-memory diagnostic is Linux-only")
    verify_archive(archive)
    with tempfile.TemporaryDirectory(prefix="t068-memory-") as temporary:
        folder = Path(temporary)
        libraries = {"scalar": compile_kernel(folder),
                     "blend2d": compile_bridge(source, library_dir, folder)}
        runs = []
        for repeat in range(REPETITIONS):
            rows = []
            # Alternate spawn order; each worker starts fresh and holds only one backend.
            for side in SIDES:
                for backend in (BACKENDS if repeat % 2 == 0 else BACKENDS[::-1]):
                    proc = subprocess.run([
                        sys.executable, str(Path(__file__).resolve()), "--worker",
                        "--backend", backend, "--side", str(side),
                        "--library", str(libraries[backend]),
                    ], text=True, capture_output=True, timeout=90, check=False,
                        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
                    if proc.returncode != 0:
                        raise RuntimeError(f"{backend}/{side} failed: {proc.stderr[-2000:]}")
                    rows.append(json.loads(proc.stdout))
            runs.append(rows)
    result = {"schema": 1, "archive_sha256": PINNED_SOURCE_SHA256,
              "sources": fingerprint(), "sides": list(SIDES),
              "backends": list(BACKENDS), "repetitions": REPETITIONS,
              "runs": runs, "limitations": list(LIMITATIONS)}
    validate(result)
    return result


def validate(result: Any) -> None:
    """Fail closed on missing runs, forged source/parity, and malformed measurements."""
    if (type(result) is not dict or result.get("schema") != 1 or
        result.get("archive_sha256") != PINNED_SOURCE_SHA256 or
        result.get("sources") != fingerprint() or
        result.get("sides") != list(SIDES) or result.get("backends") != list(BACKENDS) or
        result.get("repetitions") != REPETITIONS or
        result.get("limitations") != list(LIMITATIONS) or
        not isinstance(result.get("runs"), list) or len(result["runs"]) != REPETITIONS):
        raise ValueError("Invalid native memory evidence envelope")
    refs = {side: expected(side) for side in SIDES}
    for run_index, rows in enumerate(result["runs"]):
        order = [(backend, side) for side in SIDES for backend in
                 (BACKENDS if run_index % 2 == 0 else BACKENDS[::-1])]
        if not isinstance(rows, list) or len(rows) != len(order):
            raise ValueError("Missing native memory workers")
        for row, (backend, side) in zip(rows, order):
            if not isinstance(row, dict) or row.get("backend") != backend:
                raise ValueError("Incorrect native worker order")
            expected_row = refs[side]
            for key, value in expected_row.items():
                if row.get(key) != value or type(row.get(key)) is not type(value):
                    raise ValueError(f"Changed canonical native reference: {key}")
            expected_status = (expected_row["coverage_count"] if backend == "scalar" else
                               expected_row["coverage_count"])
            # In this pinned translucent source-over case every covered pixel changes.
            if type(row.get("native_status")) is not int or row["native_status"] != expected_status:
                raise ValueError("Incorrect native return status")
            keys = ("rss_before_prep_kib", "rss_before_call_kib", "rss_after_call_kib",
                    "hwm_before_prep_kib", "hwm_before_call_kib", "hwm_after_call_kib",
                    "hwm_native_growth_kib")
            if any(type(row.get(k)) is not int or not 0 <= row[k] <= 2_000_000 for k in keys):
                raise ValueError("Invalid Linux RSS/HWM sample")
            if (row["hwm_before_prep_kib"] < row["rss_before_prep_kib"] or
                row["hwm_before_call_kib"] < max(row["rss_before_call_kib"], row["hwm_before_prep_kib"]) or
                row["hwm_after_call_kib"] < max(row["rss_after_call_kib"], row["hwm_before_call_kib"]) or
                row["hwm_native_growth_kib"] !=
                    row["hwm_after_call_kib"] - row["hwm_before_call_kib"]):
                raise ValueError("Inconsistent memory snapshots")
            if set(row) != set(expected_row) | {"backend", "native_status", *keys}:
                raise ValueError("Unexpected native memory evidence fields")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--backend", choices=BACKENDS, help=argparse.SUPPRESS)
    parser.add_argument("--side", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--library", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--library-dir", type=Path)
    parser.add_argument("--output", type=Path, default=EVIDENCE)
    parser.add_argument("--replay", action="store_true")
    args = parser.parse_args()
    if args.worker:
        if args.backend is None or args.side is None or args.library is None:
            parser.error("Worker requires backend, side and library")
        print(json.dumps(worker(args.backend, args.side, args.library)))
        return
    if args.replay:
        validate(json.loads(args.output.read_text(encoding="utf-8")))
        print("T068_NATIVE_MEMORY_REPLAY_PASSED")
        return
    if not all((args.archive, args.source, args.library_dir)):
        parser.error("Live memory measurement requires archive, source and library directory")
    record = live(args.archive, args.source, args.library_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T068_NATIVE_MEMORY_PASSED: 12 isolated worker calls, exact Godot pixels")


if __name__ == "__main__":
    main()
