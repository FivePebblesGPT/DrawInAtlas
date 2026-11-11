#!/usr/bin/env python3
"""Summarize opt-in T-095 Brush JSONL traces without implying hardware latency.

The exporter deliberately retains only recent per-sample/per-frame histories.
Reported percentiles apply to retained samples, never to an entire evicted
history. Lifetime maxima and counts are reported separately where available.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Sequence


class TraceError(ValueError):
    """Invalid or incompatible owner-device trace input."""


SAMPLE_SPECS: tuple[tuple[str, str, str], ...] = (
    ("sample_to_stage", "sample_to_stage_us", "sample_to_stage_total"),
    ("stage_batch", "stage_batches_us", "stage_batch_total"),
)
FRAME_SPECS: tuple[tuple[str, str], ...] = (
    ("full_draw", "full_draw_cpu_us"),
    ("compose", "compose_cpu_us"),
    ("texture", "texture_cpu_us"),
    ("preview_index", "preview_index_cpu_us"),
    ("pending_age", "oldest_pending_age_us"),
    ("post_draw_callback", "frame_end_to_post_draw_us"),
    ("preview_stage_to_draw", "preview_stage_to_frame_end_us"),
    ("preview_stage_to_callback", "preview_stage_to_post_draw_us"),
    ("preview_input_to_draw", "preview_input_to_frame_end_us"),
    ("preview_input_to_callback", "preview_input_to_post_draw_us"),
)
MAX_LINE_BYTES = 4 * 1024 * 1024  # One exported record cannot exceed the 4 MiB file cap.
MAX_ROWS = 100_000  # Avoid unbounded aggregation on malformed or hostile files.


def nonnegative_int(value: Any, context: str) -> int:
    """Accept JSON integer counters only, rejecting bools and floats."""
    if type(value) is not int or value < 0:
        raise TraceError(f"{context}: expected nonnegative integer")
    return value


def number(value: Any, context: str, *, allow_zero: bool = False) -> float:
    """Accept finite JSON dimensions; empty-image bounds may be zero."""
    if type(value) not in (int, float):
        raise TraceError(f"{context}: expected finite positive number")
    try:
        converted = float(value)
    except (ValueError, OverflowError) as exc:
        raise TraceError(f"{context}: expected finite positive number") from exc
    if not math.isfinite(converted) or (converted < 0 if allow_zero else converted <= 0):
        raise TraceError(f"{context}: expected finite positive number")
    return converted


def samples(value: Any, context: str, limit: int) -> list[int]:
    """Validate the chronological bounded sample window."""
    if not isinstance(value, list) or len(value) > limit:
        raise TraceError(f"{context}: invalid or oversized sample window")
    return [nonnegative_int(sample, f"{context}[{index}]") for index, sample in enumerate(value)]


def percentile(values: Sequence[int], fraction: float) -> float | None:
    """Return a nearest-rank percentile of an observed, nonempty window.

    Parameters
    ----------
    values : Sequence[int]
        Observed samples, in microseconds.
    fraction : float
        Desired percentile fraction between 0 and 1, inclusive.

    Returns
    -------
    float | None
        Selected sample value; None for an empty window.
    """
    if not values:
        return None
    ordered = sorted(values)
    return float(ordered[max(0, math.ceil(fraction * len(ordered)) - 1)])


def distribution(values: Sequence[int], total: int | None = None) -> dict[str, Any]:
    """Describe retained observations, never silently filling missing data."""
    retained = len(values)
    if total is not None and total < retained:
        raise TraceError("declared lifetime total is smaller than retained history")
    return {
        "retained": retained,
        "total": total,
        "truncated": None if total is None else total > retained,
        "p50_ms": None if not values else percentile(values, 0.50) / 1000,
        "p95_ms": None if not values else percentile(values, 0.95) / 1000,
        "retained_max_ms": None if not values else max(values) / 1000,
    }


def summarize_stroke(
    record: Any, index: int, *, source_file_index: int = 1,
    timestamp_epoch_index: int = 1,
) -> dict[str, Any]:
    """Validate a stroke, retaining file and observed monotonic-clock epoch."""
    for name, value in (("source_file_index", source_file_index),
                        ("timestamp_epoch_index", timestamp_epoch_index)):
        nonnegative_int(value, name)
        if value == 0:
            raise TraceError(f"{name}: expected a positive integer")
    if not isinstance(record, dict):
        raise TraceError(f"stroke {index}: expected a JSON object")
    if record.get("schema") != 1 or record.get("capture_kind") != "engine_timing_only":
        raise TraceError(f"stroke {index}: unsupported T-095 trace schema or capture kind")
    backend = record.get("backend")
    if backend not in ("Legacy", "NativeHard", "Hokusai"):
        raise TraceError(f"stroke {index}: unsupported Brush backend")
    zoom = number(record.get("zoom"), f"stroke {index} zoom")
    width = number(record.get("brush_width_px"), f"stroke {index} brush width")
    for field in ("viewport_px", "image_size_px"):
        dims = record.get(field)
        if not isinstance(dims, list) or len(dims) != 2:
            raise TraceError(f"stroke {index} {field}: expected [width,height]")
        for coordinate in dims:
            number(coordinate, f"stroke {index} {field}", allow_zero=(field == "image_size_px"))

    down = nonnegative_int(record.get("down_us"), "down_us")
    release = nonnegative_int(record.get("release_us"), "release_us")
    commit = nonnegative_int(record.get("commit_us"), "commit_us")
    if not down <= release <= commit:
        raise TraceError(f"stroke {index}: non-monotonic input/release/commit timestamps")

    metrics: dict[str, dict[str, Any]] = {}
    for label, key, total_key in SAMPLE_SPECS:
        metric = samples(record.get(key), f"stroke {index} {key}", 4096)
        total = nonnegative_int(record.get(total_key), f"stroke {index} {total_key}")
        metrics[label] = distribution(metric, total)
    phases = record.get("frame_phases_us")
    if not isinstance(phases, list) or len(phases) > 1024:
        raise TraceError(f"stroke {index}: invalid frame window")
    for phase_index, phase in enumerate(phases):
        if not isinstance(phase, dict):
            raise TraceError(f"stroke {index}: frame {phase_index} must be an object")
    frame_total = nonnegative_int(record.get("frame_phase_total"), "frame_phase_total")
    if frame_total < len(phases):
        raise TraceError(f"stroke {index}: frame total below retained frame count")
    for label, key in FRAME_SPECS:
        present = [nonnegative_int(phase[key], f"frame {idx} {key}")
                   for idx, phase in enumerate(phases) if key in phase]
        # Missing optional callback fields MUST NOT become zero-duration events.
        total = frame_total if label in ("full_draw", "compose", "texture", "preview_index", "pending_age") else None
        metrics[label] = distribution(present, total)
    frame_matches = nonnegative_int(record.get("frame_post_draw_matches"), "frame_post_draw_matches")
    input_matches = nonnegative_int(record.get("preview_input_post_draw_matches"), "preview_input_post_draw_matches")
    if input_matches > frame_matches or frame_matches > frame_total:
        raise TraceError(f"stroke {index}: impossible callback-match counts")
    counts = {}
    for key in ("samples_received", "segments_staged", "max_pending",
                "max_sample_to_stage_us", "max_frame_oldest_pending_age_us",
                "frame_preview_stage_submissions", "preview_stage_post_draw_matches",
                "frame_phase_total", "frame_post_draw_matches",
                "preview_input_post_draw_matches"):
        counts[key] = nonnegative_int(record.get(key), f"stroke {index} {key}")
    if counts["preview_stage_post_draw_matches"] > frame_matches or input_matches > counts["frame_preview_stage_submissions"]:
        raise TraceError(f"stroke {index}: impossible changed-preview match counts")
    return {
        "stroke": index, "source_file_index": source_file_index,
        "timestamp_epoch_index": timestamp_epoch_index,
        "backend": backend, "zoom": zoom, "brush_width_px": width,
        "viewport_px": record["viewport_px"], "image_size_px": record["image_size_px"],
        "held_ms": (release - down) / 1000,
        "release_to_commit_ms": (commit - release) / 1000,
        "counts": counts,
        "metrics": metrics,
        "lifetime_max_ms": {
            "sample_to_stage": counts["max_sample_to_stage_us"] / 1000,
            "pending_age": counts["max_frame_oldest_pending_age_us"] / 1000,
        },
    }


def read_traces(paths: Sequence[Path]) -> list[dict[str, Any]]:
    """Read and strictly validate every nonempty line of the provided files."""
    strokes: list[dict[str, Any]] = []
    for source_file_index, path in enumerate(paths, start=1):
        previous_down_us: int | None = None
        timestamp_epoch_index = 1
        with path.open("rb") as handle:
            line_number = 0
            while raw := handle.readline(MAX_LINE_BYTES + 2):
                line_number += 1
                if not raw.strip():
                    continue
                if len(raw) > MAX_LINE_BYTES:
                    raise TraceError(f"{path}:{line_number}: oversized JSONL record")
                if len(strokes) == MAX_ROWS:
                    raise TraceError("too many stroke records")
                try:
                    decoded = json.loads(raw)
                except (ValueError, UnicodeDecodeError) as exc:
                    raise TraceError(f"{path}:{line_number}: malformed JSONL record") from exc
                try:
                    # get_ticks_usec() is monotonic within one Godot process,
                    # but an appended file can contain a later process restart.
                    down_us = nonnegative_int(
                        decoded.get("down_us") if isinstance(decoded, dict) else None,
                        "down_us",
                    )
                    if previous_down_us is not None and down_us < previous_down_us:
                        timestamp_epoch_index += 1
                    stroke = summarize_stroke(
                        decoded, len(strokes) + 1,
                        source_file_index=source_file_index,
                        timestamp_epoch_index=timestamp_epoch_index,
                    )
                    strokes.append(stroke)
                    previous_down_us = down_us
                except TraceError as exc:
                    raise TraceError(f"{path}:{line_number}: {exc}") from exc
    if not strokes:
        raise TraceError("no completed T-095 stroke records found")
    return strokes


def aggregate(strokes: Sequence[dict[str, Any]]) -> dict[str, Any]:
    """Separate files and observable monotonic-clock resets, not hardware IDs."""
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for stroke in strokes:
        key = (stroke["source_file_index"], stroke["timestamp_epoch_index"],
               stroke["backend"], stroke["brush_width_px"], stroke["zoom"],
               tuple(stroke["viewport_px"]), tuple(stroke["image_size_px"]))
        groups.setdefault(key, []).append(stroke)
    results: list[dict[str, Any]] = []
    for key, group in groups.items():
        metrics: dict[str, Any] = {}
        for label in ("release_to_commit",):
            values = [round(item["release_to_commit_ms"] * 1000) for item in group]
            metrics[label] = distribution(values, len(values))
        results.append({
            "source_file_index": key[0], "timestamp_epoch_index": key[1],
            "backend": key[2], "brush_width_px": key[3], "zoom": key[4],
            "viewport_px": list(key[5]), "image_size_px": list(key[6]),
            "strokes": len(group), "first_stroke_release_to_commit_ms": group[0]["release_to_commit_ms"],
            "later_strokes": max(0, len(group) - 1),
            "release_to_commit": metrics["release_to_commit"],
        })
    return {"schema": "t095_trace_analysis_v3", "measurement": "godot_engine_only_not_input_to_photon",
            "percentile_method": "nearest_rank",
            "cohort_boundary": "input_file_and_observed_timestamp_epoch_plus_brush_settings_not_verified_hardware",
            "strokes": list(strokes), "groups": results}


def human_report(report: dict[str, Any]) -> str:
    """Render a small summary without suggesting an unsupported latency target."""
    lines = ["T-095 Godot engine trace (NOT physical input-to-photon latency)",
             "Percentiles use nearest rank on retained samples only; missing callbacks are excluded.",
             "Cohorts separate input files and observed monotonic-clock resets;",
             "unobserved restarts and same-clock sessions/devices cannot be identified."]
    for group in report["groups"]:
        result = group["release_to_commit"]
        lines.append(f"File #{group['source_file_index']}, epoch #{group['timestamp_epoch_index']}: "
                     f"{group['backend']} {group['brush_width_px']:g}px at {group['zoom']:g}x: "
                     f"{group['strokes']} strokes; release→commit p50/p95 "
                     f"{result['p50_ms']:.3f}/{result['p95_ms']:.3f} ms "
                     f"(first {group['first_stroke_release_to_commit_ms']:.3f} ms)")
    for stroke in report["strokes"]:
        lines.append(f"Stroke {stroke['stroke']} (file #{stroke['source_file_index']}, "
                     f"epoch #{stroke['timestamp_epoch_index']}): "
                     f"{stroke['backend']} "
                     f"held {stroke['held_ms']:.3f} ms, release→commit "
                     f"{stroke['release_to_commit_ms']:.3f} ms")
        lines.append(f"  samples received {stroke['counts']['samples_received']}; "
                     f"staged segments {stroke['counts']['segments_staged']}; "
                     f"peak pending depth {stroke['counts']['max_pending']}; "
                     f"matched preview callbacks {stroke['counts']['preview_input_post_draw_matches']}")
        for label in ("sample_to_stage", "stage_batch", "pending_age", "full_draw",
                      "compose", "texture", "post_draw_callback",
                      "preview_stage_to_draw", "preview_stage_to_callback",
                      "preview_input_to_draw", "preview_input_to_callback"):
            metric = stroke["metrics"][label]
            if metric["retained"]:
                population = (f"{metric['retained']}/{metric['total']}"
                              if metric["total"] is not None else f"{metric['retained']} matched")
                lines.append(f"  {label}: p50/p95 {metric['p50_ms']:.3f}/{metric['p95_ms']:.3f} ms "
                             f"({population} retained; retained max {metric['retained_max_ms']:.3f} ms)")
            else:
                lines.append(f"  {label}: unavailable (no matched/retained samples)")
        lines.append(f"  lifetime max input stage {stroke['lifetime_max_ms']['sample_to_stage']:.3f} ms; "
                     f"oldest pending {stroke['lifetime_max_ms']['pending_age']:.3f} ms")
    lines.append("Owner OS/GPU/driver, physical catch-up, and final manual acceptance must be recorded separately.")
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, nargs="+", help="local T-095 JSONL trace file(s)")
    parser.add_argument("--json", action="store_true", help="emit machine-readable analysis")
    args = parser.parse_args(argv)
    try:
        report = aggregate(read_traces(args.trace))
    except (TraceError, OSError) as exc:
        print(f"T095_TRACE_ANALYSIS_FAILED: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(report, indent=2, allow_nan=False))
    else:
        print(human_report(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
