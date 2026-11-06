#!/usr/bin/env python3
"""Isolated Blend2D 0.21.2 CPU parity screen, not a production integration.

Requires a locally built upstream Blend2D shared library and its source tree.
No native binary/source is committed to the repository. Two rendering scopes
are compared: a full premultiplied tile and the clipped edit rectangle only.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from t068_cairo_cpu import (
    CASES, CheckedNativeKernel, RGBA, Operation, compile_native, fixture,
    mismatch_counts, premultiplied_bgra_to_rgba, reference_output, region,
    rgba_to_premultiplied_bgra,
)

ROOT = Path(__file__).resolve().parents[2]
PINNED_SOURCE_SHA256 = "234ba57a64153c96885a6271f15fdcf6c594ac8cb03adaad19abb8d3b2b533fa"


def verify_archive(archive: Path) -> None:
    """Enforce reproducible upstream source provenance before benchmarking."""
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != PINNED_SOURCE_SHA256:
        raise ValueError(f"Unexpected Blend2D archive SHA-256: {digest}")


def compile_bridge(source: Path, library_dir: Path, destination: Path) -> Path:
    """Compile only the benchmark shim; Blend2D itself must be prebuilt."""
    if not (source / "blend2d/blend2d.h").is_file() or not (library_dir / "libblend2d.so").is_file():
        raise FileNotFoundError("Blend2D headers/shared library missing; build 0.21.2 first")
    compiler = shutil.which("g++")
    if compiler is None:
        raise RuntimeError("g++ required")
    out = destination / "libt068_blend2d_bridge.so"
    subprocess.run([compiler, "-std=c++17", "-O2", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                    "-I", str(source), str(ROOT / "tools/benchmarks/t068_blend2d_bridge.cpp"),
                    "-L", str(library_dir), "-Wl,-rpath," + str(library_dir),
                    "-lblend2d", "-o", str(out)],
                   check=True, capture_output=True, text=True, timeout=90)
    return out


def crop_rgba(source: bytes, side: int, rect: tuple[int, int, int, int]) -> bytes:
    """Take an exact straight-RGBA8 region with no changes to its contents."""
    x, y, width, height = rect
    return b"".join(source[((row * side) + x) * 4:((row * side) + x + width) * 4]
                    for row in range(y, y + height))


def paste_rgba(source: bytes, side: int, rect: tuple[int, int, int, int], patch: bytes) -> bytes:
    """Patch just the edited rows, keeping all *outside* hidden RGB intact."""
    x, y, width, height = rect
    if len(patch) != width * height * 4:
        raise ValueError("Invalid patch length")
    result = bytearray(source)
    for row in range(height):
        start = ((y + row) * side + x) * 4
        result[start:start + width * 4] = patch[row * width * 4:(row + 1) * width * 4]
    return bytes(result)


class Blend2DCPU:
    """Single-thread synchronous Blend2D CPU raster, via a checked C ABI shim."""

    def __init__(self, bridge: Path) -> None:
        if sys.byteorder != "little":
            raise RuntimeError("PRGB32 byte order requires a little-endian host")
        lib = ctypes.CDLL(str(bridge))
        function = lib.t068_blend2d_draw
        function.restype = ctypes.c_int32
        function.argtypes = (ctypes.c_void_p, ctypes.c_uint64,
                             ctypes.c_int32, ctypes.c_int32, ctypes.c_int32,
                             ctypes.c_int32, ctypes.c_int32, ctypes.c_uint32,
                             ctypes.c_int32, ctypes.POINTER(ctypes.c_uint64))
        self._draw = function

    def draw_premul(self, data: bytearray, side: int, rect: tuple[int, int, int, int],
                    paint: RGBA, operation: Operation) -> float:
        """Render preconverted in-place buffer; return context + flush microseconds."""
        if len(data) != side * side * 4 or len(paint) != 4 or any(not 0 <= c <= 255 for c in paint):
            raise ValueError("Invalid premultiplied buffer/paint")
        if operation not in ("source_over", "replace", "erase"):
            raise ValueError("Unknown operation")
        x, y, width, height = rect
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > side or y + height > side:
            raise ValueError("Rectangle must fit")
        native = (ctypes.c_uint8 * len(data)).from_buffer(data)
        argb = paint[3] << 24 | paint[0] << 16 | paint[1] << 8 | paint[2]
        elapsed = ctypes.c_uint64()
        error = self._draw(native, len(data), side, x, y, width, height, argb,
                           {"source_over": 0, "replace": 1, "erase": 2}[operation],
                           ctypes.byref(elapsed))
        if error:
            raise RuntimeError(f"Blend2D failed: {error}")
        return elapsed.value / 1000.0

    def render(self, source: bytes, side: int, rect: tuple[int, int, int, int],
               paint: RGBA, operation: Operation, scope: str = "full_tile") -> tuple[bytes, float]:
        """Convert→render→unpremultiply; full_tile or region_only.

        This measures format loss, not an optimized exact-RGBA production adapter.
        """
        if len(source) != side * side * 4:
            raise ValueError("Source length disagrees with side")
        if scope == "full_tile":
            buffer = rgba_to_premultiplied_bgra(source)
            duration = self.draw_premul(buffer, side, rect, paint, operation)
            return premultiplied_bgra_to_rgba(buffer), duration
        if scope == "region_only":
            x, y, width, height = rect
            if width != height:  # The shim accepts square images only.
                raise ValueError("Region-only test requires a square rectangle")
            if x < 0 or y < 0 or width <= 0 or x + width > side or y + height > side:
                raise ValueError("Rectangle must fit")
            buffer = rgba_to_premultiplied_bgra(crop_rgba(source, side, rect))
            duration = self.draw_premul(buffer, width, (0, 0, width, height), paint, operation)
            result = premultiplied_bgra_to_rgba(buffer)
            return paste_rgba(source, side, rect, result), duration
        raise ValueError("Unknown rendering scope")


def benchmark(bridge: Path, sides: tuple[int, ...] = (32, 64, 128),
              trials: int = 9) -> dict[str, object]:
    """Repeat exact-pixel checks and timings with fixed fixtures and no Godot UI."""
    if not sides or any(side < 8 or side > 512 for side in sides) or not 3 <= trials <= 101:
        raise ValueError("Sides must be 8–512 and trials 3–101")
    blender = Blend2DCPU(bridge)
    measurements: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="t068-blend2d-kernel-") as temporary:
        kernel = CheckedNativeKernel(compile_native(Path(temporary)))
        for side in sides:
            for case in CASES:
                source = fixture(side, case.opaque_source)
                rect = region(side)
                expected = reference_output(source, side, rect, case.paint, case.operation)
                baseline_us: list[float] = []
                for _ in range(trials):
                    baseline, us = kernel.render(source, side, rect, case.paint, case.operation)
                    if baseline != expected:
                        raise AssertionError(f"C++ kernel mismatch: {side}/{case.name}")
                    baseline_us.append(us)
                for scope in ("full_tile", "region_only"):
                    total_us: list[float] = []
                    context_us: list[float] = []
                    disparities: dict[str, int] | None = None
                    for _ in range(trials):
                        start = time.perf_counter_ns()
                        rendered, context_duration = blender.render(source, side, rect, case.paint,
                                                                     case.operation, scope)
                        total_us.append((time.perf_counter_ns() - start) / 1000.0)
                        context_us.append(context_duration)
                        mismatch = mismatch_counts(rendered, expected, source, side, rect)
                        if disparities is not None and mismatch != disparities:
                            raise AssertionError(f"Nondeterministic Blend2D pixels: {side}/{case.name}/{scope}")
                        disparities = mismatch
                    assert disparities is not None
                    if scope == "region_only" and disparities["untouched"]:
                        raise AssertionError("Region-scoped compositor changed bytes outside the edit")
                    measurements.append({
                        "side": side, "operation": case.name, "scope": scope,
                        "source_is_opaque": case.opaque_source, "pixel_mismatches": disparities,
                        "kernel_median_us": round(statistics.median(baseline_us), 3),
                        "blend2d_context_median_us": round(statistics.median(context_us), 3),
                        "blend2d_total_median_us": round(statistics.median(total_us), 3),
                        "trials": trials,
                    })
    return {
        "ticket": "T-068", "date": "2026-11-04", "upstream_version": "0.21.2",
        "source_sha256": PINNED_SOURCE_SHA256,
        "comparison": "optional JIT Blend2D CPU vs checked C++ and exact RGBA8 oracle",
        "method": "square hard-edge half-tile rectangle, single-thread sync; full-tile or edit-region PRGB32 roundtrip",
        "checked_cpp_kernel": "tools/benchmarks/t068_raster_kernel.cpp (-O2)",
        "timing_notes": [
            "Blend2D context measures begin, set_comp_op, set_fill_style, fill_rect and synchronous end, excluding conversions",
            "Blend2D total includes Python conversion, ctypes dispatch and reconstruction, not native-only end-to-end cost",
            "Checked kernel timing includes ctypes call and already allocated points/buffers; it excludes Python point preparation",
            "Each operation is independently verified; different boundaries and language overhead prohibit speedup claims",
        ],
        "limitations": [
            "Blend2D PRGB32 loses transparent hidden RGB on direct full-tile conversion",
            "Region-scoped conversion preserves untouched RGBA8 exactly but may still disagree on touched alpha rounding",
            "No masks, brush coverage, path antialiasing, multi-layer Godot publication, production app, or physical GPU timing",
            "No Blend2D or bridge binary/source added as a Drawing/Atlas runtime dependency",
        ],
        "measurements": measurements,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True, help="Original Blend2D 0.21.2 source tar.gz")
    parser.add_argument("--source", type=Path, required=True, help="Extracted source tree")
    parser.add_argument("--library-dir", type=Path, required=True, help="Directory with libblend2d.so")
    parser.add_argument("--trials", type=int, default=9)
    parser.add_argument("--runs", type=int, default=2, choices=[1, 2, 3])
    parser.add_argument("--sides", type=int, nargs="+", default=[32, 64, 128])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    verify_archive(args.archive)
    with tempfile.TemporaryDirectory(prefix="t068-blend2d-bridge-") as temporary:
        bridge = compile_bridge(args.source, args.library_dir, Path(temporary))
        observations = [benchmark(bridge, tuple(args.sides), args.trials) for _ in range(args.runs)]
    output = {"ticket": "T-068", "runs": observations}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    total = sum(len(run["measurements"]) for run in observations)
    nonparity = sum(any(row["pixel_mismatches"].values()) for run in observations
                    for row in run["measurements"])
    print(f"T068_BLEND2D_CPU_PASSED: {total} verified cases across {args.runs} runs; {nonparity} non-parity cases")
    print("No hidden-RGB/rounding discrepancy is accepted as a production backend result.")


if __name__ == "__main__":
    main()
