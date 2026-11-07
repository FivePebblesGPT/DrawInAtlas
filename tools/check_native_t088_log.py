#!/usr/bin/env python3
"""Validate the complete T-088 software-pointer witness, not merely its marker."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUMMARY = re.compile(r"T088_NATIVE: (\d+) checks; (\d+) failed \(Godot .+\)")
MARKER = "T088_NATIVE_PASSED"
POST_EXIT_LEAK = (
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
)


def verify_log(content: str) -> tuple[list[str], int]:
    """Return fatal diagnostics and known post-success Godot leak count.

    Parameters
    ----------
    content : str
        Whole Godot process log, including diagnostics after the success marker.

    Returns
    -------
    tuple[list[str], int]
        Failure reasons and count of recognized post-exit resource warnings.
    """
    lines = content.splitlines()
    summaries = [(i, match) for i, line in enumerate(lines)
                 if (match := SUMMARY.fullmatch(line)) is not None]
    markers = [i for i, line in enumerate(lines) if line == MARKER]
    failures: list[str] = []
    if len(summaries) != 1 or len(markers) != 1:
        failures.append("expected exactly one native summary and one success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < 51
          or int(summaries[0][1].group(2)) != 0):
        failures.append("too few assertions, nonzero failures, or invalid marker order")
    marker_position = markers[0] if markers else len(lines)
    recognized_leaks = 0
    for index, line in enumerate(lines):
        if ("SCRIPT ERROR:" in line or "Parse Error:" in line
                or "Compile Error:" in line or "T088_NATIVE_FAILED:" in line):
            failures.append(f"line {index + 1}: {line}")
        elif line.startswith("ERROR:"):
            if (index > marker_position
                    and any(pattern.fullmatch(line) for pattern in POST_EXIT_LEAK)):
                recognized_leaks += 1
            else:
                failures.append(f"line {index + 1}: {line}")
    return failures, recognized_leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        problems, leaks = verify_log(args.log.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as error:
        print("T088_NATIVE_LOG_REJECTED:", error)
        return 2
    for problem in problems:
        print("T088_NATIVE_LOG_REJECTED:", problem)
    if leaks:
        print(f"T088_NATIVE_POST_EXIT_LEAKS: {leaks} documented Godot resource diagnostics")
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
