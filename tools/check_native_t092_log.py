#!/usr/bin/env python3
"""Fail-closed T-092 X11 Colors/History witness log check with explicit teardown caveats."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUMMARY = re.compile(r"T092_NATIVE: (\d+) checks; (\d+) failed")
MARKER = "T092_NATIVE_PASSED"
KNOWN_SHUTDOWN = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)


def verify(content: str) -> tuple[bool, list[str], int]:
    """Validate check count, unique success marker, and every error location.

    Returns
    -------
    tuple[bool, list[str], int]
        Whether valid, all disqualifying log lines, known post-success leaks.
    """
    lines = content.splitlines()
    summaries = [(i, SUMMARY.fullmatch(line)) for i, line in enumerate(lines)
                 if SUMMARY.fullmatch(line)]
    markers = [i for i, line in enumerate(lines) if line == MARKER]
    problems: list[str] = []
    if len(summaries) != 1 or len(markers) != 1:
        problems.append("expected exactly one passing summary and success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < 42
          or int(summaries[0][1].group(2)) != 0):
        problems.append("incomplete test count, failed assertions, or invalid marker order")
    marker_at = markers[0] if markers else len(lines)
    recognized = 0
    for line_number, line in enumerate(lines):
        if "SCRIPT ERROR:" in line or "T092_NATIVE_FAILED:" in line:
            problems.append(line)
        elif line.startswith("ERROR:"):
            if (line_number > marker_at
                    and any(pattern.fullmatch(line) for pattern in KNOWN_SHUTDOWN)):
                recognized += 1
            else:
                problems.append(line)
    return not problems, problems, recognized


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    passed, errors, leaks = verify(args.log.read_text(encoding="utf-8"))
    for error in errors:
        print("T092_NATIVE_LOG_REJECTED:", error)
    if leaks:
        print(f"T092_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {leaks} retained")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
