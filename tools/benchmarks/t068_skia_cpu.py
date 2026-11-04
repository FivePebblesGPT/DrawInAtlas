#!/usr/bin/env python3
"""T-068 opt-in Skia CPU raster parity screen; never a production dependency.

Uses the pinned skia-python 144.1 CPython 3.13 wheel only when installed into
an *external* Python environment. RasterDirect allows a straight RGBA8 surface
and exposes a separate premultiplied-BGRA path for comparison. Every rectangular
result is checked against an independent canonical oracle and checked C++ kernel.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import statistics
import sys
import tempfile
import time
from pathlib import Path
from types import ModuleType
from typing import Literal

from t068_cairo_cpu import (
    CASES, Case, CheckedNativeKernel, RGBA, Operation, compile_native,
    fixture, mismatch_counts, premultiplied_bgra_to_rgba,
    reference_output, region, rgba_to_premultiplied_bgra,
)
from t068_blend2d_cpu import crop_rgba, paste_rgba

WHEEL_SHA256 = "a008767c16671f3704ea5e1a8cee99854047044632c0d71a37105d6b632b816a"
WHEEL_NAME = "skia_python-144.1-cp313-cp313-manylinux_2_28_x86_64.whl"
Scope = Literal["direct_rgba", "premul_full", "premul_region"]
SCOPES: tuple[Scope, ...] = ("direct_rgba", "premul_full", "premul_region")
SKIA_CASES = CASES + (Case("transparent_replace", "replace", (93, 171, 44, 0), False),)


def verify_wheel(wheel: Path) -> None:
    """Reject an unverified or differently tagged binary before live benchmarking."""
    if wheel.name != WHEEL_NAME:
        raise ValueError(f"Wrong Skia wheel/tag: {wheel.name}")
    with wheel.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != WHEEL_SHA256:
        raise ValueError(f"Unexpected Skia wheel SHA-256: {digest}")


def _validate(source: bytes, side: int, rect: tuple[int, int, int, int],
              paint: RGBA, operation: Operation) -> None:
    if not 8 <= side <= 512 or len(source) != side * side * 4:
        raise ValueError("Invalid side or RGBA8 source length")
    if len(paint) != 4 or any(not isinstance(v, int) or not 0 <= v <= 255 for v in paint):
        raise ValueError("Invalid RGBA8 paint")
    if operation not in ("source_over", "replace", "erase"):
        raise ValueError("Unknown operation")
    x, y, width, height = rect
    if min(x, y) < 0 or min(width, height) <= 0 or x + width > side or y + height > side:
        raise ValueError("Invalid edit rectangle")


class SkiaCPU:
    """CPU-only SkSurface.MakeRasterDirect with caller-owned detached bytes."""

    def __init__(self) -> None:
        if sys.byteorder != "little":
            raise RuntimeError("Pinned premultiplied BGRA comparison assumes little-endian")
        import skia  # Optional: no Skia import or runtime dependency for ordinary CI.
        self.skia: ModuleType = skia
        self.version: str = skia.__version__
        if self.version != "144.1":
            raise RuntimeError(f"Expected Skia 144.1, got {self.version}")

    def _surface(self, data: bytearray, width: int, height: int, premul: bool):
        skia = self.skia
        info = skia.ImageInfo.Make(
            width, height,
            skia.ColorType.kBGRA_8888_ColorType if premul else skia.ColorType.kRGBA_8888_ColorType,
            skia.AlphaType.kPremul_AlphaType if premul else skia.AlphaType.kUnpremul_AlphaType,
        )
        surface = skia.Surface.MakeRasterDirect(info, data, width * 4)
        if surface is None:
            raise RuntimeError("Skia rejected the raster surface")
        return surface

    def _draw(self, data: bytearray, width: int, height: int,
              rect: tuple[int, int, int, int], paint: RGBA,
              operation: Operation, premul: bool) -> float:
        """Return only the synchronous drawRect call time, excluding setup/copy."""
        skia = self.skia
        surface = self._surface(data, width, height, premul)
        brush = skia.Paint(AntiAlias=False)
        brush.setColor4f(skia.Color4f(*(c / 255.0 for c in paint)))
        brush.setBlendMode({
            "source_over": skia.BlendMode.kSrcOver,
            "replace": skia.BlendMode.kSrc,
            "erase": skia.BlendMode.kClear,
        }[operation])
        start = time.perf_counter_ns()
        surface.getCanvas().drawRect(skia.Rect.MakeXYWH(*rect), brush)
        return (time.perf_counter_ns() - start) / 1000.0

    def render(self, source: bytes, side: int, rect: tuple[int, int, int, int],
               paint: RGBA, operation: Operation,
               scope: Scope = "direct_rgba") -> tuple[bytes, float]:
        """Render a hard-edged rectangle without mutating canonical source.

        direct_rgba: Skia writes directly to detached *straight* RGBA8 bytes.
        premul_full: roundtrip all pixels through premultiplied BGRA8.
        premul_region: roundtrip only a bounded edit rectangle and paste back.
        """
        _validate(source, side, rect, paint, operation)
        if scope == "direct_rgba":
            data = bytearray(source)
            draw_us = self._draw(data, side, side, rect, paint, operation, premul=False)
            return bytes(data), draw_us
        if scope == "premul_full":
            data = rgba_to_premultiplied_bgra(source)
            draw_us = self._draw(data, side, side, rect, paint, operation, premul=True)
            return premultiplied_bgra_to_rgba(data), draw_us
        if scope == "premul_region":
            x, y, width, height = rect
            data = rgba_to_premultiplied_bgra(crop_rgba(source, side, rect))
            draw_us = self._draw(data, width, height, (0, 0, width, height),
                                 paint, operation, premul=True)
            return paste_rgba(source, side, rect, premultiplied_bgra_to_rgba(data)), draw_us
        raise ValueError(f"Unknown scope: {scope}")

    def draw_shape(self, source: bytes, side: int, antialias: bool) -> tuple[bytes, float]:
        """Independent Skia path smoke; no claim of canonical stroke-geometry parity.

        A triangle with fractional vertices exercises the actual CPU shape
        rasterizer. Caller verifies deterministic pixels and bounded changes.
        """
        if side < 32 or side > 512 or len(source) != side * side * 4:
            raise ValueError("Invalid shape surface")
        skia = self.skia
        data = bytearray(source)
        surface = self._surface(data, side, side, premul=False)
        path = skia.Path()
        path.moveTo(side * 0.25 + 0.25, side * 0.25 + 0.5)
        path.lineTo(side * 0.7 + 0.5, side * 0.3 + 0.25)
        path.quadTo(side * 0.65, side * 0.7, side * 0.3 + 0.25, side * 0.75)
        path.close()
        brush = skia.Paint(AntiAlias=antialias)
        brush.setColor4f(skia.Color4f(1.0, 0.0, 0.0, 1.0))
        brush.setBlendMode(skia.BlendMode.kSrcOver)
        start = time.perf_counter_ns()
        surface.getCanvas().drawPath(path, brush)
        return bytes(data), (time.perf_counter_ns() - start) / 1000.0


def randomized_parity(renderer: SkiaCPU, samples: int = 16, side: int = 32) -> dict[str, int]:
    """Seeded independent RGBA inputs; record exceptions instead of hiding loss."""
    if not 1 <= samples <= 256 or not 8 <= side <= 128:
        raise ValueError("Invalid randomized parity budget")
    generator = random.Random(6804144)
    results = {"vectors": 0, "direct_mismatched_pixels": 0, "untouched_mismatched_pixels": 0}
    for _ in range(samples):
        source = generator.randbytes(side * side * 4)
        paint: RGBA = tuple(generator.randrange(256) for _ in range(4))  # type: ignore[assignment]
        rect = (side // 8, side // 8, side * 3 // 4, side * 3 // 4)
        for operation in ("source_over", "replace", "erase"):
            actual, _ = renderer.render(source, side, rect, paint, operation)
            expected = reference_output(source, side, rect, paint, operation)
            mismatch = mismatch_counts(actual, expected, source, side, rect)
            results["vectors"] += 1
            results["direct_mismatched_pixels"] += mismatch["touched"]
            results["untouched_mismatched_pixels"] += mismatch["untouched"]
    if results["untouched_mismatched_pixels"]:
        raise AssertionError("Skia touched canonical pixels outside a hard rectangle")
    return results


def shape_screen(renderer: SkiaCPU, side: int = 64, trials: int = 7) -> list[dict[str, object]]:
    """Path/AA capability and bounded writes, not equivalent brush semantics."""
    source = fixture(side, False)
    results = []
    for aa in (False, True):
        durations = []
        first: bytes | None = None
        for _ in range(trials):
            result, elapsed = renderer.draw_shape(source, side, aa)
            durations.append(elapsed)
            if first is not None and result != first:
                raise AssertionError("Skia shape pixels changed between trials")
            first = result
        assert first is not None
        changed = 0
        fringe = 0
        for pixel in range(side * side):
            i = pixel * 4
            if first[i:i + 4] == source[i:i + 4]:
                continue
            x, y = pixel % side, pixel // side
            if not (side // 5 <= x < 4 * side // 5 and side // 5 <= y < 4 * side // 5):
                raise AssertionError("Skia path altered bytes outside its conservative bounds")
            changed += 1
            if first[i + 3] not in (0, 255):
                fringe += 1
        if changed == 0 or (aa and fringe == 0):
            raise AssertionError("Skia shape did not produce expected coverage")
        results.append({"antialias": aa, "changed_pixels": changed,
                        "partially_covered_alpha_pixels": fringe,
                        "draw_median_us": round(statistics.median(durations), 3),
                        "trials": trials})
    return results


def benchmark(sides: tuple[int, ...] = (32, 64, 128), trials: int = 9,
              randomized_vectors: int = 16) -> dict[str, object]:
    """Screen identical rectangular pixel tasks at explicitly different call boundaries."""
    if not sides or any(side < 8 or side > 512 for side in sides) or not 3 <= trials <= 101:
        raise ValueError("Invalid benchmark sizes or trial count")
    renderer = SkiaCPU()
    measurements: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="t068-skia-kernel-") as directory:
        kernel = CheckedNativeKernel(compile_native(Path(directory)))
        for side in sides:
            for case in SKIA_CASES:
                source = fixture(side, case.opaque_source)
                rect = region(side)
                expected = reference_output(source, side, rect, case.paint, case.operation)
                kernel_us = []
                for _ in range(trials):
                    native, elapsed = kernel.render(source, side, rect, case.paint, case.operation)
                    if native != expected:
                        raise AssertionError(f"Native kernel failed oracle: {side}/{case.name}")
                    kernel_us.append(elapsed)
                for scope in SCOPES:
                    total_us = []
                    draw_us = []
                    disparity: dict[str, int] | None = None
                    for _ in range(trials):
                        start = time.perf_counter_ns()
                        observed, draw_elapsed = renderer.render(
                            source, side, rect, case.paint, case.operation, scope)
                        total_us.append((time.perf_counter_ns() - start) / 1000.0)
                        draw_us.append(draw_elapsed)
                        mismatch = mismatch_counts(observed, expected, source, side, rect)
                        if disparity is not None and disparity != mismatch:
                            raise AssertionError(f"Skia non-deterministic RGBA: {side}/{case.name}/{scope}")
                        disparity = mismatch
                    assert disparity is not None
                    if scope in ("direct_rgba", "premul_region") and disparity["untouched"]:
                        raise AssertionError("Scoped write modified untouched RGBA8")
                    measurements.append({
                        "side": side, "operation": case.name,
                        "source_is_opaque": case.opaque_source, "scope": scope,
                        "pixel_mismatches": disparity,
                        "kernel_median_us": round(statistics.median(kernel_us), 3),
                        "skia_draw_median_us": round(statistics.median(draw_us), 3),
                        "skia_total_median_us": round(statistics.median(total_us), 3),
                        "trials": trials,
                    })
    return {
        "ticket": "T-068", "date": "2026-11-04", "skia_python_version": renderer.version,
        "wheel_sha256": WHEEL_SHA256,
        "comparison": "CPU-only Skia RasterDirect vs canonical straight-RGBA8 oracle and checked C++ kernel",
        "method": "hard-edged half-tile rectangle, three transfer scopes, deterministic alpha/hidden RGB",
        "timing_notes": [
            "Skia draw timing measures only synchronous drawRect, not surface creation or transfer",
            "Skia total timing includes Python surface creation/copy and format conversion, not Godot/GDExtension",
            "C++ timing includes ctypes dispatch and output allocations but excludes points construction",
            "Cross-language timings are diagnostic, not comparable production speedups",
        ],
        "limitations": [
            "Direct unpremultiplied RGBA8 can preserve untouched hidden RGB; transparent-color replacement still loses hidden RGB",
            "Pixel discrepancies and shape AA are reported, not accepted as new canonical brush semantics",
            "No native Skia C++ API benchmark, path/brush/mask equivalence, GPU timings, physical hardware or release integration",
            "Skia wheel is external and used only for this optional Python benchmark",
        ],
        "randomized_parity": randomized_parity(renderer, randomized_vectors),
        "shape_screen": shape_screen(renderer, 64, trials),
        "measurements": measurements,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", type=Path, required=True, help="SHA-pinned wheel uploaded separately")
    parser.add_argument("--runs", type=int, choices=(1, 2, 3), default=2)
    parser.add_argument("--trials", type=int, default=9)
    parser.add_argument("--sides", type=int, nargs="+", default=(32, 64, 128))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    verify_wheel(args.wheel)
    runs = [benchmark(tuple(args.sides), args.trials) for _ in range(args.runs)]
    summary = {"ticket": "T-068", "wheel": WHEEL_NAME, "runs": runs}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    count = sum(len(run["measurements"]) for run in runs)
    mismatched = sum(bool(any(row["pixel_mismatches"].values()))
                     for run in runs for row in run["measurements"])
    print(f"T068_SKIA_CPU_PASSED: {count} verified rectangle cases across {len(runs)} runs; "
          f"{mismatched} pixel-nonparity cases")
    print("Shape results are independent AA footprints, not a canonical Drawing brush equivalence.")


if __name__ == "__main__":
    main()
