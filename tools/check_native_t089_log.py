#!/usr/bin/env python3
"""Verify the T-089 X11 witness without masking real Godot runtime errors.

Mesa/Godot 4.8-beta2 sometimes reports already-exiting renderer resource
leaks *after* the test has completed and returned its explicit success marker.
The known shutdown diagnostics are retained in the log and reported, but
script errors, failures, runtime errors and unknown teardown errors fail CI.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SUCCESS = "T089_NATIVE_PASSED: 36 checks"
SHUTDOWN_LEAKS = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)


def verify(content: str) -> tuple[bool, list[str], int]:
    """Validate a complete native log, returning (ok, errors, shutdown_leaks)."""
    lines = content.splitlines()
    markers = [index for index, line in enumerate(lines) if line == SUCCESS]
    problems: list[str] = []
    shutdown_leaks = 0
    if len(markers) != 1:
        problems.append(f"expected exactly one '{SUCCESS}' marker; found {len(markers)}")
    marker = markers[0] if markers else len(lines)
    for index, line in enumerate(lines):
        if "SCRIPT ERROR:" in line or "T089_NATIVE_FAILED:" in line:
            problems.append(line)
        elif line.startswith("ERROR:"):
            if index > marker and any(pattern.fullmatch(line) for pattern in SHUTDOWN_LEAKS):
                shutdown_leaks += 1
            else:
                problems.append(line)
    return len(problems) == 0, problems, shutdown_leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    ok, problems, shutdown_leaks = verify(args.log.read_text(encoding="utf-8"))
    for problem in problems:
        print(f"T089_NATIVE_LOG_REJECTED: {problem}")
    if shutdown_leaks:
        print(f"T089_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {shutdown_leaks} retained in full log")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
