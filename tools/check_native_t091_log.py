#!/usr/bin/env python3
"""Fail-closed T-091 X11 dock witness log check with explicit teardown caveats."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUMMARY = re.compile(r"T091_NATIVE: (\d+) checks; (\d+) failed")
GRIP_SUMMARY = re.compile(r"T091_GRIP_NATIVE: (\d+) checks; (\d+) failed")
MARKER = "T091_NATIVE_PASSED"
GRIP_MARKER = "T091_GRIP_NATIVE_PASSED"
KNOWN_SHUTDOWN = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)


def verify(content: str, *, kind: str = "single") -> tuple[bool, list[str], int]:
    """Validate check count, unique success marker, and every error location.

    Returns
    -------
    tuple[bool, list[str], int]
        Whether valid, all disqualifying log lines, known post-success leaks.
    """
    if kind not in {"single", "grip"}:
        raise ValueError("unknown T-091 native witness")
    pattern, marker, minimum = ((GRIP_SUMMARY, GRIP_MARKER, 53) if kind == "grip"
                                else (SUMMARY, MARKER, 44))
    lines = content.splitlines()
    summaries = [(i, pattern.fullmatch(line)) for i, line in enumerate(lines)
                 if pattern.fullmatch(line)]
    markers = [i for i, line in enumerate(lines) if line == marker]
    problems: list[str] = []
    if len(summaries) != 1 or len(markers) != 1:
        problems.append("expected exactly one passing summary and success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < minimum
          or int(summaries[0][1].group(2)) != 0):
        problems.append("incomplete test count, failed assertions, or invalid marker order")
    marker_at = markers[0] if markers else len(lines)
    recognized = 0
    for line_number, line in enumerate(lines):
        if "SCRIPT ERROR:" in line or "T091_NATIVE_FAILED:" in line or "T091_GRIP_NATIVE_FAILED:" in line:
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
    parser.add_argument("--kind", choices=("single", "grip"), default="single")
    args = parser.parse_args()
    passed, errors, leaks = verify(args.log.read_text(encoding="utf-8"), kind=args.kind)
    for error in errors:
        print("T091_NATIVE_LOG_REJECTED:", error)
    if leaks:
        print(f"T091_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {leaks} retained")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
