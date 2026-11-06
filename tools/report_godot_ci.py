"""Report all Godot workflow outcomes and fail only after the test steps finish."""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any


def summarize(steps: Mapping[str, Any]) -> tuple[str, bool]:
    """Render a GitHub step summary, preserving pre-continue-on-error outcomes.

    Parameters
    ----------
    steps : Mapping[str, Any]
        GitHub Actions toJSON(steps) object.

    Returns
    -------
    tuple[str, bool]
        Markdown report and whether every recorded CI check passed.
    """
    checks: list[tuple[str, str]] = []
    for identifier, value in steps.items():
        if not identifier.startswith("ci_"):
            continue
        outcome = value.get("outcome", "missing") if isinstance(value, Mapping) else "missing"
        checks.append((identifier, str(outcome)))

    failures = [(name, status) for name, status in checks if status != "success"]
    success_count = len(checks) - len(failures)
    lines = ["## Godot CI — all-check summary", "", f"**{success_count}/{len(checks)} checks passed.**", ""]
    if failures:
        lines.extend(["Failed or skipped checks (see their individual step logs):", "",
                      "| Check ID | Outcome |", "| --- | --- |"])
        lines.extend(f"| `{name}` | **{status}** |" for name, status in failures)
    elif checks:
        lines.append("All recorded checks succeeded.")
    else:
        lines.append("**No CI check outcomes were recorded.**")
    return "\n".join(lines) + "\n", bool(checks) and not failures


def main() -> int:
    steps = json.loads(os.environ.get("GODOT_CI_STEPS_JSON", "{}"))
    report, passed = summarize(steps)
    print(report, end="")
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary_path).open("a", encoding="utf-8") as stream:
            stream.write(report)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
