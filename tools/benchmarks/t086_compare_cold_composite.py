#!/usr/bin/env python3
"""Compare T-086 cold CPU compositing against the pinned pre-fast-path renderer.

Both isolated standalone projects contain the same current Drawing model and
benchmark workload. Only their ``renderer.gd`` differs. No frame presentation,
GPU upload, physical latency, or Windows/real GPU speed is measured.

Usage::

    python3 tools/benchmarks/t086_compare_cold_composite.py --godot godot
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
BASELINE = ROOT / "tools/benchmarks/fixtures/t086_pre_cold_renderer.gd.txt"
BASELINE_SHA256 = "3606b8c157c5e33ebad1feefd32ed8ed4a99e19e363ea79e3e0cf880b3543532"
PREFIX = "T086_COLD_BENCH_JSON "


def execute(command: list[str], timeout_seconds: int = 240) -> str:
    """Execute a pinned local command, preserving bounded diagnostics on failure."""
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            check=False, timeout=timeout_seconds)
    output = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR:" in output or "T086_COLD_BENCH_FAILED" in output:
        raise RuntimeError(f"Cold renderer command failed ({result.returncode}): "
                           f"{' '.join(command)}\n{output[-5000:]}")
    return output


def stage_project(godot: str, project: Path, renderer_source: bytes | None = None) -> None:
    """Stage a fresh project and import its chosen renderer before Godot tests."""
    execute([sys.executable, str(ROOT / "tools/build_drawing_app.py"),
             "--output", str(project)], timeout_seconds=120)
    if renderer_source is not None:
        (project / "addons/drawing/renderer.gd").write_bytes(renderer_source)
    execute([godot, "--headless", "--editor", "--path", str(project),
             "--import", "--quit"])


def measure(godot: str, project: Path) -> dict[str, Any]:
    output = execute([godot, "--headless", "--path", str(project), "--script",
                      "res://tests/renderer_cold_benchmark.gd"])
    if "T086_COLD_BENCH_PASSED" not in output:
        raise RuntimeError(f"Benchmark success marker absent: {output[-5000:]}")
    rows = [line[len(PREFIX):] for line in output.splitlines() if line.startswith(PREFIX)]
    if len(rows) != 1:
        raise RuntimeError("Expected one cold renderer metrics record")
    return json.loads(rows[0])


def compare(godot: str) -> dict[str, Any]:
    """Return paired results while rejecting fixture drift or pixel mismatch."""
    if hashlib.sha256(BASELINE.read_bytes()).hexdigest() != BASELINE_SHA256:
        raise RuntimeError("Historical T-086 renderer fixture digest mismatch")
    with tempfile.TemporaryDirectory(prefix="drawing-t086-cold-") as temp:
        original = Path(temp) / "before"
        improved = Path(temp) / "after"
        stage_project(godot, original, BASELINE.read_bytes())
        stage_project(godot, improved)
        before = measure(godot, original)
        after = measure(godot, improved)
    for field in ("engine", "samples_per_case", "viewport_source", "storage_stride", "layer_count"):
        if before[field] != after[field]:
            raise RuntimeError(f"Cold benchmark environment/workload mismatch: {field}")
    for case in ("opaque", "alpha", "empty_alpha"):
        if before["cases"][case]["sha256"] != after["cases"][case]["sha256"]:
            raise RuntimeError(f"Byte-exact cold render mismatch: {case}")
    return {"before": before, "after": after}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    output = compare(args.godot)
    print(f"Engine: {output['after']['engine']} | 256x256 source viewport | "
          f"two 128x128-stride layers | nine measured runs/case")
    for case in ("opaque", "alpha", "empty_alpha"):
        before = output["before"]["cases"][case]
        after = output["after"]["cases"][case]
        print(f"{case}: median/p95 CPU ms "
              f"{before['median_ms']:.2f}/{before['p95_ms']:.2f} -> "
              f"{after['median_ms']:.2f}/{after['p95_ms']:.2f}; "
              "SHA-256 pixel parity confirmed")
    print("T086_COLD_COMPARISON_PASSED")


if __name__ == "__main__":
    main()
