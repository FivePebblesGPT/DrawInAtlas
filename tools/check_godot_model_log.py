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
# Godot errors can be indented by CI log forwarders or decorated by terminal
# color codes. Such decoration must not hide a runtime failure behind a valid
# success marker. Only *literal*, unadorned post-exit leaks are allowlisted.
ANSI_SGR = re.compile(r"\x1b\[[0-9;]*m")
PROCESS_FAILURE = re.compile(
    r"(?:FATAL(?: ERROR)?:|CRASH:|Segmentation fault(?: \(core dumped\))?"
    r"|Aborted(?: \(core dumped\))?|terminate called after throwing)",
    re.IGNORECASE,
)



def verify_log(content: str, marker: str) -> tuple[list[str], int]:
    """Return fatal diagnostics and recognized *post-success* leak count."""
    if not marker or not re.fullmatch(r"[A-Z][A-Z0-9_]+_PASSED", marker):
        raise ValueError("Expected exact uppercase *_PASSED marker")
    lines = content.splitlines()
    # Only formats actually emitted by checked-in model witnesses are valid.
    # A loose prefix check accepted misleading output such as `PASSED 0/99`
    # and `PASSED (42 checks; 5 failed)` as success. Fail closed instead.
    escaped = re.escape(marker)
    positive = r"[1-9][0-9]*"
    ratio = re.compile(rf"{escaped} ({positive})/({positive})\Z")
    counted = re.compile(rf"{escaped}: {positive} checks\Z")
    checked = re.compile(rf"{escaped} \({positive} checks; 0 failed\)\Z")
    no_failures = re.compile(rf"{escaped} \(0 failures\)\Z")
    comma_checked = re.compile(rf"{escaped} \({positive} checks, 0 failures\)\Z")
    labeled_counts = re.compile(rf"{escaped} checks={positive} failures=0\Z")
    inline_counts = re.compile(rf"{escaped} {positive} checks, failures=0\Z")
    markers: list[int] = []
    problems: list[str] = []
    for index, line in enumerate(lines):
        if not line.startswith((marker + " ", marker + ":", marker + "(")) and line != marker:
            continue
        match = ratio.fullmatch(line)
        if (line == marker or counted.fullmatch(line) or checked.fullmatch(line)
                or no_failures.fullmatch(line) or comma_checked.fullmatch(line)
                or labeled_counts.fullmatch(line) or inline_counts.fullmatch(line) or
                (match is not None and match.group(1) == match.group(2))):
            markers.append(index)
        else:
            problems.append(f"Line {index + 1}: Invalid or incomplete {marker} success summary: {line}")
    if len(markers) != 1:
        problems.append(f"Expected exactly one {marker} marker, got {len(markers)}")
    marker_line = markers[0] if len(markers) == 1 else len(lines)
    leaks = 0
    for number, line in enumerate(lines, 1):
        diagnostic = ANSI_SGR.sub("", line).lstrip(" \t")
        if ("SCRIPT ERROR:" in diagnostic or "Parse Error:" in diagnostic
                or "Compile Error:" in diagnostic or MODEL_FAILURE.search(diagnostic)
                or PROCESS_FAILURE.match(diagnostic)):
            problems.append(f"Line {number}: {line}")
        elif diagnostic.startswith("ERROR:"):
            if (diagnostic == line and number - 1 > marker_line
                    and any(pattern.fullmatch(line) for pattern in KNOWN_POST_EXIT)):
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
