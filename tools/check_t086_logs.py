#!/usr/bin/env python3
"""Verify current native viewport and renderer logs, without reusing stale baselines.

The historical pre-T-086 cold renderer fixtures are immutable, but they no
longer compile against the current DrawingRenderer API. The current renderer
has separate deterministic RGBA8 fingerprints at Godot 4.8 beta 3.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

from check_godot_model_log import verify_log

VIEWPORT_SUMMARY = re.compile(r"T086_NATIVE: (\d+) checks; (\d+) failed\Z")
COLD_PREFIX = "T086_COLD_BENCH_JSON "
COLD_SHA256 = {
    "alpha": "25e7f578b53dd14aa3b5a0a7b5956eb784a363abf294ed2b2e4c5e0597f462a7",
    "empty_alpha": "8a39d2abd3999ab73c34db2476849cddf303ce389b35826850f9a700589b4a90",
    "opaque": "e49dcee7b4b28a4ad6a8de43560d13cfecdb307c1d02a9458da8bc8042debb3a",
}


def verify_viewport(content: str) -> list[str]:
    """Reject incomplete, duplicated, or errored 153-check X11 witnesses."""
    errors, _ = verify_log(content, "T086_NATIVE_PASSED")
    summaries = [m for line in content.splitlines() if (m := VIEWPORT_SUMMARY.fullmatch(line))]
    if len(summaries) != 1 or summaries[0].groups() != ("153", "0"):
        errors.append("Expected one exact T086_NATIVE: 153 checks; 0 failed summary")
    return errors


def verify_cold(content: str) -> list[str]:
    """Check the current renderer's deterministic RGBA8 and complete timing cases."""
    errors, _ = verify_log(content, "T086_COLD_BENCH_PASSED")
    records = [line[len(COLD_PREFIX):] for line in content.splitlines()
               if line.startswith(COLD_PREFIX)]
    if len(records) != 1:
        return errors + ["Expected exactly one current renderer JSON record"]
    try:
        report: dict[str, Any] = json.loads(records[0])
    except (json.JSONDecodeError, TypeError) as exc:
        return errors + [f"Invalid renderer JSON: {exc}"]
    if not isinstance(report, dict):
        return errors + ["Renderer JSON must be an object"]
    if ("4.8-beta3" not in str(report.get("engine", ""))
            or report.get("samples_per_case") != 9
            or report.get("viewport_source") != [256, 256]
            or report.get("storage_stride") != 128
            or report.get("layer_count") != 2):
        errors.append("Current native renderer environment or workload changed")
    cases = report.get("cases")
    if not isinstance(cases, dict) or set(cases) != set(COLD_SHA256):
        return errors + ["Missing or unexpected cold renderer alpha cases"]
    for name, expected in COLD_SHA256.items():
        item = cases[name]
        if not isinstance(item, dict) or item.get("sha256") != expected:
            errors.append(f"RGBA8 fingerprint mismatch: {name}")
            continue
        for key in ("median_ms", "p95_ms"):
            number = item.get(key)
            if isinstance(number, bool) or not isinstance(number, (int, float)) \
                    or not math.isfinite(number) or number <= 0:
                errors.append(f"Missing or invalid positive {key}: {name}")
        median = item.get("median_ms")
        p95 = item.get("p95_ms")
        if isinstance(median, (int, float)) and isinstance(p95, (int, float)) \
                and math.isfinite(median) and math.isfinite(p95) and p95 < median:
            errors.append(f"p95 below median: {name}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("viewport", "cold"))
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        content = args.log.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        print(f"T086_LOG_REJECTED: {exc}")
        return 2
    problems = verify_viewport(content) if args.kind == "viewport" else verify_cold(content)
    for message in problems:
        print(f"T086_LOG_REJECTED: {message}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
