#!/usr/bin/env python3
"""Compare the pre-T-086 full redraw and new display cache in isolated Godot apps.

The pre-change canvas is copied from a pinned Git commit and *only* annotated
with timing counters. These are CPU submission/upload-call timings rather than
physical display latency. Both apps retain the same current document model,
scene, test case, software renderer and standalone staging workflow.

Run from the repository root, with Godot 4.8-beta2 and Xvfb installed::

    python3 tools/benchmarks/t086_compare_viewport.py --godot godot

The script creates temporary projects and never modifies canonical addons or
checks in generated drawing/addons. Processes are sequential, not simultaneous.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
# Historical T-085 canvas. Keep the fixture byte-identical to that pre-cache
# source so the benchmark survives `git am` (which changes commit SHAs) and
# downstream squash merges (which remove intermediate commits entirely).
PRE_T086_FIXTURE = ROOT / "tools/benchmarks/fixtures/t086_pre_cache_canvas.gd.txt"
PRE_T086_SHA256 = "0c5ae9dfab57891170ea0d7119b76463c316c0ce08308f5f9b4b853ec4b825bb"
BENCH_MARKER = "T086_BENCH_JSON "


def replace_once(source: str, old: str, new: str) -> str:
    """Replace one known source probe site, rejecting ambiguous drift.

    Parameters
    ----------
    source : str
        Original source text.
    old : str
        Expected source fragment.
    new : str
        Probe replacement.

    Returns
    -------
    str
        Instrumented source text.

    Raises
    ------
    ValueError
        The pinned baseline no longer matches the probe's source contract.
    """
    if source.count(old) != 1:
        raise ValueError(f"Expected one probe insertion site; found {source.count(old)}: {old!r}")
    return source.replace(old, new, 1)


def baseline_canvas(original: str) -> str:
    """Add observational timing probes to the pre-cache canvas without changing rendering."""
    s = replace_once(original,
        "var _frame_textures: Array[ImageTexture] = []",
        "var _frame_textures: Array[ImageTexture] = []\nvar last_frame_metrics: Dictionary = {}")
    s = replace_once(s, "func _draw() -> void:\n\t_frame_textures.clear()", """func _draw() -> void:
\tvar frame_start_us: int = Time.get_ticks_usec()
\tvar m: Dictionary = {"tiles_composited": 0, "textures_created": 0,
\t\t"textures_updated": 0, "bytes_uploaded": 0, "source_pixels_rendered": 0,
\t\t"compose_cpu_us": 0, "texture_cpu_us": 0,
\t\t"draw_cpu_us": 0, "cache_bytes_estimate": 0}
\t_frame_textures.clear()""")
    s = replace_once(s,
        "\t\t\tvar composite: DrawingResult = DrawingRenderer.render(document, area,\n\t\t\t\t0, 0, 1048576, session)",
        """\t\t\tvar start_compose: int = Time.get_ticks_usec()
\t\t\tvar composite: DrawingResult = DrawingRenderer.render(document, area,
\t\t\t\t0, 0, 1048576, session)
\t\t\tm["compose_cpu_us"] = int(m["compose_cpu_us"]) + Time.get_ticks_usec() - start_compose""")
    s = replace_once(s,
        "\t\t\tvar texture: ImageTexture = ImageTexture.create_from_image(image)\n\t\t\t_frame_textures.append(texture)",
        """\t\t\tvar start_texture: int = Time.get_ticks_usec()
\t\t\tvar texture: ImageTexture = ImageTexture.create_from_image(image)
\t\t\tm["texture_cpu_us"] = int(m["texture_cpu_us"]) + Time.get_ticks_usec() - start_texture
\t\t\tm["textures_created"] = int(m["textures_created"]) + 1
\t\t\tm["tiles_composited"] = int(m["tiles_composited"]) + 1
\t\t\tm["source_pixels_rendered"] = int(m["source_pixels_rendered"]) + area.size.x * area.size.y
\t\t\tm["bytes_uploaded"] = int(m["bytes_uploaded"]) + area.size.x * area.size.y * 4
\t\t\t_frame_textures.append(texture)""")
    return replace_once(s,
        "\tif asset_bounds.has_area():\n\t\tdraw_rect",
        """\tm["draw_cpu_us"] = Time.get_ticks_usec() - frame_start_us
\tlast_frame_metrics = m
\tif asset_bounds.has_area():
\t\tdraw_rect""")


def execute(argv: list[str], *, timeout_s: int) -> str:
    """Run an isolated command and surface its complete log on failure."""
    result = subprocess.run(argv, cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False, timeout=timeout_s)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {argv}\n{result.stdout[-6000:]}")
    if "SCRIPT ERROR:" in result.stdout or "T086_BENCH_FAILED" in result.stdout:
        raise RuntimeError(f"Godot script error: {argv}\n{result.stdout[-6000:]}")
    return result.stdout


def stage_project(path: Path, godot: str) -> None:
    execute([sys.executable, str(ROOT / "tools/build_drawing_app.py"),
        "--output", str(path)], timeout_s=120)
    # Native fonts and SVGs must be imported before running a release script.
    execute([godot, "--headless", "--editor", "--path", str(path),
        "--import", "--quit"], timeout_s=240)


def native_benchmark(project: Path, godot: str) -> dict[str, Any]:
    output = execute(["xvfb-run", "-a", godot, "--display-driver", "x11",
        "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
        "--path", str(project), "--script",
        "res://tests/viewport_cache_benchmark.gd"], timeout_s=240)
    if "T086_BENCH_PASSED" not in output:
        raise RuntimeError(f"Benchmark did not finish: {output[-6000:]}")
    lines = [line[len(BENCH_MARKER):] for line in output.splitlines()
        if line.startswith(BENCH_MARKER)]
    if len(lines) != 1:
        raise RuntimeError("Expected exactly one benchmark JSON record")
    return json.loads(lines[0])


def print_comparison(before: dict[str, Any], after: dict[str, Any]) -> None:
    for zoom in ("1.0", "0.5", "0.25"):
        print(f"\nZoom {zoom} | 12 redraws per phase | median/p95")
        print(f"{'Phase and metric':<30} {'Before':>22} {'Cached':>22}")
        for phase in ("idle", "edits"):
            for name in ("compose_cpu_us", "texture_cpu_us", "frame_ms",
                    "source_pixels_rendered", "bytes_uploaded"):
                left = before[zoom][phase][name]
                right = after[zoom][phase][name]
                print(f"{phase} {name:<24} "
                    f"{left['median']:>10.2f}/{left['p95']:<10.2f} "
                    f"{right['median']:>10.2f}/{right['p95']:<10.2f}")
        print(f"Transition frame (ms): {before[zoom]['zoom_transition']['frame_ms']:.2f} "
            f"before, {after[zoom]['zoom_transition']['frame_ms']:.2f} cached")
    print("\nEnvironment and process high-water memory (KiB):")
    for label, record in (("baseline", before), ("cached", after)):
        print(f"{label}: {json.dumps(record['environment'], sort_keys=True)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Pinned Godot 4.8-beta2 executable")
    parser.add_argument("--baseline-ref", default=None,
        help="Optional historical T-085 commit; default is the verified archived source fixture")
    args = parser.parse_args()

    if args.baseline_ref:
        old_canvas = execute(["git", "show", f"{args.baseline_ref}:addons/drawing/canvas.gd"],
            timeout_s=30)
    else:
        old_bytes = PRE_T086_FIXTURE.read_bytes()
        digest = hashlib.sha256(old_bytes).hexdigest()
        if digest != PRE_T086_SHA256:
            raise RuntimeError(f"Pre-cache fixture digest mismatch: {digest}")
        old_canvas = old_bytes.decode("utf-8")
    with tempfile.TemporaryDirectory(prefix="drawing-t086-compare-") as temporary:
        baseline = Path(temporary) / "baseline"
        cached = Path(temporary) / "cached"
        # Both projects use the current canonical document model and exact test
        # scene. Only the baseline canvas renderer is replaced and instrumented.
        stage_project(baseline, args.godot)
        (baseline / "addons/drawing/canvas.gd").write_text(baseline_canvas(old_canvas))
        stage_project(cached, args.godot)
        before = native_benchmark(baseline, args.godot)
        after = native_benchmark(cached, args.godot)
        if before["environment"]["engine"] != after["environment"]["engine"]:
            raise RuntimeError("Engine mismatch invalidates comparison")
        print_comparison(before, after)
        print("T086_COMPARISON_PASSED")


if __name__ == "__main__":
    main()
