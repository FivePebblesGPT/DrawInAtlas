#!/usr/bin/env python3
"""Compile and measure an isolated native edit kernel without adding a runtime dependency.

The ctypes call is *not* a Godot GDExtension call. Times exclude viewport upload,
Godot transaction marshaling, and generation save. Build outputs go outside Git.
"""
from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time
from typing import Callable

SOURCE = Path(__file__).with_name("t068_raster_kernel.cpp")


class Delta(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("before", ctypes.c_uint32), ("after", ctypes.c_uint32)]


@dataclass(frozen=True)
class Batch:
    before: bytes
    after: bytes
    changes: tuple[tuple[int, int, int], ...]


def build(directory: Path) -> Path:
    """Build the optional C++ candidate with the host compiler.

    Parameters
    ----------
    directory : Path
        Temporary output directory, not the source tree.

    Returns
    -------
    Path
        The generated shared-object path.
    """
    directory.mkdir(parents=True, exist_ok=True)
    library = directory / ("t068_native.dll" if sys.platform == "win32" else "t068_native.so")
    subprocess.run(["g++", "-std=c++17", "-O3", "-fPIC", "-shared", "-Wall", "-Wextra",
                    "-Werror", str(SOURCE), "-o", str(library)], check=True)
    return library


def open_kernel(path: Path) -> ctypes.CDLL:
    lib = ctypes.CDLL(str(path))
    lib.draw_source_over.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    lib.draw_source_over.restype = ctypes.c_uint32
    lib.draw_batch.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                              ctypes.POINTER(ctypes.c_uint8), ctypes.c_int32, ctypes.c_int32,
                              ctypes.POINTER(ctypes.c_int32), ctypes.c_int32, ctypes.c_uint32,
                              ctypes.c_int32, ctypes.POINTER(ctypes.c_uint8),
                              ctypes.POINTER(Delta), ctypes.c_int32]
    lib.draw_batch.restype = ctypes.c_int32
    return lib


def baseline_blend(src: int, dst: int) -> int:
    """Python reference with Godot's positive-value round-half-up behavior."""
    sa = ((src >> 24) & 255) / 255.0
    if sa <= 0:
        return dst
    da = ((dst >> 24) & 255) / 255.0
    alpha = sa + da * (1 - sa)
    output = int(alpha * 255 + 0.5) << 24
    for index in range(3):
        shift = index * 8
        sc = (src >> shift) & 255
        dc = (dst >> shift) & 255
        output |= min(255, max(0, int((sc * sa + dc * da * (1 - sa)) / alpha + 0.5))) << shift
    return output


def _source(width: int, height: int) -> bytes:
    data = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            index = (y * width + x) * 4
            data[index:index + 4] = bytes(((x * 3 + y * 5) & 255,
                                           (x * 13 + y) & 255, (y * 7) & 255,
                                           (x + y) % 7 * 42))
    return bytes(data)


def _points(width: int, height: int, workload: str) -> list[tuple[int, int]]:
    if workload == "short_4px":
        values = [(x, y) for x in range(16, 48) for y in range(16, 20)]
    elif workload == "round_64px":
        mid = width // 2
        values = [(x, y) for y in range(mid - 32, mid + 32)
                  for x in range(mid - 32, mid + 32)
                  if (x - mid + 0.5) ** 2 + (y - mid + 0.5) ** 2 <= 32 ** 2]
    elif workload == "long_fast":
        values = [(x, y) for x in range(16, width - 16)
                  for y in range(24, 28)]
    elif workload == "self_cross":
        values = ([(x, height // 2) for x in range(16, width - 16)] +
                  [(width // 2, y) for y in range(16, height - 16)] +
                  [(x, height // 2) for x in range(width - 17, 15, -1)])
    elif workload == "fill":
        values = [(x, y) for y in range(16, height - 16)
                  for x in range(16, width - 16)]
    else:
        raise ValueError(workload)
    return values


def call_batch(lib: ctypes.CDLL, source: bytes, width: int, height: int,
               coords: list[tuple[int, int]], rgba: int, operation: int = 0,
               mask: bytes | None = None, capacity: int | None = None) -> tuple[int, bytes, list[Delta]]:
    raw = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
    output = (ctypes.c_uint8 * len(source))()
    points = (ctypes.c_int32 * (len(coords) * 2))(*(v for xy in coords for v in xy))
    cap = len(coords) if capacity is None else capacity
    deltas = (Delta * max(1, cap))()
    selected = (ctypes.c_uint8 * len(mask)).from_buffer_copy(mask) if mask is not None else None
    result = lib.draw_batch(raw, output, width, height, points, len(coords), rgba, operation,
                            selected, deltas, cap)
    return result, bytes(output), list(deltas[:max(0, result)])


def _stats(samples: list[float]) -> dict[str, float]:
    sorted_ms = sorted(samples)
    return {"median_ms": round(statistics.median(sorted_ms), 4),
            "p95_ms": round(sorted_ms[min(len(samples) - 1, int(len(samples) * 0.95 + 0.999999) - 1)], 4)}


def benchmark(lib: ctypes.CDLL, output_path: Path, rounds: int = 7) -> dict:
    """Measure warm CPU kernel and Python FFI boundary independently."""
    records = []
    for size in (128, 256, 512):
        source = _source(size, size)
        raw = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
        output = (ctypes.c_uint8 * len(source))()
        for name in ("short_4px", "round_64px", "long_fast", "self_cross", "fill"):
            coords = _points(size, size, name)
            points = (ctypes.c_int32 * (len(coords) * 2))(*(v for pair in coords for v in pair))
            deltas = (Delta * len(coords))()
            times: list[float] = []
            outcome = -1
            for iteration in range(rounds + 2):
                t0 = time.perf_counter_ns()
                outcome = lib.draw_batch(raw, output, size, size, points, len(coords),
                                         0x88774422, 0, None, deltas, len(coords))
                duration = (time.perf_counter_ns() - t0) / 1_000_000
                if iteration >= 2:
                    times.append(duration)
                if outcome < 0:
                    raise RuntimeError(f"kernel error {outcome}: {size} {name}")
            records.append({"region": size, "workload": name, "candidates": len(coords),
                            "changed": outcome, "bytes_copied": len(source),
                            "undo_delta_bytes": outcome * ctypes.sizeof(Delta),
                            **_stats(times)})
    # No-op FFI call measures ctypes/Python dispatch, not Godot GDExtension overhead.
    empty_source = (ctypes.c_uint8 * 4)()
    empty_result = (ctypes.c_uint8 * 4)()
    overhead_ns = []
    for iteration in range(1024):
        t0 = time.perf_counter_ns()
        if lib.draw_batch(empty_source, empty_result, 1, 1, None, 0, 0, 0, None, None, 0) != 0:
            raise RuntimeError("empty call failed")
        if iteration >= 24:
            overhead_ns.append((time.perf_counter_ns() - t0) / 1000)
    payload = {"schema": "t068-native-v1", "platform": platform.platform(),
               "compiler": subprocess.run(["g++", "--version"], capture_output=True,
                                          text=True, check=True).stdout.splitlines()[0],
               "native_boundary": "Python ctypes, not Godot/GDExtension",
               "dispatch_us": {"median": round(statistics.median(overhead_ns), 3),
                               "p95": round(sorted(overhead_ns)[949], 3)},
               "rounds": rounds, "rows": records}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("/tmp/t068-native"))
    parser.add_argument("--output", type=Path, default=Path("/tmp/t068-native.json"))
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--godot-vectors", type=Path)
    args = parser.parse_args()
    lib = open_kernel(build(args.build_dir))
    if args.godot_vectors:
        vectors = json.loads(args.godot_vectors.read_text(encoding="utf-8"))
        for entry in vectors["blend_vectors"]:
            expected = int(entry["result"])
            actual = lib.draw_source_over(int(entry["src"]), int(entry["dst"]))
            if actual != expected:
                raise AssertionError(f"Godot native rounding mismatch {entry}: {actual}")
        fixture = vectors["kernel_fixture"]
        covered = [(int(pair[0]), int(pair[1])) for pair in fixture["covered_xy"]]
        # Duplicate some covered pixels: one-hit-per-gesture semantics must survive.
        repeated = covered + covered[:min(7, len(covered))]
        changed, result, _ = call_batch(lib, bytes.fromhex(fixture["before_hex"]),
                                         int(fixture["width"]), int(fixture["height"]),
                                         repeated, int(fixture["rgba"]))
        if changed != fixture["changed"] or result.hex() != fixture["after_hex"]:
            raise AssertionError("Godot gesture and C++ batch produce different exact RGBA8")
        print(f"T068_NATIVE_GODOT_PARITY_PASSED {len(vectors['blend_vectors'])} vectors "
              f"and {changed} edited pixels")
    results = benchmark(lib, args.output, args.rounds)
    print(f"T068_NATIVE_PASSED {len(results['rows'])} timed cases, file={args.output}")


if __name__ == "__main__":
    main()
