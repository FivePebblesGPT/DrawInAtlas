#!/usr/bin/env python3
"""Audit all fast-CI replay artifacts and expose unresolved owner actions.

This is an integrity/provenance *inventory*, never hosted-CI or physical UX
acceptance. In particular, a valid exploratory replay is explicitly untrusted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from check_godot_model_log import verify_log
from drawing_owner_evidence import blank_manifest, validate
from replay_godot_ci import extract_checks
from report_godot_ci import WORKFLOW
from verify_godot_ci_replay import verify_replay

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
MATRIX = DOCS / "DRAWING_OWNER_ACCEPTANCE_MATRIX.md"
REVIEW = DOCS / "DRAWING_USABILITY_REVIEW_2026-11-05.md"
SHA40 = re.compile(r"[0-9a-f]{40}\Z")
TICKET = re.compile(r"T-[0-9]{3}")
REPLAY_UNATTESTED = "Replay lacks a clean, commit-attributed starting tree"
MANUAL_GATES = ("T-056", "T-059", "T-065", "T-083", "T-095", "T-096")
RUNTIME = DOCS / "evidence/T-107-2026-11-12-runtime"
RUNTIME_MARKERS = {
    "standalone-roundtrip.log": "DRAWING_STANDALONE_PASSED",
    "atlas-composition.log": "T055_COMPOSITION_PASSED",
    "atlas-bundle.log": "ATLAS_BUNDLE_PASSED",
}


class AuditError(ValueError):
    """A required artifact or review mapping fails an integrity check."""


def _read_rows(path: Path) -> dict[int, list[str]]:
    """Read the canonical numbered owner findings, rejecting duplicates."""
    rows: dict[int, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\|\s*\d{1,2}\s*\|", line):
            continue
        columns = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(columns) != (4 if path == REVIEW else 6):
            raise AuditError(f"Malformed row in {path.name}: {line}")
        number = int(columns[0])
        if number in rows:
            raise AuditError(f"Duplicate owner finding #{number:02d}")
        rows[number] = columns
    if set(rows) != set(range(1, 24)):
        raise AuditError(f"{path.name} does not contain exactly findings 01–23")
    return rows


def owner_actions() -> list[dict[str, Any]]:
    """Return a per-finding action, not a fabricated physical observation.

    Both OS manifests are generated afresh and validated by the canonical
    T-094 owner-evidence validator. The historical success at #22 and the
    documented revision semantics at #23 do not become physical PASS records.
    """
    review = _read_rows(REVIEW)
    matrix = _read_rows(MATRIX)
    for os_name in ("Linux", "Windows"):
        manifest = blank_manifest(os_name)
        problems, passed, failed = validate(manifest, ROOT)
        if problems or passed or failed or any(x["status"] != "NOT RUN" for x in manifest["results"]):
            raise AuditError(f"Invalid unobserved {os_name} owner evidence: {problems}")

    rows: list[dict[str, Any]] = []
    for number, values in sorted(matrix.items()):
        original = review[number]
        tickets = TICKET.findall(values[1])
        if (not tickets or set(tickets) != set(TICKET.findall(original[2]))
                or not values[2] or not values[3] or not values[4]):
            raise AuditError(f"#{number:02d}: missing or incorrect owner action/evidence mapping")
        for ticket in tickets:
            if not (DOCS / f"Tickets/{ticket}.md").is_file():
                raise AuditError(f"#{number:02d}: missing mapped ticket {ticket}")
        required_state = ("OWNER PASS / REGRESSION" if number == 22 else
                          "MODEL EXPECTED / UI PENDING" if number == 23 else "PENDING")
        if values[5] != required_state:
            raise AuditError(f"#{number:02d}: owner evidence status altered without review")
        rows.append({
            "finding": number,
            "tickets": tickets,
            "matrix_source": "docs/DRAWING_OWNER_ACCEPTANCE_MATRIX.md",
            "review_source": "docs/DRAWING_USABILITY_REVIEW_2026-11-05.md",
            "engineering_observation": values[4],
            "finding_state": values[5],
            "physical_action": values[2],
            "expected": values[3],
            "physical_linux": "NOT RUN",
            "physical_windows": "NOT RUN",
            "owner_acceptance": "NOT GRANTED",
        })
    return rows


def manual_gates() -> list[dict[str, str]]:
    """Retain the hard-gate frontmatter as a separate pending owner action."""
    gates: list[dict[str, str]] = []
    for identifier in MANUAL_GATES:
        path = DOCS / f"Tickets/{identifier}.md"
        frontmatter = path.read_text(encoding="utf-8").split("---", 2)[1]
        status = re.search(r'^status:\s*"?([^"\n]+)"?', frontmatter, re.MULTILINE)
        if (not re.search(r"^manual_review:\s*true\s*$", frontmatter, re.MULTILINE)
                or status is None or status.group(1).strip() in {"Done", "Archived"}):
            raise AuditError(f"Manual gate {identifier} was unexpectedly cleared")
        gates.append({"ticket": identifier, "status": status.group(1).strip(),
                      "required_action": "explicit owner review; no agent approval",
                      "source": f"docs/Tickets/{identifier}.md"})
    return gates


def _read_regular(path: Path) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise AuditError(f"Missing or unsafe raw artifact {path}")
    return path.read_bytes()


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replay_inventory(directory: Path) -> dict[str, Any]:
    """Verify every workflow check, replay script, result and raw log digest.

    An exploratory run is permitted *only as exploratory evidence*: no future
    caller may convert its green checks into hosted or commit-attested status.
    """
    workflow = WORKFLOW.read_text(encoding="utf-8")
    checks = extract_checks(workflow)
    if len(checks) != 46:
        raise AuditError(f"Expected 46 required checks, found {len(checks)}")
    problems = verify_replay(directory, checks, workflow)
    if problems and problems != [REPLAY_UNATTESTED]:
        raise AuditError("Invalid CI replay: " + "; ".join(problems))
    report = json.loads(_read_regular(directory / "report.json"))
    exploratory = bool(problems)
    if exploratory and (report.get("candidate_commit") is not None
                        or report.get("working_tree_clean") is not False):
        raise AuditError("Exploratory provenance fields are inconsistent")
    records = report["checks"]
    inventory: list[dict[str, Any]] = []
    for check, record in zip(checks, records, strict=True):
        raw_log = _read_regular(directory / "logs" / f"{check.identifier}.log")
        inventory.append({"id": check.identifier, "outcome": record["outcome"],
                          "exit_code": record["exit_code"],
                          "script_sha256": record["script_sha256"],
                          "log_sha256": _hash(raw_log), "log_bytes": len(raw_log)})
    return {"kind": "local-exploratory" if exploratory else "local-commit-attributed",
            "not_github_hosted": True,
            "checks_total": len(checks),
            "checks_passed": len(inventory),
            "engine": report["godot_version"],
            "report_sha256": _hash(_read_regular(directory / "report.json")),
            "summary_sha256": _hash(_read_regular(directory / "summary.md")),
            "workflow_sha256": _hash(workflow.encode("utf-8")),
            "checks": inventory}


def runtime_inventory(directory: Path = RUNTIME) -> dict[str, Any]:
    """Validate exact runtime markers and retain hashes of isolated raw logs.

    The process exit codes are separately witnessed by the documented `set -e`
    shell invocation. This verifies saved output bytes, not the exit codes of
    programs whose processes have already terminated.
    """
    results: list[dict[str, Any]] = []
    required = ("godot-version.log", "standalone-build.log", "standalone-import.log",
                "standalone-roundtrip.log", "standalone-verify.log",
                "atlas-composition.log", "atlas-composition-verify.log",
                "atlas-bundle.log", "atlas-bundle-verify.log")
    for name in required:
        data = _read_regular(directory / name)
        if not data and name not in ("atlas-bundle-verify.log",):
            raise AuditError(f"Empty runtime evidence: {name}")
        if name in RUNTIME_MARKERS:
            problems, known_leaks = verify_log(data.decode("utf-8"), RUNTIME_MARKERS[name])
            if problems:
                raise AuditError(f"Runtime {name}: " + "; ".join(problems))
        else:
            known_leaks = 0
        results.append({"name": name, "sha256": _hash(data), "bytes": len(data),
                        "known_post_exit_leak_diagnostics": known_leaks})
    if b"4.8.beta3.official.c51ff06e8" not in _read_regular(directory / "godot-version.log"):
        raise AuditError("Runtime engine version is not the pinned beta3 build")
    return {"kind": "local-isolated-regression-not-physical-acceptance",
            "checks": results, "source_scope": "canonical standalone Drawing and Atlas integration"}


def audit(directory: Path, *, remote_head: str, local_head: str) -> dict[str, Any]:
    """Build a reproducible local readiness report with no implied approvals."""
    if not SHA40.fullmatch(remote_head) or not SHA40.fullmatch(local_head):
        raise AuditError("Provide two exact lowercase 40-character commit SHAs")
    return {
        "schema_version": 1,
        "candidate_head_before_t107": local_head,
        "last_confirmed_pr_head": remote_head,
        "hosted_ci": {
            "status": "NOT VERIFIED FOR CANDIDATE",
            "reason": "Local HEAD differs from last confirmed PR head" if remote_head != local_head
                      else "No independent GitHub-hosted outcome artifact and raw-log provenance",
            "result_cannot_be_inferred_from_local_replay": True,
        },
        "required_fast_ci": replay_inventory(directory),
        "standalone_atlas_runtime": runtime_inventory(),
        "owner_findings": owner_actions(),
        "unapproved_manual_gates": manual_gates(),
    }


def copy_replay(source: Path, destination: Path) -> None:
    """Snapshot exactly the files audited, rejecting preexisting destinations."""
    if destination.exists():
        raise AuditError(f"Snapshot target already exists: {destination}")
    replay_inventory(source)  # Reject incorrect or incomplete source before copying.
    destination.mkdir(parents=True)
    (destination / "logs").mkdir()
    (destination / "scripts").mkdir()
    checks = extract_checks(WORKFLOW.read_text(encoding="utf-8"))
    for name in ("report.json", "summary.md"):
        (destination / name).write_bytes(_read_regular(source / name))
    for check in checks:
        for group, extension in (("scripts", "sh"), ("logs", "log")):
            name = f"{check.identifier}.{extension}"
            (destination / group / name).write_bytes(_read_regular(source / group / name))
    replay_inventory(destination)  # Verify entire retained copy again.


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay", type=Path, required=True,
                        help="Directory containing all 46 replay logs/scripts/report")
    parser.add_argument("--remote-head", required=True)
    parser.add_argument("--local-head", required=True)
    parser.add_argument("--output", type=Path,
                        help="Write audit JSON; otherwise print result")
    parser.add_argument("--snapshot", type=Path,
                        help="Copy checked logs, scripts and report to a new directory")
    parser.add_argument("--verify", type=Path,
                        help="Compare saved report to freshly recomputed source and logs")
    args = parser.parse_args(argv)
    if args.verify and (args.output or args.snapshot):
        parser.error("--verify cannot be combined with --output or --snapshot")
    try:
        if args.snapshot:
            copy_replay(args.replay, args.snapshot)
        audited = audit(args.snapshot or args.replay,
                        remote_head=args.remote_head, local_head=args.local_head)
        if args.verify:
            existing = json.loads(_read_regular(args.verify))
            if existing != audited:
                raise AuditError("Saved T-107 audit differs from current workflow, raw logs or owner matrix")
        elif args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(audited, indent=2, ensure_ascii=False) + "\n",
                                   encoding="utf-8")
        else:
            print(json.dumps(audited, indent=2, ensure_ascii=False))
    except (AuditError, ValueError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"T107_EVIDENCE_REJECTED: {exc}", file=sys.stderr)
        return 1
    print("T107_EVIDENCE_VERIFIED: 46 raw CI logs and all 23 owner actions; "
          "local evidence only, no hosted or owner acceptance", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
