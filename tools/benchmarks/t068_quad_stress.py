#!/usr/bin/env python3
"""T-068 varied-convex-polygon selection parity screen, not shipping code.

Godot's real AtlasFill._allows_pixel() authors the pinned oracle. C++ masks
are checked byte-for-byte; discrepancies are reported, never waived.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from typing import Any

from t068_quad_differential import NativeQuad

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/benchmarks/t068_quad_scope_kernel.cpp"
ORACLE = ROOT / "tools/benchmarks/t068_quad_stress_oracle.json"
ORACLE_SHA256 = "b93c8f80165d628ce9de53948ea4f3e2de24b032d9eab5a9caa370719e69e064"
SIDE = 24
COUNT = 96
PROFILES = (("g++", "-O2"), ("clang++", "-O3"))


def digest(blob: bytes) -> str:
    """Return the full SHA-256 of a serialized fixture or native source."""
    return hashlib.sha256(blob).hexdigest()


def load_oracle() -> list[dict[str, Any]]:
    """Load only the independently generated, pinned Godot masks."""
    raw = ORACLE.read_bytes()
    if digest(raw) != ORACLE_SHA256:
        raise ValueError("Godot stress fixture checksum changed")
    envelope = json.loads(raw)
    if (not isinstance(envelope, dict) or set(envelope) != {
            "schema", "seed", "generator", "godot_version", "side", "cases"}
            or type(envelope["schema"]) is not int or envelope["schema"] != 1
            or envelope["seed"] != 0x68048 or envelope["side"] != SIDE
            or envelope["generator"] != "tests/drawing_t068_quad_stress_oracle.gd"
            or not isinstance(envelope["godot_version"], str)
            or not envelope["godot_version"].startswith("4.8-beta2")
            or not isinstance(envelope["cases"], list)
            or len(envelope["cases"]) != COUNT):
        raise ValueError("Invalid Godot stress fixture envelope")
    for index, case in enumerate(envelope["cases"]):
        if (not isinstance(case, dict) or set(case) != {
                "id", "transform", "density", "polygon", "enabled", "allowed", "mask_base64"}
                or case["id"] != f"stress_{index:03d}"
                or not isinstance(case["transform"], list) or len(case["transform"]) != 6
                or not isinstance(case["polygon"], list)
                or type(case["enabled"]) is not bool
                or type(case["allowed"]) is not int):
            raise ValueError("Invalid Godot stress case")
        try:
            mask = base64.b64decode(case["mask_base64"], validate=True)
        except (TypeError, ValueError) as exc:
            raise ValueError("Invalid stress mask encoding") from exc
        if len(mask) != SIDE * SIDE or set(mask) - {0, 1} or mask.count(1) != case["allowed"]:
            raise ValueError("Invalid Godot stress mask")
    return envelope["cases"]


def build(compiler: str, optimization: str, directory: Path) -> Path:
    """Compile the detached ABI without modifying the repository or editor."""
    library = directory / f"quad_{compiler.replace('+', 'p')}_{optimization[1:]}.so"
    subprocess.run([compiler, "-std=c++17", optimization, "-fPIC", "-shared",
                    "-Wall", "-Wextra", "-Werror", str(SOURCE), "-o", str(library)],
                   capture_output=True, text=True, check=True, timeout=60)
    return library


def native_mask(native: NativeQuad, case: dict[str, Any]) -> bytes:
    """Exercise the raw ABI on a non-32px tile; reject invalid native output."""
    transform = (ctypes.c_double * 6)(*case["transform"])
    coordinates = [component for point in case["polygon"] for component in point]
    vertices = (ctypes.c_double * len(coordinates))(*coordinates)
    output = (ctypes.c_uint8 * (SIDE * SIDE))(*([0xA5] * (SIDE * SIDE)))
    returned = native.function(output, SIDE * SIDE, SIDE, transform,
                               ctypes.sizeof(transform), case["density"],
                               vertices if coordinates else None,
                               ctypes.sizeof(vertices), len(coordinates) // 2,
                               int(case["enabled"]))
    actual = bytes(output)
    if returned < 0 or set(actual) - {0, 1} or actual.count(1) != returned:
        raise ValueError("Native stress ABI rejected or corrupted a mask")
    return actual


def screen() -> dict[str, Any]:
    """Run two passes on two strict compiler profiles and keep all differences."""
    cases = load_oracle()
    profiles = []
    with tempfile.TemporaryDirectory(prefix="t068-quad-stress-") as temp:
        for compiler, optimization in PROFILES:
            native = NativeQuad(build(compiler, optimization, Path(temp)))
            runs = []
            for _ in range(2):
                rows = []
                for case in cases:
                    expected = base64.b64decode(case["mask_base64"], validate=True)
                    actual = native_mask(native, case)
                    rows.append({
                        "id": case["id"], "native_sha256": digest(actual),
                        "missing_indices": [i for i, (a, b) in enumerate(zip(expected, actual))
                                            if a == 1 and b == 0],
                        "extra_indices": [i for i, (a, b) in enumerate(zip(expected, actual))
                                          if a == 0 and b == 1],
                    })
                runs.append(rows)
            profiles.append({"compiler": compiler, "optimization": optimization,
                             "runs": runs})
    differences = [r for profile in profiles for r in profile["runs"][0]
                   if r["missing_indices"] or r["extra_indices"]]
    result = {
        "schema": 1, "ticket": "T-068", "godot_oracle_sha256": ORACLE_SHA256,
        "native_source_sha256": digest(SOURCE.read_bytes()),
        "summary": {"profiles": len(PROFILES), "runs_per_profile": 2,
                    "cases_per_run": COUNT, "comparisons": len(PROFILES) * 2 * COUNT,
                    "nonparity_profile_cases": len(differences),
                    "missing_pixels": sum(len(r["missing_indices"]) for r in differences),
                    "extra_pixels": sum(len(r["extra_indices"]) for r in differences)},
        "profiles": profiles,
        "limitations": ["Seeded finite convex scopes only; not arbitrary transforms, Windows, or native backend acceptance",
                        "Godot AtlasFill generated masks; detached C++ ABI, no GPU or app integration"],
    }
    validate_evidence(result)
    return result


def validate_evidence(record: Any) -> None:
    """Replay all masks from the pinned Godot oracle; fail on forged summaries."""
    cases = load_oracle()
    if (not isinstance(record, dict) or set(record) != {
            "schema", "ticket", "godot_oracle_sha256", "native_source_sha256",
            "summary", "profiles", "limitations"}
            or type(record["schema"]) is not int or record["schema"] != 1
            or record["ticket"] != "T-068"
            or record["godot_oracle_sha256"] != ORACLE_SHA256
            or record["native_source_sha256"] != digest(SOURCE.read_bytes())
            or not isinstance(record["limitations"], list)
            or not any("not arbitrary transforms" in x for x in record["limitations"]
                       if isinstance(x, str))
            or not isinstance(record["profiles"], list)
            or len(record["profiles"]) != len(PROFILES)):
        raise ValueError("Incomplete quad stress evidence")
    discrepancy_rows = []
    for (compiler, optimization), profile in zip(PROFILES, record["profiles"]):
        if (not isinstance(profile, dict) or set(profile) != {
                "compiler", "optimization", "runs"}
                or profile["compiler"] != compiler or profile["optimization"] != optimization
                or not isinstance(profile["runs"], list) or len(profile["runs"]) != 2):
            raise ValueError("Invalid compiler profile")
        signatures = []
        for rows in profile["runs"]:
            if not isinstance(rows, list) or len(rows) != COUNT:
                raise ValueError("Missing stress comparisons")
            signature = []
            for case, row in zip(cases, rows):
                if (not isinstance(row, dict) or set(row) != {
                        "id", "native_sha256", "missing_indices", "extra_indices"}
                        or row["id"] != case["id"]):
                    raise ValueError("Stress case order or schema altered")
                expected = base64.b64decode(case["mask_base64"], validate=True)
                missing, extra = row["missing_indices"], row["extra_indices"]
                for indices, original_value in ((missing, 1), (extra, 0)):
                    if (not isinstance(indices, list)
                            or any(type(i) is not int or i < 0 or i >= SIDE * SIDE
                                   for i in indices)
                            or indices != sorted(set(indices))
                            or any(expected[i] != original_value for i in indices)):
                        raise ValueError("Forged stress mismatch indices")
                actual = bytearray(expected)
                for i in missing:
                    actual[i] = 0
                for i in extra:
                    actual[i] = 1
                if digest(actual) != row["native_sha256"]:
                    raise ValueError("Native stress mask digest mismatch")
                signature.append((tuple(missing), tuple(extra), row["native_sha256"]))
            signatures.append(signature)
        if signatures[0] != signatures[1]:
            raise ValueError("Native stress passes differ")
        discrepancy_rows.extend(r for r in profile["runs"][0]
                                if r["missing_indices"] or r["extra_indices"])
    summary = {"profiles": len(PROFILES), "runs_per_profile": 2,
               "cases_per_run": COUNT, "comparisons": len(PROFILES) * 2 * COUNT,
               "nonparity_profile_cases": len(discrepancy_rows),
               "missing_pixels": sum(len(r["missing_indices"]) for r in discrepancy_rows),
               "extra_pixels": sum(len(r["extra_indices"]) for r in discrepancy_rows)}
    if record["summary"] != summary:
        raise ValueError("Forged stress summary")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evidence = screen()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print("T068_QUAD_STRESS_PASSED:", evidence["summary"])


if __name__ == "__main__":
    main()
