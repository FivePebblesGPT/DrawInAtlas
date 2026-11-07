#!/usr/bin/env python3
"""Fail closed on T-080's real native dock-reorder pointer witness.

Only the pinned Godot 4.8 beta2/Mesa post-success resource diagnostics are
recognized as shutdown warnings; earlier/unknown errors remain failures.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUMMARY = re.compile(r"T080_DOCK_REORDER_NATIVE: (\d+) checks; (\d+) failed")
MARKER = "T080_DOCK_REORDER_NATIVE_PASSED"
MINIMUM_CHECKS = 70
POST_EXIT = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)


def verify(content: str) -> tuple[bool, list[str], int]:
    """Validate completion, runtime errors, and narrowly known shutdown leaks.

    Returns
    -------
    tuple[bool, list[str], int]
        Success, rejected log lines, and retained post-exit leak count.
    """
    lines = content.splitlines()
    summaries = [(i, match) for i, line in enumerate(lines)
                 if (match := SUMMARY.fullmatch(line)) is not None]
    markers = [i for i, line in enumerate(lines) if line == MARKER]
    problems: list[str] = []
    if len(summaries) != 1 or len(markers) != 1:
        problems.append("expected exactly one summary and one success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < MINIMUM_CHECKS
          or int(summaries[0][1].group(2)) != 0):
        problems.append("incomplete, failed, or wrongly ordered native witness")
    marker_index = markers[0] if markers else len(lines)
    leaks = 0
    for i, line in enumerate(lines):
        if "SCRIPT ERROR:" in line or "T080_NATIVE_FAILED:" in line:
            problems.append(line)
        elif line.startswith("ERROR:"):
            if i > marker_index and any(pattern.fullmatch(line) for pattern in POST_EXIT):
                leaks += 1
            else:
                problems.append(line)
    return not problems, problems, leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    passed, problems, leaks = verify(args.log.read_text(encoding="utf-8"))
    for problem in problems:
        print("T080_NATIVE_LOG_REJECTED:", problem)
    if leaks:
        print(f"T080_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {leaks} retained")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
