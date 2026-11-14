#!/usr/bin/env python3
"""Replay the checked-in fast Godot CI steps locally, preserving all outcomes.

This is a diagnostic rehearsal, never a substitute for a GitHub-hosted CI run.
It intentionally executes the workflow's own Bash commands; it does not invent
alternative tests or treat a selected subset as a complete green CI result.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from report_godot_ci import WORKFLOW, expected_check_ids, summarize

ROOT = Path(__file__).resolve().parents[1]
ENGINE_VERSION = re.compile(r"^4\.8\.beta3\.official\.")
STEP_START = re.compile(r"^      - name: (.+)$", re.MULTILINE)
STEP_ID = re.compile(r"^        id: (ci_[a-z0-9_]+)$", re.MULTILINE)
RUN_LINE = re.compile(r"^        run: (.+)$", re.MULTILINE)


@dataclass(frozen=True)
class Check:
    identifier: str
    name: str
    script: str


def extract_checks(workflow: str) -> list[Check]:
    """Parse the narrow checked-in steps convention without a YAML dependency.

    Reject a CI-step change that cannot be replayed verbatim instead of
    silently claiming its test succeeded.
    """
    matches = list(STEP_START.finditer(workflow))
    if not matches:
        raise ValueError("No workflow steps found")
    checks: list[Check] = []
    for index, match in enumerate(matches):
        block = workflow[match.end():matches[index + 1].start() if index + 1 < len(matches) else len(workflow)]
        ids = STEP_ID.findall(block)
        if not ids:
            continue  # checkout, engine setup, version preflight, final summary
        if len(ids) != 1:
            raise ValueError(f"Ambiguous check ID in {match.group(1)}")
        if re.search(r"^        uses:", block, re.MULTILINE):
            raise ValueError(f"External action cannot be replayed: {ids[0]}")
        if "        if: ${{ !cancelled() }}" not in block or "        continue-on-error: true" not in block:
            raise ValueError(f"Nonstandard step conditions cannot be replayed: {ids[0]}")
        if re.search(r"^        (?:env:|shell: (?!bash$))", block, re.MULTILINE):
            raise ValueError(f"Nonstandard step environment or shell: {ids[0]}")
        if len(RUN_LINE.findall(block)) != 1:
            raise ValueError(f"Missing or multiple run commands: {ids[0]}")
        run = RUN_LINE.search(block)
        if run is None:
            raise ValueError(f"Missing Bash run command: {ids[0]}")
        if run.group(1) in ("|", "|-"):
            lines: list[str] = []
            for line in block[run.end():].splitlines():
                if line.startswith("          "):
                    lines.append(line[10:])
                elif not line.strip():
                    lines.append("")
                else:
                    break
            script = "\n".join(lines).strip("\n") + "\n"
        else:
            script = run.group(1) + "\n"
        if not script.strip() or "${{" in script:
            raise ValueError(f"Missing or unresolved GitHub expression in {ids[0]}")
        checks.append(Check(ids[0], match.group(1), script))
    if [check.identifier for check in checks] != expected_check_ids(workflow):
        raise ValueError("Parsed Bash checks differ from workflow inventory")
    return checks


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_checks(checks: list[Check], destination: Path, *, timeout_seconds: int,
               selected: set[str] | None = None, cwd: Path = ROOT) -> dict[str, Any]:
    """Execute every selected command, even after prior failures.

    Each command gets a dedicated process group so the watchdog kills nested
    Godot/compiler children as well as Bash on timeout.
    """
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    identifiers = [check.identifier for check in checks]
    if len(identifiers) != len(set(identifiers)) or not identifiers:
        raise ValueError("Check inventory is empty or duplicated")
    unknown = (selected or set()) - set(identifiers)
    if unknown:
        raise ValueError(f"Unknown selected IDs: {sorted(unknown)}")
    destination.mkdir(parents=True, exist_ok=False)
    (destination / "logs").mkdir()
    (destination / "scripts").mkdir()
    outcomes: dict[str, dict[str, str]] = {}
    records: list[dict[str, Any]] = []
    for check in checks:
        if selected is not None and check.identifier not in selected:
            continue
        script = destination / "scripts" / f"{check.identifier}.sh"
        log = destination / "logs" / f"{check.identifier}.log"
        script.write_text(check.script, encoding="utf-8")
        start = time.monotonic()
        timed_out = False
        with log.open("wb") as output:
            child = subprocess.Popen(
                ["bash", "--noprofile", "--norc", "-eo", "pipefail", str(script)],
                cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                exit_code = child.wait(timeout=timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                exit_code = child.returncode
        outcome = "timeout" if timed_out else "success" if exit_code == 0 else "failure"
        outcomes[check.identifier] = {"outcome": outcome}
        records.append({
            "id": check.identifier,
            "name": check.name,
            "outcome": outcome,
            "exit_code": exit_code,
            "duration_seconds": round(time.monotonic() - start, 3),
            "script_sha256": _sha256(script),
            "log_sha256": _sha256(log),
            "log": str(log.relative_to(destination)),
        })
        print(f"{outcome.upper():8} {check.identifier} ({records[-1]['duration_seconds']:.1f}s)", flush=True)
    summary, all_passed = summarize(outcomes, identifiers)
    (destination / "summary.md").write_text(
        "**LOCAL REPLAY — NOT REMOTE GITHUB ACTIONS OR OWNER ACCEPTANCE**\n\n" + summary,
        encoding="utf-8",
    )
    return {
        "complete": len(records) == len(checks),
        "passed": all_passed,
        "checks_total": len(checks),
        "checks_executed": len(records),
        "checks": records,
    }


def revision_identity(head: str, *, dirty: bool, expected: str | None,
                      allow_dirty: bool) -> dict[str, Any]:
    """Never attach a commit attestation to uncommitted source changes."""
    if expected is not None and head != expected:
        raise ValueError("Checkout differs from --expected-commit")
    if dirty and (expected is not None or not allow_dirty):
        raise ValueError("Working tree is dirty; commit first or use --allow-dirty for exploratory runs")
    return {
        "candidate_commit": head if not dirty else None,
        "base_head_sha": head,
        "working_tree_clean": not dirty,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path,
                        help="New directory outside the Git repository for scripts and full logs")
    parser.add_argument("--check", action="append", dest="checks", metavar="CI_STEP_ID",
                        help="Run selected checks only (summary remains incomplete)")
    parser.add_argument("--timeout-seconds", type=int, default=1800,
                        help="Per-step watchdog; default 1800")
    parser.add_argument("--expected-commit", help="Require the exact 40-character candidate SHA")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="Exploratory only: dirty source has no candidate-commit attestation")
    args = parser.parse_args(argv)
    try:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        checks = extract_checks(workflow)
        git_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, text=True).strip())
        identity = revision_identity(git_sha, dirty=dirty,
                                     expected=args.expected_commit, allow_dirty=args.allow_dirty)
        godot_version = subprocess.check_output(["godot", "--version"], cwd=ROOT, text=True).strip()
        if not ENGINE_VERSION.match(godot_version):
            raise ValueError(f"Godot version is not pinned 4.8 beta3: {godot_version}")
        output = args.output.resolve()
        if ROOT == output or ROOT in output.parents:
            raise ValueError("Place replay logs outside the tracked repository")
        report = run_checks(checks, output, timeout_seconds=args.timeout_seconds,
                            selected=set(args.checks) if args.checks else None)
        report.update({
            "schema_version": 1,
            **identity,
            "godot_version": godot_version,
            "workflow_sha256": hashlib.sha256(workflow.encode()).hexdigest(),
            "runner": "local-fast-CI-replay-not-GitHub",
        })
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Local result: {report['checks_executed']}/{report['checks_total']} executed; "
              f"complete={report['complete']}; passed={report['passed']}", flush=True)
        return 0 if report["passed"] else 1
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"Local replay rejected: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
