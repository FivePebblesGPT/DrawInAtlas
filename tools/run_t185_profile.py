#!/usr/bin/env python3
"""T-185 strict full-workspace frame-time capture (software X11, native-only).

Each trial is a fresh Godot process with 8 real Drawing workspace gestures:
2 zooms x cold Brush, warm overlap, stationary held Brush, and native Eraser.
Raw logs remain available even when a trial times out or its oracle fails.

The engine callback/viewport measurements are NOT physical input-to-photon.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
EXPECTED = tuple((zoom, kind) for zoom in (0.54, 1.0) for kind in
                 ("cold_brush", "warm_overlap", "held_brush", "eraser"))
FRAME_THRESHOLDS_US = (33_333, 83_333)


def quantile(values: list[float], percentile: float) -> float:
    """Return nearest-rank quantile without interpolating sparse samples."""
    if not values or not 0.0 < percentile <= 1.0:
        raise ValueError("empty sample or invalid quantile")
    ranked = sorted(values)
    return ranked[math.ceil(len(ranked) * percentile) - 1]


def distribution(values: list[float]) -> dict[str, float | int]:
    """Summarize raw timings without hiding tails or incomplete trials."""
    return {"n": len(values), "p50": round(quantile(values, 0.5), 3),
            "p95": round(quantile(values, 0.95), 3),
            "max": round(max(values), 3)}


# Keep diagnostic evidence bounded without losing counts for retained frame records.
MAX_RETAINED_SLOW_CALLBACK_EVENTS = 32


def callback_gap_diagnostics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Pair only consecutive Canvas frames with distinct renderer callbacks.

    A callback belongs to a Canvas frame only if it was stamped by that
    frame's matched session. Missing callbacks break continuity; gestures
    never share a pair. These are CPU/renderer callback periods, **not** FPS,
    physical frame scanout or a causal attribution of any long gap.
    """
    periods_ms: list[float] = []
    long_events: list[dict[str, int | float]] = []
    unmatched = 0
    nonmonotonic = 0
    long_33 = 0
    long_83 = 0
    for row_index, row in enumerate(rows):
        phases = row["frame_phases_us"]
        for frame_index in range(1, len(phases)):
            previous = phases[frame_index - 1]
            current = phases[frame_index]
            if ("frame_post_draw_callback_us" not in previous or
                    "frame_post_draw_callback_us" not in current):
                unmatched += 1
                continue
            previous_us = int(previous["frame_post_draw_callback_us"])
            current_us = int(current["frame_post_draw_callback_us"])
            if previous_us <= 0 or current_us <= previous_us:
                nonmonotonic += 1
                continue
            period_us = current_us - previous_us
            periods_ms.append(period_us / 1000)
            if period_us >= FRAME_THRESHOLDS_US[0]:
                long_33 += 1
            if period_us >= FRAME_THRESHOLDS_US[1]:
                long_83 += 1
                # Retain the most recent outliers, without hiding earlier ones
                # from counts or the complete-period distribution in this window.
                event: dict[str, int | float] = {
                    "row_index": row_index,
                    "frame_index": frame_index,
                    "callback_period_ms": round(period_us / 1000, 3),
                    "canvas_draw_ms": round(int(current.get("full_draw_cpu_us", 0)) / 1000, 3),
                    "previous_canvas_draw_ms": round(int(previous.get("full_draw_cpu_us", 0)) / 1000, 3),
                    "postdraw_delay_ms": round(int(current.get(
                        "frame_end_to_post_draw_us", 0)) / 1000, 3),
                    "pending_input_count": int(current.get("pending_input_count", 0)),
                    "oldest_pending_age_ms": round(int(current.get(
                        "oldest_pending_age_us", 0)) / 1000, 3),
                }
                long_events.append(event)
                if len(long_events) > MAX_RETAINED_SLOW_CALLBACK_EVENTS:
                    long_events.pop(0)
    return {
        "matched_pairs": len(periods_ms),
        "unmatched_pairs": unmatched,
        "rejected_nonmonotonic_pairs": nonmonotonic,
        "matched_period_ms": distribution(periods_ms) if periods_ms else None,
        "long_33ms": long_33,
        "long_83ms": long_83,
        "retained_long_events": len(long_events),
        "omitted_long_events": long_83 - len(long_events),
        "long_events": long_events,
    }



def canvas_draw_cadence_diagnostics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Report gaps between consecutive Canvas *draw ends* in one gesture.

    Unlike renderer callbacks, Canvas draw ends exist even when a callback is
    missing. They describe observed redraw cadence only: no draw means no
    sample, and neither missing frames nor physical scanout can be inferred.
    """
    periods_ms: list[float] = []
    long_events: list[dict[str, int | float | bool]] = []
    callback_pairs = 0
    without_callbacks = 0
    missing_end = 0
    nonmonotonic_end = 0
    long_33 = 0
    long_83 = 0
    for row_index, row in enumerate(rows):
        phases = row["frame_phases_us"]
        for frame_index in range(1, len(phases)):
            previous = phases[frame_index - 1]
            current = phases[frame_index]
            before = int(previous.get("frame_end_us", 0))
            after = int(current.get("frame_end_us", 0))
            if before <= 0 or after <= 0:
                missing_end += 1
                continue
            if after <= before:
                nonmonotonic_end += 1
                continue
            elapsed_us = after - before
            periods_ms.append(elapsed_us / 1000.0)
            before_callback = int(previous.get("frame_post_draw_callback_us", 0))
            after_callback = int(current.get("frame_post_draw_callback_us", 0))
            paired = before_callback > 0 and after_callback > before_callback
            if paired:
                callback_pairs += 1
            else:
                without_callbacks += 1
            long_33 += elapsed_us >= FRAME_THRESHOLDS_US[0]
            if elapsed_us >= FRAME_THRESHOLDS_US[1]:
                long_83 += 1
                long_events.append({
                    "row_index": row_index,
                    "frame_index": frame_index,
                    "gap_ms": round(elapsed_us / 1000, 3),
                    "canvas_draw_cpu_ms": round(int(current.get(
                        "full_draw_cpu_us", 0)) / 1000, 3),
                    "previous_canvas_draw_cpu_ms": round(int(previous.get(
                        "full_draw_cpu_us", 0)) / 1000, 3),
                    "pending_input_count": int(current.get("pending_input_count", 0)),
                    "oldest_pending_age_ms": round(int(current.get(
                        "oldest_pending_age_us", 0)) / 1000, 3),
                    "adjacent_callback_pair": paired,
                })
                if len(long_events) > MAX_RETAINED_SLOW_CALLBACK_EVENTS:
                    long_events.pop(0)
    return {
        "frame_end_pairs": len(periods_ms),
        "with_adjacent_callback_pair": callback_pairs,
        "without_adjacent_callback_pair": without_callbacks,
        "rejected_missing_end_pairs": missing_end,
        "rejected_nonmonotonic_end_pairs": nonmonotonic_end,
        "frame_end_period_ms": distribution(periods_ms) if periods_ms else None,
        "long_33ms": long_33,
        "long_83ms": long_83,
        "retained_long_events": len(long_events),
        "omitted_long_events": long_83 - len(long_events),
        "long_events": long_events,
    }


def extract(text: str) -> list[dict[str, Any]]:
    """Reject any missing/inconsistent native gesture, not just a marker."""
    lines = [line for line in text.splitlines() if line.startswith("T185_RUN ")]
    if len(lines) != len(EXPECTED) or "T185_PROFILE_PASSED cases=8 failures=0" not in text:
        raise ValueError(f"expected 8 complete gestures and a clean marker, got {len(lines)}")
    if "T185_FAILED:" in text or "SCRIPT ERROR:" in text or "ERROR: Parse Error:" in text:
        raise ValueError("native witness reported failures")
    runs = [json.loads(line.removeprefix("T185_RUN ")) for line in lines]
    for index, ((zoom, kind), row) in enumerate(zip(EXPECTED, runs, strict=True)):
        if (row.get("index") != index or row.get("zoom") != zoom or
                row.get("case") != kind or row.get("native_backend") != "Hokusai" or
                row.get("commit_revision_delta") != 1 or row.get("input_events") != 14 or
                row.get("width_px") != 96 or row.get("opacity") != 1 or
                row.get("canvas_px", [0, 0])[0] < 512):
            raise ValueError(f"trial {index} metadata or source transaction incomplete")
        if row.get("tool") != ("Eraser" if kind == "eraser" else "Brush"):
            raise ValueError(f"trial {index} wrong editing tool")
        if (row.get("before_sha256") == row.get("after_sha256") or
                not re.fullmatch("[a-f0-9]{64}", row.get("after_sha256", "")) or
                row.get("coverage", 0) < 1):
            raise ValueError(f"trial {index} has no committed native RGBA8 change")
        if (kind == "cold_brush" and row["display_tiles_before"] != 0) or (
                kind != "cold_brush" and row["display_tiles_before"] == 0):
            raise ValueError(f"trial {index} cache state not cold/warm as claimed")
        stage = row.get("native_stage", {})
        ffi = row.get("native_ffi_stats", {})
        if (stage.get("batch_calls", 0) < 1 or
                stage.get("dirty_entries", 0) < stage.get("unique_tiles", 1) or
                ffi.get("tile_ffi_calls", 0) < 1 or
                ffi.get("tile_pixel_stream_calls") != 0):
            raise ValueError(f"trial {index} native stage/FFI witness incomplete")
        for key in ("first_submit_ms", "first_postdraw_ms", "release_to_commit_ms",
                    "release_to_settled_ms", "total_to_settled_ms"):
            if not isinstance(row.get(key), (int, float)) or not math.isfinite(row[key]) or row[key] <= 0:
                raise ValueError(f"trial {index} lacks timing {key}")
        if row["first_postdraw_ms"] < row["first_submit_ms"]:
            raise ValueError(f"trial {index} preview callback predates submission")
        for key in ("post_draw_intervals_us", "process_frame_intervals_us"):
            series = row.get(key, [])
            if len(series) < 2 or min(series) <= 0 or max(series) > 2_000_000:
                raise ValueError(f"trial {index} frame trace is missing or implausible: {key}")
        if not row.get("frame_phases_us"):
            raise ValueError(f"trial {index} has no Canvas CPU frame phases")
    return runs


def fingerprint(path: Path) -> dict[str, Any]:
    return {"path": str(path.relative_to(REPO)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def environment(godot: Path) -> dict[str, Any]:
    native = REPO / "addons/drawing/native/bin/libdrawing_brush.so"
    sources = [REPO / entry for entry in (
        "addons/drawing/canvas.gd", "addons/drawing/edit_session.gd",
        "addons/drawing/workspace.gd", "drawing/tests/t185_current_app_profile.gd",
        "tools/run_t185_profile.py", "drawing/tests/t146_hokusai_full_canvas_native.gd")]
    presets = sorted((REPO / "addons/drawing/brushes").glob("*.myb"))
    if not native.is_file() or not presets:
        raise ValueError("native library or presets absent")
    ver = subprocess.check_output([str(godot), "--version"], text=True).strip()
    cpu = next((line.partition(":")[2].strip() for line in
                Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unavailable")
    return {"git_parent": subprocess.check_output(["git", "rev-parse", "HEAD"],
                                                    cwd=REPO, text=True).strip(),
            "git_status_note": "Working-tree T-185 profiling instrumentation pinned by hashes; commit after capture",
            "godot_version": ver, "godot_binary": str(godot),
            "native_sha256": hashlib.sha256(native.read_bytes()).hexdigest(),
            "source": [fingerprint(entry) for entry in sources],
            "presets": [fingerprint(entry) for entry in presets],
            "machine": {"platform": platform.platform(), "machine": platform.machine(),
                        "cpu": cpu, "python": sys.version.split()[0]},
            "renderer": "Xvfb 1280x900x24, Godot X11 gl_compatibility, Mesa llvmpipe, LIBGL_ALWAYS_SOFTWARE=1",
            "interpretation": "Virtual input/engine callbacks, not physical mouse or display-scanout telemetry"}


def run_trial(godot: Path, output: Path, timeout: int, index: int) -> dict[str, Any]:
    log = output / f"workspace-{index}.log"
    time = output / f"workspace-{index}.time"
    command = ["/usr/bin/time", "-v", "-o", str(time), "timeout", f"{timeout}s",
               "xvfb-run", "-a", "-s", "-screen 0 1280x900x24",
               str(godot), "--display-driver", "x11", "--rendering-method",
               "gl_compatibility", "--audio-driver", "Dummy", "--path", "drawing",
               "--script", "res://tests/t185_current_app_profile.gd"]
    env = os.environ.copy()
    env.update({"LIBGL_ALWAYS_SOFTWARE": "1", "DRAWING_T185_PROFILE": "1",
                "GODOT_SILENCE_ROOT_WARNING": "1"})
    with log.open("wb") as stream:
        try:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=timeout + 15, check=False)
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            exit_code = 124
    entry: dict[str, Any] = {"index": index, "exit": exit_code,
                             "log": log.name, "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),
                             "time": time.name, "command": command}
    try:
        rows = extract(log.read_text(encoding="utf-8", errors="replace"))
        if exit_code != 0:
            raise ValueError(f"nonzero process exit: {exit_code}")
        entry["rows"] = rows
        entry["valid"] = True
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        entry["valid"] = False
        entry["validation_error"] = str(exc)
    if time.is_file():
        for line in time.read_text(errors="replace").splitlines():
            if "Maximum resident set size (kbytes):" in line:
                entry["peak_rss_kib"] = int(line.rsplit(":", 1)[1])
    print(f"workspace-{index}: valid={entry['valid']} exit={exit_code} "
          f"rss_kib={entry.get('peak_rss_kib', 'n/a')}", flush=True)
    return entry



def ingest_trial(log: Path, output: Path, index: int) -> dict[str, Any]:
    """Preserve raw success *and* incomplete attempts; exit is independently required."""
    source_time = log.with_suffix(".time")
    copied_log = output / f"workspace-{index}.log"
    copied_time = output / f"workspace-{index}.time"
    shutil.copyfile(log, copied_log)
    if source_time.is_file():
        shutil.copyfile(source_time, copied_time)
    time_text = copied_time.read_text(errors="replace") if copied_time.is_file() else ""
    exit_code = 0 if re.search(r"(?m)^\s*Exit status: 0\s*$", time_text) else 124
    entry: dict[str, Any] = {"index": index, "exit": exit_code, "log": copied_log.name,
                             "time": copied_time.name if copied_time.is_file() else None,
                             "log_sha256": hashlib.sha256(copied_log.read_bytes()).hexdigest(),
                             "source_log": str(log), "ingested": True}
    try:
        rows = extract(copied_log.read_text(encoding="utf-8", errors="replace"))
        if exit_code != 0:
            raise ValueError("no confirmed zero exit, even if success marker printed")
        entry["rows"] = rows
        entry["valid"] = True
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        entry["validation_error"] = str(exc)
        entry["valid"] = False
    if copied_time.is_file():
        for line in time_text.splitlines():
            if "Maximum resident set size (kbytes):" in line:
                entry["peak_rss_kib"] = int(line.rsplit(":", 1)[1])
    print(f"ingested-{index}: valid={entry['valid']} exit={exit_code}", flush=True)
    return entry


def summarize(trials: list[dict[str, Any]]) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for trial in trials:
        if not trial.get("valid", False):
            continue
        prior_native_bytes: dict[float, int] = {}
        for row in trial["rows"]:
            zoom = row["zoom"]
            current_native_bytes = int(row["native_ffi_stats"].get("tile_bytes_exported", 0))
            row["native_tile_export_delta_bytes"] = current_native_bytes - prior_native_bytes.get(zoom, 0)
            prior_native_bytes[zoom] = current_native_bytes
            groups[f"{zoom:.2f}/{row['case']}"].append(row)
    metrics = ("first_submit_ms", "first_postdraw_ms", "release_to_commit_ms",
               "release_to_settled_ms", "total_to_settled_ms", "stage_cpu_us",
               "compose_cpu_us", "texture_cpu_us", "preview_index_cpu_us", "commit_cpu_us",
               "bytes_uploaded", "native_tile_export_delta_bytes")
    output: dict[str, Any] = {}
    for label, group in sorted(groups.items()):
        stats: dict[str, Any] = {"complete_trials": len(group)}
        for metric in metrics:
            values = [float(row[metric]) for row in group]
            stats[metric] = distribution(values)
        # This differs from the global postdraw series above: only adjacent
        # actual Canvas frames with matched, increasing callback timestamps
        # contribute, and gesture boundaries are never bridged.
        stats["matched_canvas_callback_gaps"] = callback_gap_diagnostics(group)
        # A separate engine-side witness includes redraws without renderer
        # callback pairing. It is not a display FPS or scanout measurement.
        stats["canvas_draw_cadence"] = canvas_draw_cadence_diagnostics(group)
        for source in ("post_draw_intervals_us", "process_frame_intervals_us", "input_delivery_intervals_us"):
            values = [float(v) / 1000.0 for row in group for v in row[source]]
            if not values:
                continue
            stats[source] = distribution(values)
            stats[source]["long_33ms"] = sum(v >= FRAME_THRESHOLDS_US[0] / 1000.0 for v in values)
            stats[source]["long_83ms"] = sum(v >= FRAME_THRESHOLDS_US[1] / 1000.0 for v in values)
            stats[source]["fps_from_median_period"] = round(1000.0 / quantile(values, 0.50), 2)
        for phase in ("apply_us", "authorize_us", "dirty_query_us", "stamp_us", "index_us",
                      "dirty_entries", "revisited_entries", "unique_tiles", "batch_calls"):
            stats[f"native_{phase}"] = distribution([float(row["native_stage"][phase]) for row in group])
        for phase in ("full_draw_cpu_us", "compose_cpu_us", "texture_cpu_us",
                      "preview_index_cpu_us", "pending_input_count", "oldest_pending_age_us"):
            values = [float(entry.get(phase, 0)) for row in group for entry in row["frame_phases_us"]]
            stats[f"frame_{phase}"] = distribution(values)
        output[label] = stats
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--ingest", nargs="*", type=Path, default=None,
                        help="Existing raw log paths with .time exit records; retain failures")
    args = parser.parse_args()
    if args.trials < 1 or args.timeout < 15:
        parser.error("trials >= 1, timeout >= 15s")
    godot = args.godot.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = ([ingest_trial(entry.resolve(), output, i) for i, entry in enumerate(args.ingest)]
               if args.ingest is not None else
               [run_trial(godot, output, args.timeout, i) for i in range(args.trials)])
    report = {"identity": environment(godot), "trials": results, "summary": summarize(results)}
    (output / "summary.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return 0 if all(t["valid"] for t in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
