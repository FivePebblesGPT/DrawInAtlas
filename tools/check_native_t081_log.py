#!/usr/bin/env python3
"""Fail closed on T-081 floating-host native ownership and sizing evidence.

Known Godot 4.8 beta2 resource leaks are retained only after a complete pass.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUMMARY = re.compile(r"T081_FLOAT_NATIVE: (\d+) checks; (\d+) failed")
MARKER = "T081_FLOAT_NATIVE_PASSED"
MINIMUM_CHECKS = 58
KNOWN_POST_EXIT = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)


def verify(content: str) -> tuple[bool, list[str], int]:
    """Verify completion count, failure diagnostics and post-success leaks.

    Returns
    -------
    tuple[bool, list[str], int]
        Valid log, disqualifying messages, known resource-leak count.
    """
    lines = content.splitlines()
    summaries = [(i, match) for i, line in enumerate(lines)
                 if (match := SUMMARY.fullmatch(line)) is not None]
    markers = [i for i, line in enumerate(lines) if line == MARKER]
    problems: list[str] = []
    if len(summaries) != 1 or len(markers) != 1:
        problems.append("expected one complete summary and one success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < MINIMUM_CHECKS
          or int(summaries[0][1].group(2)) != 0):
        problems.append("stale, failed or incorrectly ordered T-081 witness")
    marker_at = markers[0] if markers else len(lines)
    known_leaks = 0
    for i, line in enumerate(lines):
        if ("SCRIPT ERROR:" in line or "Parse Error:" in line
                or "Compile Error:" in line or "T081_NATIVE_FAILED:" in line):
            problems.append(line)
        elif line.startswith("ERROR:"):
            if i > marker_at and any(p.fullmatch(line) for p in KNOWN_POST_EXIT):
                known_leaks += 1
            else:
                problems.append(line)
    return not problems, problems, known_leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    valid, problems, leaks = verify(args.log.read_text(encoding="utf-8"))
    for message in problems:
        print("T081_NATIVE_LOG_REJECTED:", message)
    if leaks:
        print(f"T081_NATIVE_POST_EXIT_LEAKS: {leaks} recorded")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
