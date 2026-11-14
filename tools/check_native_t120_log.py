#!/usr/bin/env python3
"""Fail-closed T-120 X11 menu/Open witness with explicit post-exit leak accounting."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from check_godot_model_log import verify_log

MARKER = "T120_NATIVE_PASSED"
SUMMARY = re.compile(r"T120_NATIVE: ([1-9][0-9]*) checks; (\d+) failed\Z")
MIN_CHECKS = 20


def verify(content: str) -> tuple[bool, list[str], int]:
    """Verify native witness assertions, completion and retained engine diagnostics.

    Returns
    -------
    tuple[bool, list[str], int]
        True on success, disqualifying log lines, and known post-success leaks.
    """
    problems, leaks = verify_log(content, MARKER)
    lines = content.splitlines()
    summaries = [(index, found) for index, line in enumerate(lines)
                 if (found := SUMMARY.fullmatch(line)) is not None]
    markers = [index for index, line in enumerate(lines) if line == MARKER]
    if len(summaries) != 1 or len(markers) != 1:
        problems.append("expected one exact native summary and success marker")
    elif (summaries[0][0] >= markers[0]
          or int(summaries[0][1].group(1)) < MIN_CHECKS
          or int(summaries[0][1].group(2)) != 0):
        problems.append("missing assertions, reported failures, or invalid marker order")
    return not problems, problems, leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        passed, problems, leaks = verify(args.log.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"T120_NATIVE_LOG_REJECTED: {error}")
        return 2
    for problem in problems:
        print("T120_NATIVE_LOG_REJECTED:", problem)
    if leaks:
        print(f"T120_NATIVE_POST_EXIT_LEAKS: {leaks} retained in {args.log}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
