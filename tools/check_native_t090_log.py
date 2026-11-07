#!/usr/bin/env python3
"""Fail-closed T-090 framebuffer log check; report known Godot/Mesa exit leaks."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SHUTDOWN_LEAKS = (
    re.compile(r"ERROR: Texture with GL ID of \d+: leaked \d+ bytes\."),
    re.compile(r"ERROR: \d+ RID allocations of type '[^']+' were leaked at exit\."),
)
SUMMARY = re.compile(r"T090_NATIVE: (\d+) checks; (\d+) failed")
SUCCESS = re.compile(r"T090_NATIVE_PASSED: (\d+) checks")


def verify(content: str) -> tuple[bool, list[str], int]:
    """Return pass, diagnostic failures and recognized post-marker leak count."""
    lines = content.splitlines()
    summaries = [(index, SUMMARY.fullmatch(line)) for index, line in enumerate(lines)
                 if SUMMARY.fullmatch(line)]
    markers = [(index, SUCCESS.fullmatch(line)) for index, line in enumerate(lines)
               if SUCCESS.fullmatch(line)]
    errors: list[str] = []
    if len(markers) != 1 or len(summaries) != 1:
        errors.append("expected exactly one summary and one success marker")
    elif (summaries[0][0] >= markers[0][0]
          or summaries[0][1].group(1) != markers[0][1].group(1)
          or summaries[0][1].group(2) != "0"
          or int(markers[0][1].group(1)) < 77):
        errors.append("summary and pass marker disagree, report failures, or omit checks")
    marker_line = markers[0][0] if markers else len(lines)
    shutdown_leaks = 0
    for index, line in enumerate(lines):
        if "SCRIPT ERROR:" in line or "T090_NATIVE_FAILED:" in line:
            errors.append(line)
        elif line.startswith("ERROR:"):
            if index > marker_line and any(pattern.fullmatch(line) for pattern in SHUTDOWN_LEAKS):
                shutdown_leaks += 1
            else:
                errors.append(line)
    return not errors, errors, shutdown_leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    ok, errors, leaks = verify(args.log.read_text(encoding="utf-8"))
    for message in errors:
        print("T090_NATIVE_LOG_REJECTED:", message)
    if leaks:
        print(f"T090_NATIVE_SHUTDOWN_LEAK_DIAGNOSTICS: {leaks} retained")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
