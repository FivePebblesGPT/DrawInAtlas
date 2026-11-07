"""Report all Godot workflow outcomes and fail only after the test steps finish."""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/godot-check.yml"
CHECK_ID_PATTERN = re.compile(r"^        id: (ci_[a-z0-9_]+)$", re.MULTILINE)


def expected_check_ids(workflow: str) -> list[str]:
    """Read the set of required step IDs from the committed workflow.

    This deliberately uses the narrow, indented check-ID convention rather
    than requiring a YAML package on GitHub's default Python runner.
    """
    identifiers = CHECK_ID_PATTERN.findall(workflow)
    duplicates = [name for name, count in Counter(identifiers).items() if count > 1]
    if not identifiers or duplicates:
        raise ValueError(f"Missing check IDs or duplicate IDs: {duplicates}")
    return identifiers


def summarize(steps: Mapping[str, Any], expected_ids: Sequence[str] | None = None) -> tuple[str, bool]:
    """Render a GitHub step summary, preserving pre-continue-on-error outcomes.

    Parameters
    ----------
    steps : Mapping[str, Any]
        GitHub Actions toJSON(steps) object.
    expected_ids : Sequence[str] | None
        Check IDs parsed from the committed workflow. When provided, missing
        or unexpected results are failures rather than silently omitted.

    Returns
    -------
    tuple[str, bool]
        Markdown report and whether every recorded CI check passed.
    """
    if expected_ids is None:
        identifiers = [name for name in steps if name.startswith("ci_")]
    else:
        identifiers = list(expected_ids)
    checks: list[tuple[str, str]] = []
    for identifier in identifiers:
        value = steps.get(identifier)
        outcome = value.get("outcome", "missing") if isinstance(value, Mapping) else "missing"
        checks.append((identifier, str(outcome)))
    unexpected = sorted(name for name in steps if name.startswith("ci_") and name not in identifiers)
    checks.extend((name, "unexpected") for name in unexpected)

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
    try:
        steps = json.loads(os.environ.get("GODOT_CI_STEPS_JSON", "{}"))
        if not isinstance(steps, dict):
            raise ValueError("CI steps JSON must be a mapping")
        required = expected_check_ids(WORKFLOW.read_text(encoding="utf-8"))
        report, passed = summarize(steps, expected_ids=required)
    except (OSError, ValueError, TypeError) as exc:
        report, passed = f"## Godot CI — invalid check report\n\n**{exc}**\n", False
    print(report, end="")
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary_path).open("a", encoding="utf-8") as stream:
            stream.write(report)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
