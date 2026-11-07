#!/usr/bin/env python3
"""Prepare and validate owner-run physical Drawing evidence for T-094.

This does not run hardware tests, attest the reporter's identity, approve tickets,
or change the owner-acceptance matrix. It fails closed on incomplete/unsafe files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "docs/DRAWING_OWNER_ACCEPTANCE_MATRIX.md"
HEX_SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
WINDOW = re.compile(r"^[0-9]{3,5}x[0-9]{3,5}$")
SOFTWARE_RENDERERS = ("llvmpipe", "softpipe", "swiftshader", "lavapipe", "software rasterizer")
TIMED_FINDINGS = (1, 15)
TIMING_PHASES = ("down_to_preview_ms", "motion_to_preview_ms", "release_to_commit_ms")


class EvidenceError(ValueError):
    """Evidence cannot establish its claimed result or violates the format."""


def findings() -> dict[int, str]:
    """Read the 23 current runbook IDs and responsible tickets, not a frozen copy."""
    result: dict[int, str] = {}
    for line in MATRIX.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\|\s*(\d{1,2})\s*\|\s*([^|]+)\|", line)
        if match:
            number = int(match.group(1))
            if number in result:
                raise EvidenceError(f"Duplicate finding {number} in runbook")
            result[number] = match.group(2).strip()
    if set(result) != set(range(1, 24)):
        raise EvidenceError("Runbook must contain exactly findings 01–23")
    return result


def blank_manifest(os_name: str) -> dict[str, Any]:
    """Produce an intentionally NOT RUN report for one physical OS."""
    if os_name not in ("Linux", "Windows"):
        raise EvidenceError("Choose Linux or Windows")
    return {
        "schema_version": 1,
        "environment": {
            "os": os_name,
            "physical_display": False,
            "commit": "", "godot_version": "", "gpu": "", "renderer": "",
            "pointer": "", "display_refresh_hz": None,
            "window_px": "", "ui_scale": None, "timestamp": "",
        },
        "results": [
            {"finding": n, "tickets": target, "status": "NOT RUN", "observed": "",
             "artifacts": [], "zooms_percent": [], "timings_ms": {}}
            for n, target in findings().items()
        ],
    }


def _valid_timestamp(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is not None
    except ValueError:
        return False


def _verify_artifacts(artifacts: Any, base: Path, finding: int) -> list[str]:
    problems: list[str] = []
    if not isinstance(artifacts, list) or not artifacts:
        return [f"#{finding:02d}: PASS/FAIL must include hashed evidence artifacts"]
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            problems.append(f"#{finding:02d}: artifact must be an object")
            continue
        name, digest = artifact.get("path"), artifact.get("sha256")
        if not isinstance(name, str) or not name or not isinstance(digest, str) or not HEX_SHA256.fullmatch(digest):
            problems.append(f"#{finding:02d}: artifact path/SHA-256 invalid")
            continue
        relative = Path(name)
        if (relative.is_absolute() or ".." in relative.parts or "." in relative.parts
                or len(relative.parts) > 8):
            problems.append(f"#{finding:02d}: artifact path must be relative and contained")
            continue
        candidate = base / relative
        if (not candidate.is_file() or candidate.is_symlink()
                or candidate.resolve() != candidate.absolute()):
            problems.append(f"#{finding:02d}: missing, redirected or unsafe artifact {name}")
            continue
        hasher = hashlib.sha256()
        with candidate.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                hasher.update(block)
        if hasher.hexdigest() != digest:
            problems.append(f"#{finding:02d}: artifact SHA-256 mismatch: {name}")
    return problems


def _validate_zoom_timings(entry: dict[str, Any], finding: int) -> list[str]:
    """Require independent timing samples for each physical zoom observation.

    `zooms_percent` names the measured zooms; `timings_ms` maps their string
    forms to three per-phase arrays. Pooled samples cannot establish latency
    at the slowest zoom and must not validate as a physical PASS.
    """
    problems: list[str] = []
    zooms = entry.get("zooms_percent")
    if (not isinstance(zooms, list) or any(type(zoom) is not int or not 1 <= zoom <= 800
                                            for zoom in zooms)
            or len(set(zooms)) != len(zooms)
            or not {25, 50, 100}.issubset(zooms)):
        return [f"#{finding:02d}: PASS needs distinct integer 25/50/100% zoom observations"]

    timings = entry.get("timings_ms")
    expected_keys = {str(zoom) for zoom in zooms}
    if not isinstance(timings, dict):
        return [f"#{finding:02d}: timings_ms must contain separate objects for each zoom"]
    if set(timings) != expected_keys:
        problems.append(f"#{finding:02d}: timing zoom keys must match recorded zooms {sorted(expected_keys)}")
    for key in sorted(expected_keys):
        phases = timings.get(key)
        if not isinstance(phases, dict):
            problems.append(f"#{finding:02d}: zoom {key}% needs a timing object")
            continue
        if set(phases) != set(TIMING_PHASES):
            problems.append(f"#{finding:02d}: zoom {key}% needs exactly {', '.join(TIMING_PHASES)}")
        for phase in TIMING_PHASES:
            samples = phases.get(phase)
            if (not isinstance(samples, list) or len(samples) < 5
                    or any(type(value) not in (int, float) or not 0 <= value <= 120_000
                           or not math.isfinite(value) for value in samples)):
                problems.append(f"#{finding:02d}: zoom {key}% {phase} needs five finite nonnegative samples in ms")
    return problems


def percentile_ms(samples: list[int | float], percentile: float) -> float:
    """Return a linearly interpolated (R-7) percentile of validated samples.

    A five-sample p95 lies between the fourth and fifth ordered values, rather
    than silently implying 20 or more independent observations.

    Parameters
    ----------
    samples : list[int | float]
        Five or more finite nonnegative millisecond observations, previously
        checked by ``_validate_zoom_timings``.
    percentile : float
        Requested percentile in the inclusive 0–100 range.

    Returns
    -------
    float
        Sample percentile in milliseconds.
    """
    ordered = sorted(samples)
    rank = (len(ordered) - 1) * percentile / 100.0
    lower = math.floor(rank)
    upper = math.ceil(rank)
    weight = rank - lower
    return float(ordered[lower] + (ordered[upper] - ordered[lower]) * weight)


def timing_summary(manifest: dict[str, Any]) -> list[str]:
    """Format medians/p95 for validated physical PASS findings #01/#15 only.

    Call only after ``validate`` and the cross-OS cohort check have succeeded.
    Never derive a timing claim from FAIL or NOT RUN rows, and never confuse
    recorded frame callbacks with a hardware input-to-photon measurement.
    """
    result: list[str] = []
    os_name: str = manifest["environment"]["os"]
    for entry in manifest["results"]:
        if entry["finding"] not in TIMED_FINDINGS or entry["status"] != "PASS":
            continue
        for zoom in sorted(entry["zooms_percent"]):
            phases = entry["timings_ms"][str(zoom)]
            for phase in TIMING_PHASES:
                samples = phases[phase]
                result.append(
                    f"{os_name} #{entry['finding']:02d} {zoom}% {phase}: "
                    f"n={len(samples)} p50={percentile_ms(samples, 50):.3f} ms "
                    f"p95={percentile_ms(samples, 95):.3f} ms"
                )
    return result


def validate(manifest: Any, directory: Path) -> tuple[list[str], int, int]:
    """Validate evidence honesty/integrity, without equating it to owner signoff.

    Returns
    -------
    tuple[list[str], int, int]
        Problems, number of PASS results and number of FAIL results.
    """
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise EvidenceError("Unsupported owner evidence schema")
    environment = manifest.get("environment")
    if not isinstance(environment, dict) or environment.get("os") not in ("Linux", "Windows"):
        raise EvidenceError("Missing supported OS (Linux or Windows)")
    expected = findings()
    entries = manifest.get("results")
    if not isinstance(entries, list):
        raise EvidenceError("results must be an array")
    problems: list[str] = []
    found: set[int] = set()
    passed = failed = 0
    for entry in entries:
        if not isinstance(entry, dict) or type(entry.get("finding")) is not int:
            problems.append("Finding row must be an object with integer ID")
            continue
        number = entry["finding"]
        if number not in expected or number in found:
            problems.append(f"Duplicate or unknown finding {number}")
            continue
        found.add(number)
        if entry.get("tickets") != expected[number]:
            problems.append(f"#{number:02d}: ticket mapping differs from current runbook")
        state = entry.get("status")
        if state == "NOT RUN":
            # Prevent attaching an old positive outcome to a NOT RUN row.
            if (entry.get("observed") or entry.get("artifacts")
                    or entry.get("timings_ms") or entry.get("zooms_percent")):
                problems.append(f"#{number:02d}: NOT RUN cannot contain observed results")
            continue
        if state not in ("PASS", "FAIL"):
            problems.append(f"#{number:02d}: invalid status {state!r}")
            continue
        passed += state == "PASS"
        failed += state == "FAIL"
        if environment.get("physical_display") is not True:
            problems.append(f"#{number:02d}: physical_display must be true for physical result")
        if not isinstance(entry.get("observed"), str) or len(entry["observed"].strip()) < 20:
            problems.append(f"#{number:02d}: record a substantive observed result")
        problems.extend(_verify_artifacts(entry.get("artifacts"), directory, number))
        if number in TIMED_FINDINGS and state == "PASS":
            problems.extend(_validate_zoom_timings(entry, number))
    missing = set(expected) - found
    if missing:
        problems.append(f"Missing findings: {sorted(missing)}")
    if len(entries) != 23:
        problems.append(f"Expected exactly 23 rows, got {len(entries)}")
    if passed or failed:
        if not COMMIT.fullmatch(str(environment.get("commit", ""))):
            problems.append("Physical results require an exact 40-character Git commit")
        version = environment.get("godot_version")
        if not isinstance(version, str) or not version.startswith("4.8.beta2.official."):
            problems.append("Physical results require exact Godot 4.8 beta2 version")
        if not _valid_timestamp(environment.get("timestamp")):
            problems.append("Physical results require an offset-aware ISO 8601 timestamp")
        if not WINDOW.fullmatch(str(environment.get("window_px", ""))):
            problems.append("Physical results require window width x height")
        if (type(environment.get("ui_scale")) not in (int, float)
                or not 0.5 <= environment["ui_scale"] <= 5):
            problems.append("Physical results require numeric UI scale")
        refresh = environment.get("display_refresh_hz")
        if type(refresh) not in (int, float) or not 20 <= refresh <= 500:
            problems.append("Physical results require a display refresh rate")
        for field in ("gpu", "renderer", "pointer"):
            value = environment.get(field)
            if not isinstance(value, str) or len(value.strip()) < 3:
                problems.append(f"Physical results require {field}")
            elif field in ("gpu", "renderer") and any(token in value.lower() for token in SOFTWARE_RENDERERS):
                problems.append(f"Software renderer cannot support physical GPU claim: {field}")
    return problems, passed, failed


def check_cohort(
    manifests: dict[str, dict[str, Any]], expected_commit: str | None = None,
) -> list[str]:
    """Reject mixed-code or mixed-engine physical results in a combined review.

    Unrun templates are allowed in a partial review and have no test identity.
    This validates recorded metadata only; it cannot attest a physical device.

    Parameters
    ----------
    manifests : dict[str, dict[str, Any]]
        OS-keyed evidence manifests already checked individually.
    expected_commit : str | None
        Exact candidate revision, when the reviewer supplies one.

    Returns
    -------
    list[str]
        Cross-report contradictions and target-commit mismatches.
    """
    problems: list[str] = []
    if expected_commit is not None and not COMMIT.fullmatch(expected_commit):
        return ["--expected-commit must be a full 40-character lowercase Git SHA"]

    observed: dict[str, dict[str, Any]] = {}
    for os_name, manifest in manifests.items():
        rows = manifest["results"]
        if any(row.get("status") in ("PASS", "FAIL") for row in rows):
            observed[os_name] = manifest["environment"]

    if expected_commit is not None:
        for os_name, environment in observed.items():
            if environment.get("commit") != expected_commit:
                problems.append(f"{os_name}: tested commit differs from --expected-commit")

    for key, label in (("commit", "Git commit"), ("godot_version", "Godot build")):
        distinct = {str(info.get(key, "")) for info in observed.values()}
        if len(distinct) > 1:
            problems.append(f"Mixed {label} across physical OS reports; run both on one build")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    init = subparsers.add_parser("init", help="Write a NOT RUN template; refuses overwrite")
    init.add_argument("--os", choices=("Linux", "Windows"), required=True)
    init.add_argument("--output", type=Path, required=True)
    verify = subparsers.add_parser("verify", help="Validate one or two filled evidence manifests")
    verify.add_argument("manifests", nargs="+", type=Path)
    verify.add_argument("--require-complete", action="store_true",
                        help="Fail unless 23 PASS results are evidenced on *both* physical OSes")
    verify.add_argument("--expected-commit",
                        help="Require all observed physical results to match this full Git SHA")
    verify.add_argument("--timing-summary", action="store_true",
                        help="Print validated per-zoom p50/p95 timing samples (not hardware attestation)")
    args = parser.parse_args(argv)
    try:
        if args.action == "init":
            with args.output.open("x", encoding="utf-8") as stream:
                json.dump(blank_manifest(args.os), stream, indent=2, ensure_ascii=False)
                stream.write("\n")
            print(f"Created NOT RUN {args.os} template at {args.output}")
            return 0
        seen: set[str] = set()
        counts: dict[str, tuple[int, int]] = {}
        manifests: dict[str, dict[str, Any]] = {}
        for path in args.manifests:
            report = json.loads(path.read_text(encoding="utf-8"))
            problems, passed, failed = validate(report, path.resolve().parent)
            os_name = report["environment"]["os"]
            if os_name in seen:
                problems.append(f"Duplicate {os_name} manifest")
            seen.add(os_name)
            counts[os_name] = (passed, failed)
            manifests[os_name] = report
            for problem in problems:
                print(f"{path}: {problem}", file=sys.stderr)
            if problems:
                return 2
        contradictions = check_cohort(manifests, expected_commit=args.expected_commit)
        if contradictions:
            for problem in contradictions:
                print(f"Physical evidence cohort rejected: {problem}", file=sys.stderr)
            return 2
        for os_name, (passed, failed) in counts.items():
            print(f"{os_name}: PASS {passed}/23, FAIL {failed}/23, NOT RUN {23-passed-failed}/23")
        if args.require_complete and (set(counts) != {"Linux", "Windows"}
                                      or any(count != (23, 0) for count in counts.values())):
            print("Physical evidence incomplete: require 23 PASS rows on each OS", file=sys.stderr)
            return 1
        if args.timing_summary:
            lines = [line for report in manifests.values() for line in timing_summary(report)]
            if lines:
                print("Validated reported timing samples (R-7 interpolation; not input-to-photon attestation):")
                for line in lines:
                    print(line)
            else:
                print("No validated PASS timing observations for findings #01/#15.")
        print("Evidence files are structurally valid; owner approval is never inferred.")
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"Owner evidence rejected: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
