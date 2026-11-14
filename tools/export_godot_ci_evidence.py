#!/usr/bin/env python3
"""Export/audit a *GitHub-hosted* fast-CI outcome snapshot without step outputs.

This is a cross-checkable record of check outcomes, not a signature or proof of
physical/owner acceptance. Verify a downloaded copy against its GitHub run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Mapping

from report_godot_ci import WORKFLOW, expected_check_ids, summarize

HEX40 = re.compile(r"[0-9a-f]{40}\Z")
DIGITS = re.compile(r"[1-9][0-9]*\Z")
GODOT_PIN = re.compile(r"4\.8\.beta3\.official\.[a-zA-Z0-9]+\Z")
RUNNER_OS = {"Linux", "Windows", "macOS"}
SCHEMA_VERSION = 1


def _identity(value: Any, pattern: re.Pattern[str]) -> str | None:
    return value if isinstance(value, str) and pattern.fullmatch(value) else None


def _engine_version() -> str | None:
    try:
        output = subprocess.run(["godot", "--version"], check=True,
                                text=True, capture_output=True, timeout=20).stdout.strip()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    return output if GODOT_PIN.fullmatch(output) else None


def build_evidence(steps: Mapping[str, Any], *, commit: str | None,
                   run_id: str | None, attempt: str | None,
                   runner_os: str | None, godot_version: str | None,
                   workflow: str) -> dict[str, Any]:
    """Serialize only pre-continue-on-error outcomes for known check IDs.

    Failed and incomplete runs still produce useful, explicitly red evidence.
    A GitHub `conclusion: success` must never override `outcome: failure`.
    """
    ids = expected_check_ids(workflow)
    _summary, passed = summarize(steps, ids)
    results: list[dict[str, str]] = []
    for identifier in ids:
        record = steps.get(identifier)
        outcome = record.get("outcome") if isinstance(record, Mapping) else None
        results.append({"id": identifier,
                        "outcome": outcome if outcome in ("success", "failure", "skipped", "cancelled", "timed_out") else "missing"})
    unexpected = sorted(name for name in steps if name.startswith("ci_") and name not in ids)
    # Do not serialize arbitrary step outputs, environment variables or unexpected
    # step names: those may contain secrets. Report only their count.
    identity_ok = bool(_identity(commit, HEX40) and _identity(run_id, DIGITS)
                       and _identity(attempt, DIGITS) and runner_os in RUNNER_OS
                       and isinstance(godot_version, str) and GODOT_PIN.fullmatch(godot_version))
    all_green = bool(passed and identity_ok and not unexpected)
    return {
        "schema_version": SCHEMA_VERSION,
        "kind": "github-actions-observed-steps-not-owner-acceptance",
        "workflow_sha256": hashlib.sha256(workflow.encode("utf-8")).hexdigest(),
        "candidate_commit": _identity(commit, HEX40),
        "github_run_id": _identity(run_id, DIGITS),
        "github_run_attempt": _identity(attempt, DIGITS),
        "runner_os": runner_os if runner_os in RUNNER_OS else None,
        "godot_version": godot_version if isinstance(godot_version, str) and GODOT_PIN.fullmatch(godot_version) else None,
        "expected_check_count": len(ids),
        "recorded_check_count": sum(result["outcome"] != "missing" for result in results),
        "unexpected_check_count": len(unexpected),
        "checks": results,
        "all_required_checks_succeeded": all_green,
        "outcome": "all_checks_succeeded" if all_green else "failed_or_incomplete",
        "note": "Verify the run/attempt and artifact origin on GitHub; this JSON is not a signed attestation or physical UX approval.",
    }


def verify_evidence(evidence: Any, *, workflow: str,
                    expected_commit: str | None = None,
                    expected_run_id: str | None = None) -> list[str]:
    """Fail closed on modified workflow, missing checks and false green claims.

    This verifies *internal consistency*, not artifact authenticity: the
    GitHub-hosted run must be verified independently by the reviewer.
    """
    if not isinstance(evidence, dict):
        return ["Evidence must be a JSON object"]
    problems: list[str] = []
    ids = expected_check_ids(workflow)
    expected_hash = hashlib.sha256(workflow.encode("utf-8")).hexdigest()
    if evidence.get("schema_version") != SCHEMA_VERSION or evidence.get("kind") != "github-actions-observed-steps-not-owner-acceptance":
        problems.append("Unsupported schema or evidence kind")
    if evidence.get("workflow_sha256") != expected_hash:
        problems.append("Workflow hash mismatch")
    for key, pattern in (("candidate_commit", HEX40), ("github_run_id", DIGITS),
                         ("github_run_attempt", DIGITS)):
        if _identity(evidence.get(key), pattern) is None:
            problems.append(f"Invalid {key}")
    if expected_commit is not None and evidence.get("candidate_commit") != expected_commit:
        problems.append("Candidate commit mismatch")
    if expected_run_id is not None and evidence.get("github_run_id") != expected_run_id:
        problems.append("GitHub run ID mismatch")
    if not isinstance(evidence.get("runner_os"), str) or evidence.get("runner_os") not in RUNNER_OS:
        problems.append("Invalid runner OS")
    version = evidence.get("godot_version")
    if not isinstance(version, str) or GODOT_PIN.fullmatch(version) is None:
        problems.append("Godot 4.8-beta3 identity missing")
    checks = evidence.get("checks")
    if not isinstance(checks, list) or any(not isinstance(row, dict) for row in checks):
        return problems + ["Invalid check list"]
    if [row.get("id") for row in checks] != ids:
        problems.append("Missing, duplicated or reordered check IDs")
    if any(row.get("outcome") not in ("success", "failure", "skipped", "cancelled", "timed_out", "missing") for row in checks):
        problems.append("Invalid check outcome")
    count = sum(row.get("outcome") != "missing" for row in checks)
    if evidence.get("expected_check_count") != len(ids) or evidence.get("recorded_check_count") != count:
        problems.append("Incorrect check counts")
    extra = evidence.get("unexpected_check_count")
    if not isinstance(extra, int) or isinstance(extra, bool) or extra < 0:
        problems.append("Invalid unexpected-check count")
    green = (not problems and count == len(ids) and extra == 0
             and all(row.get("outcome") == "success" for row in checks))
    if evidence.get("all_required_checks_succeeded") is not green or evidence.get("outcome") != (
            "all_checks_succeeded" if green else "failed_or_incomplete"):
        problems.append("False or inconsistent overall verdict")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write a sanitized GitHub Actions evidence JSON")
    parser.add_argument("--verify", type=Path, help="Verify previously downloaded JSON")
    parser.add_argument("--expected-commit", help="Expected exact source commit")
    parser.add_argument("--expected-run-id", help="Expected GitHub Actions run ID")
    args = parser.parse_args(argv)
    if bool(args.output) == bool(args.verify):
        parser.error("Choose exactly one of --output or --verify")
    try:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        if args.verify:
            record = json.loads(args.verify.read_text(encoding="utf-8"))
            problems = verify_evidence(record, workflow=workflow,
                                       expected_commit=args.expected_commit,
                                       expected_run_id=args.expected_run_id)
            for issue in problems:
                print(f"CI_EVIDENCE_REJECTED: {issue}")
            if problems:
                return 1
            print("CI_EVIDENCE_VALID_STRUCTURE: verify run identity and artifact on GitHub; not owner approval")
            return 0
        raw = json.loads(os.environ["GODOT_CI_STEPS_JSON"])
        if not isinstance(raw, dict):
            raise ValueError("GODOT_CI_STEPS_JSON is not a mapping")
        record = build_evidence(raw, commit=os.environ.get("GITHUB_SHA"),
                                run_id=os.environ.get("GITHUB_RUN_ID"),
                                attempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                                runner_os=os.environ.get("RUNNER_OS"),
                                godot_version=_engine_version(), workflow=workflow)
        assert args.output is not None
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(f"CI_EVIDENCE_EXPORTED: {record['recorded_check_count']}/{record['expected_check_count']}"
              f" required outcomes; verdict={record['outcome']}; not owner approval")
        return 0  # Explicitly red results still need to be uploaded and inspected.
    except (OSError, UnicodeError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"CI_EVIDENCE_REJECTED: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
