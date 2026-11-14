#!/usr/bin/env python3
"""Audit a completed local fast-CI replay and its retained source/log bytes.

Checks consistency, not provenance: local logs are not signed GitHub Actions
artifacts and do not replace physical owner acceptance or remote CI.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

from replay_godot_ci import ENGINE_VERSION, Check, extract_checks
from report_godot_ci import WORKFLOW, summarize

COMMIT_SHA = re.compile(r"[0-9a-f]{40}\Z")
PREFIX = "**LOCAL REPLAY — NOT REMOTE GITHUB ACTIONS OR OWNER ACCEPTANCE**\n\n"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_artifact(directory: Path, relative: str) -> bytes:
    """Read only the expected regular file, never a symlink or a parent escape."""
    parts = Path(relative).parts
    if (Path(relative).is_absolute() or ".." in parts or not parts
            or any((directory.joinpath(*parts[:i])).is_symlink()
                   for i in range(1, len(parts) + 1))):
        raise ValueError(f"Unsafe replay artifact path: {relative}")
    destination = directory / relative
    if not destination.is_file():
        raise ValueError(f"Missing, symlinked or non-file replay artifact: {relative}")
    return destination.read_bytes()


def verify_replay(directory: Path, checks: list[Check], workflow: str, *,
                  expected_commit: str | None = None) -> list[str]:
    """Check full inventory, status consistency, original scripts and raw log digests.

    Parameters
    ----------
    directory : Path
        Directory created by the local replay command.
    checks : list[Check]
        Ordered, independently extracted required workflow checks.
    workflow : str
        The exact workflow source used as the expected script inventory.
    expected_commit : str | None
        Full Git commit SHA used for candidate attribution, if provided.

    Returns
    -------
    list[str]
        Problems. An empty list verifies internal integrity and completeness,
        not the authenticity of logs or success of hosted GitHub CI.
    """
    if expected_commit is not None and not COMMIT_SHA.fullmatch(expected_commit):
        raise ValueError("--expected-commit requires a full lowercase 40-digit SHA")
    if checks != extract_checks(workflow):
        raise ValueError("Supplied checks differ from the workflow inventory")
    problems: list[str] = []
    try:
        report = json.loads(_read_artifact(directory, "report.json"))
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as exc:
        return [f"Cannot read replay report: {exc}"]
    if not isinstance(report, dict):
        return ["Replay report is not a JSON object"]
    if report.get("schema_version") != 1 or report.get("runner") != "local-fast-CI-replay-not-GitHub":
        problems.append("Unknown report schema or runner")
    if report.get("workflow_sha256") != _sha256(workflow.encode("utf-8")):
        problems.append("Workflow digest differs from recorded source")
    if not isinstance(report.get("godot_version"), str) or not ENGINE_VERSION.match(report["godot_version"]):
        problems.append("Report does not identify pinned Godot 4.8 beta3")
    revision = report.get("candidate_commit")
    if (not isinstance(revision, str) or not COMMIT_SHA.fullmatch(revision)
            or report.get("base_head_sha") != revision or report.get("working_tree_clean") is not True):
        problems.append("Replay lacks a clean, commit-attributed starting tree")
    if expected_commit is not None and revision != expected_commit:
        problems.append("Replay commit does not match expected candidate")
    records = report.get("checks")
    if not isinstance(records, list):
        return problems + ["Missing replay step records"]
    names = [c.identifier for c in checks]
    if (report.get("complete") is not True or report.get("passed") is not True
            or type(report.get("checks_total")) is not int or report["checks_total"] != len(checks)
            or type(report.get("checks_executed")) is not int or report["checks_executed"] != len(checks)
            or len(records) != len(checks)):
        problems.append("Replay is not a complete, passing run of every required step")

    statuses: dict[str, dict[str, str]] = {}
    for i, check in enumerate(checks):
        if i >= len(records):
            break
        record = records[i]
        if not isinstance(record, dict) or record.get("id") != check.identifier:
            problems.append(f"Step {i + 1} is missing, duplicate or out of order")
            continue
        if record.get("name") != check.name:
            problems.append(f"{check.identifier}: workflow step name changed")
        if (record.get("outcome") != "success" or type(record.get("exit_code")) is not int
                or record["exit_code"] != 0):
            problems.append(f"{check.identifier}: step did not exit successfully")
        duration = record.get("duration_seconds")
        if (type(duration) not in (float, int) or not math.isfinite(duration) or duration < 0):
            problems.append(f"{check.identifier}: invalid step duration")
        script_rel = f"scripts/{check.identifier}.sh"
        log_rel = f"logs/{check.identifier}.log"
        if record.get("log") != log_rel:
            problems.append(f"{check.identifier}: unexpected log path")
        for relative, expected_digest, exact in (
            (script_rel, record.get("script_sha256"), check.script.encode("utf-8")),
            (log_rel, record.get("log_sha256"), None),
        ):
            try:
                contents = _read_artifact(directory, relative)
            except (OSError, ValueError) as exc:
                problems.append(f"{check.identifier}: {exc}")
                continue
            if exact is not None and contents != exact:
                problems.append(f"{check.identifier}: script differs from committed workflow")
            if _sha256(contents) != expected_digest:
                problems.append(f"{check.identifier}: {relative} SHA-256 mismatch")
        statuses[check.identifier] = {"outcome": record.get("outcome", "missing")}

    summary, all_passed = summarize(statuses, names)
    if not all_passed:
        problems.append("Fail-late verdict does not agree with stored step outcomes")
    try:
        observed_summary = _read_artifact(directory, "summary.md")
        if observed_summary != (PREFIX + summary).encode("utf-8"):
            problems.append("Stored summary differs from regenerated fail-late verdict")
    except (OSError, ValueError) as exc:
        problems.append(f"Cannot read replay summary: {exc}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--expected-commit", help="Full commit SHA recorded in the replay")
    args = parser.parse_args(argv)
    try:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        problems = verify_replay(args.directory, extract_checks(workflow), workflow,
                                 expected_commit=args.expected_commit)
    except (OSError, ValueError) as exc:
        print(f"LOCAL_CI_REPLAY_REJECTED: {exc}", file=sys.stderr)
        return 2
    for problem in problems:
        print(f"LOCAL_CI_REPLAY_REJECTED: {problem}", file=sys.stderr)
    if problems:
        return 1
    print("LOCAL_CI_REPLAY_VERIFIED: full checked-in workflow, source scripts, "
          "recorded outcomes, summary and raw log hashes agree; LOCAL ONLY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
