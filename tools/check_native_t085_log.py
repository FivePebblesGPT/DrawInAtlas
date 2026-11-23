#!/usr/bin/env python3
"""Reject truncated/failed T-085 native framebuffer and 840-sample history logs.

The generic Godot verifier owns diagnostic classification. This witness adds
T-085-specific check-count, per-zoom and native-stroke completeness contracts.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from check_godot_model_log import verify_log

EXPECTED_ZOOMS = frozenset({"1.00", "0.50", "0.25"})
SUMMARY = re.compile(r"T085_NATIVE: (\d+) checks; (\d+) failed")
ZOOM = re.compile(
    r"T085_NATIVE_ZOOM zoom=(1\.00|0\.50|0\.25) samples=(\d+) "
    r"max_queued=\d+ down_to_stage_ms=[\d.]+ down_to_frame_ms=[\d.]+ "
    r"release_to_commit_ms=[\d.]+"
)
LONG = re.compile(
    r"T085_NATIVE_LONG zoom=(1\.00|0\.50|0\.25) delivered=(\d+) segments=(\d+) "
    r"drain_calls=\d+ drain_frames=\d+ max_drain_cpu_ms=[\d.]+ "
    r"stage_cpu_ms=[\d.]+ release_to_commit_ms=[\d.]+ wall_ms=[\d.]+"
)
LONG_SUMMARY = re.compile(
    r"T085_NATIVE_LONG_SUMMARY zoom=(1\.00|0\.50|0\.25) trials=(\d+) "
    r"release_to_commit_p50_ms=([\d.]+) release_to_commit_p95_ms=([\d.]+)"
)
METRICS = re.compile(
    r"T085_NATIVE_METRICS ms: preview_frame_p50=[\d.]+ preview_frame_p95=[\d.]+ "
    r"sample_to_stage_p50=[\d.]+ sample_to_stage_p95=[\d.]+ "
    r"stage_cpu_p50=[\d.]+ stage_cpu_p95=[\d.]+"
)


def verify(content: str) -> tuple[bool, list[str], int]:
    """Validate unique success, native coverage and fatal diagnostics.

    Parameters
    ----------
    content : str
        Full Godot process stdout/stderr.

    Returns
    -------
    tuple[bool, list[str], int]
        Success, rejection reasons, recognized post-exit leak count.
    """
    problems, leaks = verify_log(content, "T085_NATIVE_PASSED")
    lines = content.splitlines()
    summaries = [(i, match) for i, line in enumerate(lines) if (match := SUMMARY.fullmatch(line)) is not None]
    marker = [i for i, line in enumerate(lines) if line == "T085_NATIVE_PASSED"]
    if (
        len(summaries) != 1
        or len(marker) != 1
        or summaries[0][0] >= marker[0]
        or int(summaries[0][1].group(1)) < 144
        or int(summaries[0][1].group(2)) != 0
    ):
        problems.append("expected 144+ zero-failure checks before the unique success marker")

    observed_zooms: set[str] = set()
    long_counts: dict[str, int] = dict.fromkeys(EXPECTED_ZOOMS, 0)
    observed_summaries: set[str] = set()
    metric_count = 0
    for line in lines:
        if line.startswith("T085_NATIVE_ZOOM "):
            match = ZOOM.fullmatch(line)
            if match is None or int(match.group(2)) != 31 or match.group(1) in observed_zooms:
                problems.append(f"invalid or duplicate per-zoom short stroke: {line}")
            else:
                observed_zooms.add(match.group(1))
        elif line.startswith("T085_NATIVE_LONG zoom="):
            match = LONG.fullmatch(line)
            if match is None or int(match.group(2)) != 840 or int(match.group(3)) < 840:
                problems.append(f"incomplete or malformed 840-point native replay: {line}")
            else:
                long_counts[match.group(1)] += 1
        elif line.startswith("T085_NATIVE_LONG_SUMMARY "):
            match = LONG_SUMMARY.fullmatch(line)
            if (
                match is None
                or int(match.group(2)) != 3
                or float(match.group(4)) < float(match.group(3))
                or match.group(1) in observed_summaries
            ):
                problems.append(f"invalid or duplicate long-stroke summary: {line}")
            else:
                observed_summaries.add(match.group(1))
        elif line.startswith("T085_NATIVE_METRICS "):
            metric_count += 1
            if METRICS.fullmatch(line) is None:
                problems.append(f"missing frame/stage timing fields: {line}")
    if observed_zooms != EXPECTED_ZOOMS:
        problems.append(f"short stroke zoom coverage incomplete: {sorted(observed_zooms)}")
    if any(count != 3 for count in long_counts.values()):
        problems.append(f"long stroke trials incomplete: {long_counts}")
    if observed_summaries != EXPECTED_ZOOMS:
        problems.append(f"long stroke summary coverage incomplete: {sorted(observed_summaries)}")
    if metric_count != 1:
        problems.append(f"expected one timing summary, found {metric_count}")
    return not problems, problems, leaks


def main() -> int:
    """Validate the supplied logfile and report retained Godot exit leaks."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        passed, problems, leaks = verify(args.log.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"T085_NATIVE_LOG_REJECTED: {exc}")
        return 2
    for problem in problems:
        print(f"T085_NATIVE_LOG_REJECTED: {problem}")
    if leaks:
        print(f"T085_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {leaks} retained")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
