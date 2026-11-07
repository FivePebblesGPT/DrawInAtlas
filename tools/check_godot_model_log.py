#!/usr/bin/env python3
"""Check Godot model smoke logs without hiding post-exit renderer diagnostics.

A passing test must print exactly one named success marker and no script, parse,
model-assertion, or renderer errors during execution. The only allowed `ERROR:`
lines are Godot's *specifically identified* resource leaks after that marker;
they remain in the captured CI log and are separately counted here.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

KNOWN_POST_EXIT = (
    re.compile(r"ERROR: \d+ RID allocations of type '[^'\n]+' were leaked at exit\."),
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
)
MODEL_FAILURE = re.compile(r"\b[A-Z][A-Z0-9_]*FAILED:|\bFAILED:|\bDOCK MODEL FAILED:")


def verify_log(content: str, marker: str) -> tuple[list[str], int]:
    """Return fatal diagnostics and recognized *post-success* leak count."""
    if not marker or not re.fullmatch(r"[A-Z][A-Z0-9_]+_PASSED", marker):
        raise ValueError("Expected exact uppercase *_PASSED marker")
    lines = content.splitlines()
    # Legacy model witnesses may report an assertion count as
    # `T089_MODEL_PASSED: 62 checks`; accept that exact form, not an
    # arbitrary colon suffix that could disguise a diagnostic.
    counted_marker = re.compile(re.escape(marker) + r": [1-9][0-9]* checks\Z")
    markers = [i for i, line in enumerate(lines)
               if line == marker or line.startswith(marker + " ")
               or line.startswith(marker + "(") or counted_marker.fullmatch(line)]
    problems: list[str] = []
    if len(markers) != 1:
        problems.append(f"Expected exactly one {marker} marker, got {len(markers)}")
    marker_line = markers[0] if len(markers) == 1 else len(lines)
    leaks = 0
    for number, line in enumerate(lines, 1):
        if ("SCRIPT ERROR:" in line or "Parse Error:" in line or "Compile Error:" in line
                or MODEL_FAILURE.search(line)):
            problems.append(f"Line {number}: {line}")
        elif line.startswith("ERROR:"):
            if number - 1 > marker_line and any(p.fullmatch(line) for p in KNOWN_POST_EXIT):
                leaks += 1
            else:
                problems.append(f"Line {number}: {line}")
    return problems, leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--marker", required=True, help="Exact single *_PASSED test marker")
    args = parser.parse_args()
    try:
        problems, leaks = verify_log(args.log.read_text(encoding="utf-8"), args.marker)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"GODOT_MODEL_LOG_REJECTED: {exc}")
        return 2
    for problem in problems:
        print(f"GODOT_MODEL_LOG_REJECTED: {problem}")
    if leaks:
        print(f"GODOT_MODEL_POST_EXIT_LEAKS: {leaks} known resource-leak diagnostics retained in {args.log}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
