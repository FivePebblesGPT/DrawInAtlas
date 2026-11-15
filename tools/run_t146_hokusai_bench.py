#!/usr/bin/env python3
"""T-146 strict software-X11 96px Brush benchmark (real Godot process per trial).

Native-required Hokusai uses its independent alpha oracle; Legacy/NativeHard
retain the existing T-095 exact-opaque-red source oracle. A log success marker
is necessary but NEVER sufficient without a zero process exit and complete
100-event, 512x512 observations. Generated logs/JSON are local evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
BACKENDS = ("Legacy", "NativeHard", "Hokusai")
PREFIX = {"Legacy": "T095_FULL_CANVAS", "NativeHard": "T095_FULL_CANVAS",
          "Hokusai": "T146_HOKUSAI"}
SCRIPT = {"Legacy": "t095_full_canvas_brush_native.gd",
          "NativeHard": "t095_full_canvas_brush_native.gd",
          "Hokusai": "t146_hokusai_full_canvas_native.gd"}


def fields(line: str) -> dict[str, str]:
    """Read the key=value scalar subset, excluding arbitrary JSON/Vector2 fields."""
    return dict(re.findall(r"([a-z][a-z0-9_]+)=([^\s]+)", line))


def p(values: list[float], q: float) -> float:
    """Nearest-rank percentile, matching the Godot witness's implementation."""
    ordered = sorted(values)
    return ordered[max(0, min(len(ordered) - 1, int(math.ceil(len(ordered) * q)) - 1))]


def verify_run_log(text: str, backend: str, runs: int) -> list[dict[str, Any]]:
    """Reject missing/fallback/partial measurements, even with a valid marker."""
    if backend not in BACKENDS:
        raise ValueError("unknown backend")
    prefix = PREFIX[backend]
    measurements = [fields(l) for l in text.splitlines() if l.startswith(prefix + "_RUN ")]
    if len(measurements) != runs:
        raise ValueError(f"{backend}: expected {runs} complete runs, got {len(measurements)}")
    for idx, m in enumerate(measurements):
        for key, expected in (("index", str(idx)), ("backend", backend),
                              ("source_pixels", "262144"), ("width_px", "96"),
                              ("input_events", "100")):
            if m.get(key) != expected:
                raise ValueError(f"{backend} run {idx}: {key}={m.get(key)!r}, expected {expected}")
        for key in ("total_to_postdraw_ms", "release_to_commit_ms", "stage_cpu_ms"):
            if key not in m or not math.isfinite(float(m[key])) or float(m[key]) < 0:
                raise ValueError(f"{backend} run {idx}: missing/nonfinite {key}")
    if backend == "Hokusai":
        identities = [fields(l) for l in text.splitlines() if l.startswith("T146_IDENTITY ")]
        if len(identities) != 1 or identities[0].get("backend") != backend or identities[0].get("preset") != "hard":
            raise ValueError("Hokusai native/backend/preset identity missing")
        for k in ("preset_sha256", "native_sha256", "repo_sha"):
            if not re.fullmatch(r"[a-f0-9]{40,64}", identities[0].get(k, "")):
                raise ValueError("Hokusai identity missing hash " + k)
        sources = [fields(l) for l in text.splitlines()
                   if l.startswith("T146_SOURCE label=stroke-")]
        redo_sources = [fields(l) for l in text.splitlines()
                        if l.startswith("T146_SOURCE label=redo-")]
        fill_statuses = [fields(l) for l in text.splitlines()
                         if l.startswith("T146_FILL_STATUS ")]
        framebuffer_samples = [l for l in text.splitlines()
                               if l.startswith("T146_FRAMEBUFFER ")]
        if (len(redo_sources) != runs or len(fill_statuses) != runs or
                len(framebuffer_samples) != 5 * runs):
            raise ValueError("Hokusai source Undo/Redo/framebuffer witness incomplete")
        if len(sources) != runs:
            raise ValueError("Hokusai source histograms missing")
        firsts = [fields(l) for l in text.splitlines()
                  if l.startswith("T146_FIRST_VISIBLE ")]
        native_phases = [fields(l) for l in text.splitlines()
                         if l.startswith("T146_NATIVE_PHASE ")]
        if len(firsts) != runs or len(native_phases) != runs:
            raise ValueError("Hokusai first-visible/native phase samples missing")
        for idx, source in enumerate(sources):
            if firsts[idx].get("index") != str(idx) or native_phases[idx].get("index") != str(idx):
                raise ValueError("Hokusai phase index misaligned")
            down = int(firsts[idx]["down_us"])
            submit = int(firsts[idx]["first_submit_us"])
            post = int(firsts[idx]["first_postdraw_us"])
            if not (0 < down <= submit <= post) or int(firsts[idx]["postdraw_matches"]) < 1:
                raise ValueError("Hokusai preview/postdraw trace incomplete")
            measurements[idx]["first_submit_ms"] = (submit - down) / 1000.
            measurements[idx]["first_postdraw_ms"] = (post - down) / 1000.
            measurements[idx]["native_cpu_ms"] = float(native_phases[idx]["native_cpu_ms"])
            measurements[idx]["marshal_changed_pixels"] = int(native_phases[idx]["native_changed"])
            if source.get("label") != f"stroke-{idx}":
                raise ValueError("Hokusai source histogram run misaligned")
            buckets = ("zero", "alpha_1_63", "alpha_64_127",
                       "alpha_128_191", "alpha_192_254", "alpha_255")
            if sum(int(source[k]) for k in buckets) != 262144:
                raise ValueError("Hokusai alpha histogram does not cover canvas")
            if int(source["covered"]) != 262144 - int(source["zero"]):
                raise ValueError("Hokusai source coverage inconsistent")
            if (redo_sources[idx].get("label") != f"redo-{idx}" or
                    redo_sources[idx].get("sha256") != source.get("sha256")):
                raise ValueError("Hokusai Undo/Redo digest mismatch")
            if (fill_statuses[idx].get("index") != str(idx) or
                    fill_statuses[idx].get("full_coverage") != "true" or
                    fill_statuses[idx].get("holes") != "0" or
                    source.get("zero") != "0" or source.get("nonred") != "0"):
                raise ValueError("Hokusai source is not full-coverage red")
            if (not math.isfinite(float(native_phases[idx]["native_cpu_ms"])) or
                    float(native_phases[idx]["native_cpu_ms"]) <= 0 or
                    int(native_phases[idx]["native_changed"]) <= 0):
                raise ValueError("Hokusai native phases missing activity")
            measurements[idx]["source_coverage"] = int(source["covered"])
            measurements[idx]["source_opaque"] = int(source["alpha_255"])
            measurements[idx]["source_sha256"] = source["sha256"]
        for expected in ("T146_CANCEL_RETRY ", "T146_MASK_HIDDEN_RGB "):
            if not any(line.startswith(expected) for line in text.splitlines()):
                raise ValueError("Hokusai transaction fixture missing " + expected)
    return measurements


def summary(rows: list[dict[str, Any]]) -> dict[str, dict[str, float | int]]:
    metrics = ("total_to_postdraw_ms", "release_to_commit_ms", "stage_cpu_ms",
               "commit_cpu_ms", "compose_cpu_ms", "texture_cpu_ms",
               "max_drain_ms", "max_frame_draw_ms",
               "first_submit_ms", "first_postdraw_ms", "native_cpu_ms",
               "marshal_changed_pixels")
    result: dict[str, dict[str, float | int]] = {}
    for name in metrics:
        values = [float(row[name]) for row in rows if name in row]
        if values:
            result[name] = {"n": len(values), "p50": p(values, .50), "p95": p(values, .95),
                            "max": max(values)}
    return result


def execute(godot: Path, output: Path, timeout: int, backend: str, mode: str,
            index: int, count: int, native_sha: str, repo_sha: str) -> dict[str, Any]:
    import os
    output.mkdir(parents=True, exist_ok=True)
    name = f"{backend.lower()}-{mode}-{index}"
    log = output / f"{name}.log"
    timing = output / f"{name}.time"
    env = os.environ.copy()
    env.update({"DRAWING_BRUSH_BACKEND": backend, "LIBGL_ALWAYS_SOFTWARE": "1",
                "T146_RUNS": str(count), "T095_FULL_CANVAS_RUNS": str(count),
                "T146_NATIVE_SHA256": native_sha, "T146_REPO_SHA": repo_sha})
    command = [
        "/usr/bin/time", "-v", "-o", str(timing),
        "timeout", f"{timeout}s", "xvfb-run", "-a", "-s", "-screen 0 1280x900x24",
        str(godot), "--display-driver", "x11", "--rendering-method",
        "gl_compatibility", "--audio-driver", "Dummy", "--path", "drawing",
        "--script", f"res://tests/{SCRIPT[backend]}",
    ]
    with log.open("wb") as stream:
        proc = subprocess.run(command, cwd=REPO, env=env, stdout=stream,
                              stderr=subprocess.STDOUT, check=False, timeout=timeout + 25)
    body = log.read_text(encoding="utf-8", errors="replace")
    checker = subprocess.run([
        sys.executable, str(REPO / "tools/check_godot_model_log.py"), str(log),
        "--marker", PREFIX[backend] + ("_BENCHMARK_PASSED" if backend == "Hokusai" else "_PASSED")
    ], capture_output=True, text=True, check=False)
    result: dict[str, Any] = {
        "backend": backend, "mode": mode, "index": index, "runs": count,
        "exit": proc.returncode, "checker_exit": checker.returncode,
        "checker_output": checker.stdout.strip(), "command": command,
        "log": log.name, "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    }
    for line in timing.read_text().splitlines():
        if "Maximum resident set size (kbytes):" in line:
            result["peak_rss_kib"] = int(line.rsplit(":", 1)[-1])
        if "User time (seconds):" in line:
            result["user_cpu_s"] = float(line.rsplit(":", 1)[-1])
        if "System time (seconds):" in line:
            result["system_cpu_s"] = float(line.rsplit(":", 1)[-1])
    try:
        result["observations"] = verify_run_log(body, backend, count)
    except (KeyError, TypeError, ValueError) as exc:
        result["validation_error"] = str(exc)
    result["valid"] = (proc.returncode == 0 and checker.returncode == 0 and
                       "observations" in result)
    print(f"{name}: exit={proc.returncode} checker={checker.returncode} "
          f"valid={result['valid']} rss_kib={result.get('peak_rss_kib', 'n/a')}", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cold", type=int, default=3)
    parser.add_argument("--warm", type=int, default=2,
                        help="Gestures within one fresh process; 0 disables warm")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--candidate-only", action="store_true")
    args = parser.parse_args()
    if args.cold < 1 or args.warm not in (0, 2, 3) or args.timeout < 10:
        parser.error("cold >= 1, warm=0|2|3, timeout >= 10")
    native = REPO / "addons/drawing/native/bin/libdrawing_brush.so"
    if not native.is_file():
        parser.error("real native release library missing")
    native_sha = hashlib.sha256(native.read_bytes()).hexdigest()
    repo_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    backends = ["Hokusai"] if args.candidate_only else list(BACKENDS)
    results: list[dict[str, Any]] = []
    for backend in backends:
        for i in range(args.cold):
            results.append(execute(args.godot.resolve(), args.output.resolve(),
                                   args.timeout, backend, "cold", i, 1, native_sha, repo_sha))
        if args.warm:
            results.append(execute(args.godot.resolve(), args.output.resolve(),
                                   args.timeout, backend, "warm", 0, args.warm,
                                   native_sha, repo_sha))
    matrix: dict[str, Any] = {}
    for backend in backends:
        matrix[backend] = {}
        for mode in ("cold", "warm"):
            rows = [obs for result in results if result["backend"] == backend and
                    result["mode"] == mode and result["valid"]
                    for obs in result["observations"]]
            matrix[backend][mode] = {"stats": summary(rows), "n": len(rows)}
    report = {"repository_sha": repo_sha, "native_sha256": native_sha,
              "godot": str(args.godot.resolve()), "runs": results, "matrix": matrix}
    path = args.output.resolve() / "summary.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    print("Summary:", path, "all_valid:", all(r["valid"] for r in results))
    return 0 if all(r["valid"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
