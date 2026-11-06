#!/usr/bin/env python3
"""T-068 optional Cairo CPU compositor screening (no production dependency).

The harness compares a pinned *runtime-reported* system Cairo and the existing
bounded C++ kernel against the same canonical straight-RGBA8 rectangle oracle.
Cairo operates on native-endian premultiplied ARGB32, so conversion is measured
and correctness discrepancies are reported, never silently fixed.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import math
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


ROOT = Path(__file__).resolve().parents[2]
RGBA = tuple[int, int, int, int]
Operation = Literal["source_over", "replace", "erase"]


@dataclass(frozen=True)
class Case:
    name: str
    operation: Operation
    paint: RGBA
    opaque_source: bool


CASES: tuple[Case, ...] = (
    Case("opaque_replace", "replace", (219, 41, 87, 255), True),
    Case("opaque_over", "source_over", (219, 41, 87, 255), True),
    Case("transparent_over", "source_over", (101, 223, 52, 0), False),
    Case("translucent_over", "source_over", (219, 41, 87, 129), False),
    Case("translucent_replace", "replace", (219, 41, 87, 129), False),
    Case("erase", "erase", (0, 0, 0, 0), False),
)


def _round8(value: float) -> int:
    """Round positive floats with the C++/Godot half-away-from-zero rule."""
    return min(255, max(0, int(math.floor(value + 0.5))))


def source_over(source: RGBA, destination: RGBA) -> RGBA:
    """Apply canonical DrawingEditSession._blend straight-RGBA8 semantics."""
    sa = source[3] / 255.0
    if sa <= 0:
        return destination
    da = destination[3] / 255.0
    alpha = sa + da * (1.0 - sa)
    rgb = tuple(_round8((source[c] * sa + destination[c] * da * (1.0 - sa)) / alpha)
                for c in range(3))
    return (rgb[0], rgb[1], rgb[2], _round8(alpha * 255.0))


def fixture(side: int, opaque: bool) -> bytes:
    """Construct varied source colors including nonzero hidden RGB at alpha zero."""
    if side < 8 or side > 512:
        raise ValueError("Benchmark side must be within [8, 512]")
    data = bytearray(side * side * 4)
    for y in range(side):
        for x in range(side):
            i = (y * side + x) * 4
            a = 255 if opaque else (0, 1, 64, 128, 254, 255)[(x + y * 3) % 6]
            data[i:i + 4] = bytes(((x * 19 + y * 11 + 31) & 255,
                                   (x * 7 + y * 23 + 53) & 255,
                                   (x * 3 + y * 17 + 79) & 255, a))
    return bytes(data)


def region(side: int) -> tuple[int, int, int, int]:
    """Choose the same interior hard-edged rectangular gesture for each backend."""
    return side // 4, side // 4, side // 2, side // 2


def reference_output(source: bytes, side: int, rect: tuple[int, int, int, int],
                     paint: RGBA, operation: Operation) -> bytes:
    """Build the exact canonical result without using a native backend."""
    output = bytearray(source)
    x0, y0, width, height = rect
    for y in range(y0, y0 + height):
        for x in range(x0, x0 + width):
            i = (y * side + x) * 4
            old = tuple(source[i:i + 4])
            if operation == "erase":
                after: RGBA = (0, 0, 0, 0)
            elif operation == "replace":
                after = paint
            else:
                after = source_over(paint, (old[0], old[1], old[2], old[3]))
            output[i:i + 4] = bytes(after)
    return bytes(output)


def rgba_to_premultiplied_bgra(source: bytes) -> bytearray:
    """Convert canonical RGBA8 to Cairo's little-endian premultiplied ARGB32.

    Unchanged transparent hidden RGB is necessarily lost in this representation.
    """
    output = bytearray(len(source))
    for i in range(0, len(source), 4):
        r, g, b, a = source[i:i + 4]
        output[i:i + 4] = bytes(((b * a + 127) // 255,
                                  (g * a + 127) // 255,
                                  (r * a + 127) // 255, a))
    return output


def premultiplied_bgra_to_rgba(source: bytes | bytearray) -> bytes:
    """Convert Cairo's ARGB32 back to straight RGBA8 with deterministic rounding."""
    output = bytearray(len(source))
    for i in range(0, len(source), 4):
        b, g, r, a = source[i:i + 4]
        if a == 0:
            output[i:i + 4] = b"\x00\x00\x00\x00"
        else:
            output[i:i + 4] = bytes((min(255, (r * 255 + a // 2) // a),
                                    min(255, (g * 255 + a // 2) // a),
                                    min(255, (b * 255 + a // 2) // a), a))
    return bytes(output)


class CairoCPU:
    """The installed Cairo C API, loaded dynamically for an optional CPU trial.

    Parameters
    ----------
    library : str, optional
        Override the discovered Cairo shared library for controlled tests.
    """

    def __init__(self, library: str | None = None) -> None:
        if sys.byteorder != "little":
            raise RuntimeError("Benchmark's BGRA conversion requires little-endian CPU")
        path = library or ctypes.util.find_library("cairo")
        if not path:
            raise RuntimeError("Optional libcairo is not installed")
        lib = ctypes.CDLL(path)
        signatures: dict[str, tuple[object, tuple[object, ...]]] = {
            "cairo_version_string": (ctypes.c_char_p, ()),
            "cairo_image_surface_create_for_data":
                (ctypes.c_void_p, (ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int)),
            "cairo_surface_status": (ctypes.c_int, (ctypes.c_void_p,)),
            "cairo_surface_flush": (None, (ctypes.c_void_p,)),
            "cairo_surface_destroy": (None, (ctypes.c_void_p,)),
            "cairo_create": (ctypes.c_void_p, (ctypes.c_void_p,)),
            "cairo_status": (ctypes.c_int, (ctypes.c_void_p,)),
            "cairo_destroy": (None, (ctypes.c_void_p,)),
            "cairo_set_operator": (None, (ctypes.c_void_p, ctypes.c_int)),
            "cairo_set_source_rgba":
                (None, (ctypes.c_void_p, ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_double)),
            "cairo_rectangle":
                (None, (ctypes.c_void_p, ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_double)),
            "cairo_fill": (None, (ctypes.c_void_p,)),
        }
        for name, (restype, args) in signatures.items():
            function = getattr(lib, name)
            function.restype = restype
            function.argtypes = list(args)
        self._lib = lib
        self.version = lib.cairo_version_string().decode("ascii")

    def render(self, source: bytes, side: int, rect: tuple[int, int, int, int],
               paint: RGBA, operation: Operation) -> tuple[bytes, float]:
        """Render one Cairo rectangle and return RGBA8 plus draw-only microseconds.

        Raises
        ------
        ValueError
            If the input bytes or rectangle are invalid.
        RuntimeError
            If the Cairo surface/context fails.
        """
        if len(source) != side * side * 4 or len(paint) != 4 or any(c < 0 or c > 255 for c in paint):
            raise ValueError("Invalid RGBA8 source or paint")
        x, y, width, height = rect
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > side or y + height > side:
            raise ValueError("Rectangle must fit the source")
        data = rgba_to_premultiplied_bgra(source)
        native = (ctypes.c_uint8 * len(data)).from_buffer(data)
        cairo = self._lib
        surface = cairo.cairo_image_surface_create_for_data(native, 0, side, side, side * 4)
        if not surface:
            raise RuntimeError("Cairo returned a null surface")
        try:
            if cairo.cairo_surface_status(surface):
                raise RuntimeError("Cairo rejected image surface")
            context = cairo.cairo_create(surface)
            if not context:
                raise RuntimeError("Cairo returned a null context")
            try:
                # Cairo operator enum: CLEAR=0, SOURCE=1, OVER=2.
                cairo.cairo_set_operator(context, {"erase": 0, "replace": 1,
                                                    "source_over": 2}[operation])
                cairo.cairo_set_source_rgba(context, *(channel / 255.0 for channel in paint))
                start = time.perf_counter_ns()
                cairo.cairo_rectangle(context, x, y, width, height)
                cairo.cairo_fill(context)
                cairo.cairo_surface_flush(surface)
                draw_us = (time.perf_counter_ns() - start) / 1000.0
                if cairo.cairo_status(context) or cairo.cairo_surface_status(surface):
                    raise RuntimeError("Cairo failed during rectangle compositing")
            finally:
                cairo.cairo_destroy(context)
        finally:
            cairo.cairo_surface_destroy(surface)
        return premultiplied_bgra_to_rgba(data), draw_us


class CheckedNativeKernel:
    """Existing checked C++ raster kernel compiled into a temporary directory."""

    def __init__(self, library: Path) -> None:
        lib = ctypes.CDLL(str(library))
        function = lib.draw_batch_checked
        function.restype = ctypes.c_int32
        function.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p,
                             ctypes.c_uint64, ctypes.c_int32, ctypes.c_int32,
                             ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                             ctypes.c_uint32, ctypes.c_int32, ctypes.c_void_p,
                             ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
                             ctypes.c_int32]
        self._call = function

    def render(self, source: bytes, side: int, rect: tuple[int, int, int, int],
               paint: RGBA, operation: Operation) -> tuple[bytes, float]:
        """Execute the same pixel set with the checked C++ kernel."""
        x0, y0, width, height = rect
        coords = [component for y in range(y0, y0 + height)
                  for x in range(x0, x0 + width) for component in (x, y)]
        count = width * height
        points = (ctypes.c_int32 * (2 * count))(*coords)
        data = (ctypes.c_uint8 * len(source)).from_buffer_copy(source)
        result = (ctypes.c_uint8 * len(source))()
        deltas = (ctypes.c_uint8 * (12 * count))()
        rgba = sum(channel << (index * 8) for index, channel in enumerate(paint))
        start = time.perf_counter_ns()
        changed = self._call(data, len(source), result, len(source), side, side,
                             points, ctypes.sizeof(points), count, rgba,
                             {"source_over": 0, "erase": 1, "replace": 2}[operation],
                             None, 0, deltas, ctypes.sizeof(deltas), count)
        elapsed = (time.perf_counter_ns() - start) / 1000.0
        if changed < 0:
            raise RuntimeError(f"Native checked raster kernel failed: {changed}")
        return bytes(result), elapsed


def mismatch_counts(observed: bytes, expected: bytes,
                    source: bytes, side: int, rect: tuple[int, int, int, int]) -> dict[str, int]:
    """Count pixels (not channels) that differ in touched and untouched areas."""
    if len(observed) != len(expected) or len(source) != len(expected):
        raise ValueError("Pixel buffers must have identical lengths")
    x0, y0, width, height = rect
    touched = 0
    untouched = 0
    lost_hidden_rgb = 0
    for index in range(side * side):
        offset = index * 4
        if observed[offset:offset + 4] == expected[offset:offset + 4]:
            continue
        x, y = index % side, index // side
        if x0 <= x < x0 + width and y0 <= y < y0 + height:
            touched += 1
        else:
            untouched += 1
        if source[offset + 3] == 0 and any(source[offset:offset + 3]):
            lost_hidden_rgb += 1
    return {"touched": touched, "untouched": untouched,
            "lost_hidden_rgb": lost_hidden_rgb}


def compile_native(destination: Path) -> Path:
    """Compile the repository's unmodified reference C++ kernel, not a vendored library."""
    compiler = shutil.which("g++")
    if compiler is None:
        raise RuntimeError("g++ is required for the reference kernel")
    library = destination / "libt068_checked.so"
    subprocess.run([compiler, "-std=c++17", "-O2", "-fPIC", "-shared", "-Wall",
                    "-Wextra", "-Werror", str(ROOT / "tools/benchmarks/t068_raster_kernel.cpp"),
                    "-o", str(library)], check=True, capture_output=True, text=True, timeout=90)
    return library


def benchmark(sides: tuple[int, ...] = (32, 64, 128), trials: int = 7) -> dict[str, object]:
    """Run correctness and operation-level CPU measurements.

    Each result reports two different boundaries: a C++ kernel call on already
    canonical buffers and a Cairo draw call (plus full RGBA conversion). These
    have different setup costs and are NOT a controlled backend speed contest.
    """
    if trials < 3 or trials > 101:
        raise ValueError("Use 3–101 trials")
    cairo = CairoCPU()
    measurements: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="t068-cairo-") as temporary:
        native = CheckedNativeKernel(compile_native(Path(temporary)))
        for side in sides:
            for case in CASES:
                source = fixture(side, case.opaque_source)
                rect = region(side)
                expected = reference_output(source, side, rect, case.paint, case.operation)
                kernel_times: list[float] = []
                cairo_total: list[float] = []
                cairo_draw: list[float] = []
                disparities: dict[str, int] | None = None
                for _ in range(trials):
                    baseline, elapsed = native.render(source, side, rect, case.paint,
                                                      case.operation)
                    if baseline != expected:
                        raise AssertionError(f"Checked C++ output differs from canonical RGBA8: {side} {case.name}")
                    kernel_times.append(elapsed)
                    start = time.perf_counter_ns()
                    rendered, draw_us = cairo.render(source, side, rect, case.paint, case.operation)
                    cairo_total.append((time.perf_counter_ns() - start) / 1000.0)
                    cairo_draw.append(draw_us)
                    mismatch = mismatch_counts(rendered, expected, source, side, rect)
                    if disparities is not None and mismatch != disparities:
                        raise AssertionError(f"Non-deterministic Cairo pixels: {side} {case.name}")
                    disparities = mismatch
                assert disparities is not None
                measurements.append({"side": side, "operation": case.name,
                                     "source_is_opaque": case.opaque_source,
                                     "pixel_mismatches": disparities,
                                     "kernel_median_us": round(statistics.median(kernel_times), 3),
                                     "cairo_draw_median_us": round(statistics.median(cairo_draw), 3),
                                     "cairo_total_median_us": round(statistics.median(cairo_total), 3),
                                     "trials": trials})
    return {
        "ticket": "T-068", "date": "2026-11-04",
        "comparison": "optional Cairo CPU image-surface screening against checked C++ kernel and canonical RGBA8",
        "cairo_version": cairo.version, "cairo_library": ctypes.util.find_library("cairo"),
        "checked_cpp_kernel": "tools/benchmarks/t068_raster_kernel.cpp (built locally with -O2)",
        "platform": {"byteorder": sys.byteorder, "os": sys.platform},
        "method": "hard-edged half-tile rectangle, fully detached output; source to premultiplied ARGB32 and back for Cairo",
        "limitations": [
            "Cairo is an optional comparator, not the required Blend2D or Skia backend",
            "Cairo ARGB32 is premultiplied and cannot preserve arbitrary hidden RGB through round-trip conversion",
            "The checked C++ call excludes coordinate/input setup; Cairo draw-only excludes pixel conversions; total timings include Cairo conversion and Python loops",
            "No claim of equivalent native input semantics, multi-layer composition, GPU upload, production latency, or hardware performance",
            "No third-party source or binary is bundled, downloaded, or installed in Drawing/Atlas",
        ],
        "measurements": measurements,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trials", type=int, default=7)
    parser.add_argument("--runs", type=int, default=2, choices=[1, 2, 3])
    parser.add_argument("--sides", type=int, nargs="+", default=[32, 64, 128])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.sides or any(side < 8 or side > 512 for side in args.sides):
        parser.error("All image sides must be 8–512")
    observations = [benchmark(tuple(args.sides), args.trials) for _ in range(args.runs)]
    versions = {sample["cairo_version"] for sample in observations}
    if len(versions) != 1:
        raise RuntimeError("Cairo runtime changed between benchmark runs")
    data = {"ticket": "T-068", "runs": observations}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    total = sum(len(run["measurements"]) for run in observations)
    mismatched = sum(1 for run in observations for sample in run["measurements"]
                     if any(sample["pixel_mismatches"].values()))
    print(f"T068_CAIRO_CPU_PASSED: {total} verified cases across {args.runs} runs; {mismatched} non-parity cases")
    print("A non-parity case is evidence of a pixel-format/rounding mismatch, not an accepted backend.")


if __name__ == "__main__":
    main()
