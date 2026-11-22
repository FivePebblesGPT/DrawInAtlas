#!/usr/bin/env python3
"""Fail-closed T-096 large-selection/Move and T-268 Atlas log verification.

The diagnostic timing lines are software-only observations, not a physical
input-to-photon latency gate. Require their presence, not a synthetic budget.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

if __package__:
    from .check_godot_model_log import verify_log as verify_godot_log
else:
    from check_godot_model_log import verify_log as verify_godot_log

CONFIG = {
    "model": ("T096_MODEL", 13000, "T096_PROFILE"),
    "native": ("T096_NATIVE", 34, "T096_NATIVE_TIMING"),
    "atlas": ("T268_ATLAS", 22, ""),
}
NATIVE_METRICS = (
    "capture_ms",
    "motion_stage_p50_ms",
    "motion_stage_p95_ms",
    "receipt_to_submit_p50_ms",
    "receipt_to_submit_p95_ms",
    "callback_p50_ms",
    "callback_p95_ms",
    "compose_p95_ms",
    "upload_p95_ms",
    "drop_callback_ms",
    "drop_cpu_ms",
    "cold_frame_callback_ms",
    "cold_compose_ms",
    "warm_compose_ms",
    "cold_outline_ms",
)
MODEL_METRICS = (
    "legacy_capture_p50/p95_ms",
    "legacy_clear_p50/p95_ms",
    "legacy_paste_p50/p95_ms",
    "optimized_stage_p50/p95_ms",
)
NONNEGATIVE = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z")


def verify_log(content: str, kind: str) -> list[str]:
    """Reject incomplete, duplicated, inconsistent or failed Godot output.

    Parameters
    ----------
    content : str
        Entire stdout/stderr of one completed Godot process.
    kind : str
        One of ``model``, ``native`` or ``atlas``.

    Returns
    -------
    list[str]
        Failure descriptions; empty means the stream passes validation.
    """
    if kind not in CONFIG:
        raise ValueError(f"Unknown T-096 witness: {kind}")
    prefix, minimum, diagnostic = CONFIG[kind]
    marker = f"{prefix}_PASSED"
    errors, _leaks = verify_godot_log(content, marker)
    lines = content.splitlines()
    summary = re.compile(rf"{re.escape(prefix)}: ([0-9]+) checks; ([0-9]+) fail(?:ed|ures)\Z")
    summaries = [
        (index, match) for index, line in enumerate(lines) if (match := summary.fullmatch(line)) is not None
    ]
    markers = [index for index, line in enumerate(lines) if line == marker]
    if len(summaries) != 1:
        errors.append(f"Expected one complete {prefix} check summary, got {len(summaries)}")
    else:
        index, match = summaries[0]
        assert match is not None
        if int(match[1]) < minimum or int(match[2]) != 0:
            errors.append(f"{prefix} checks incomplete or failed: {match[0]}")
        if len(markers) == 1 and index >= markers[0]:
            errors.append(f"{prefix} summary must precede its pass marker")
    if diagnostic:
        detail = [(index, line) for index, line in enumerate(lines) if line.startswith(f"{diagnostic}:")]
        if len(detail) != 1:
            errors.append(f"Expected exactly one {diagnostic} diagnostic")
        else:
            index, line = detail[0]
            if len(summaries) == 1 and index >= summaries[0][0]:
                errors.append(f"{diagnostic} must precede the check summary")
            for name in NATIVE_METRICS if kind == "native" else MODEL_METRICS:
                match = re.search(rf"(?<!\S){re.escape(name)}=([^\s]+)", line)
                if match is None:
                    errors.append(f"Missing {diagnostic}.{name}")
                    continue
                for value in match[1].split("/"):
                    if NONNEGATIVE.fullmatch(value) is None:
                        errors.append(f"Invalid {diagnostic}.{name}: {match[1]}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=CONFIG)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        errors = verify_log(args.log.read_text(encoding="utf-8"), args.kind)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"T096_LOG_REJECTED: {exc}")
        return 2
    for error in errors:
        print(f"T096_LOG_REJECTED: {error}")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
