#!/usr/bin/env python3
"""T-068 seeded Godot/standalone-C++ selection boundary differential screen.

Never loaded by Drawing or Atlas. The Godot-authored bytes are authoritative;
reported mismatches are findings, not successful mask parity.
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

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/benchmarks/t068_quad_scope_kernel.cpp"
ORACLE = ROOT / "tools/benchmarks/t068_quad_differential_oracle.json"
ORACLE_SHA256 = "76376a6c76c7e5e39e67550c27ad4a3980dee44434edbaa2ac9f6dfec5322ac5"
SIDE = 32
COUNT = 48


def _digest(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def load_oracle() -> list[dict[str, Any]]:
    """Load a fixed independent Godot oracle with strict mask validation."""
    raw = ORACLE.read_bytes()
    if _digest(raw) != ORACLE_SHA256:
        raise ValueError("Godot differential oracle checksum changed")
    payload = json.loads(raw)
    if (set(payload) != {"schema", "generator", "godot_version", "side", "cases"}
            or type(payload["schema"]) is not int or payload["schema"] != 1
            or payload["side"] != SIDE
            or payload["generator"] != "tests/drawing_t068_quad_differential_oracle.gd"
            or not payload["godot_version"].startswith("4.8-beta2")
            or not isinstance(payload["cases"], list) or len(payload["cases"]) != COUNT):
        raise ValueError("Invalid Godot differential oracle metadata")
    for index, case in enumerate(payload["cases"]):
        if (not isinstance(case, dict) or set(case) != {
                "id", "transform", "density", "polygon", "enabled", "allowed", "mask_base64"}
                or case["id"] != f"seed_{index:02d}"
                or type(case["allowed"]) is not int
                or type(case["enabled"]) is not bool):
            raise ValueError("Invalid Godot differential case")
        try:
            mask = base64.b64decode(case["mask_base64"], validate=True)
        except (ValueError, TypeError) as exc:
            raise ValueError("Invalid Godot differential mask base64") from exc
        if len(mask) != SIDE * SIDE or set(mask) - {0, 1} or mask.count(1) != case["allowed"]:
            raise ValueError("Invalid Godot differential mask")
    return payload["cases"]


class NativeQuad:
    """Temporary scalar C ABI wrapper, not a Godot extension or application module."""

    def __init__(self, path: Path):
        function = ctypes.CDLL(str(path)).t068_quad_scope_mask
        function.restype = ctypes.c_int32
        function.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                             ctypes.c_void_p, ctypes.c_uint64, ctypes.c_double,
                             ctypes.c_void_p, ctypes.c_uint64, ctypes.c_int32,
                             ctypes.c_int32)
        self.function = function

    def mask(self, case: dict[str, Any]) -> bytes:
        coefficients = (ctypes.c_double * 6)(*case["transform"])
        vertex_values = [v for point in case["polygon"] for v in point]
        polygon = (ctypes.c_double * len(vertex_values))(*vertex_values)
        output = (ctypes.c_uint8 * (SIDE * SIDE))()
        selected = self.function(output, SIDE * SIDE, SIDE,
                                 coefficients, ctypes.sizeof(coefficients),
                                 case["density"], polygon if vertex_values else None,
                                 ctypes.sizeof(polygon), len(vertex_values) // 2,
                                 int(case["enabled"]))
        mask = bytes(output)
        if selected < 0 or set(mask) - {0, 1} or mask.count(1) != selected:
            raise ValueError("Native quad ABI rejected or returned an invalid mask")
        return mask


def build(destination: Path) -> Path:
    """Compile only the dependency-free detached C++ kernel."""
    library = destination / "t068_quad_differential.so"
    subprocess.run(["g++", "-std=c++17", "-O2", "-fPIC", "-shared",
                    "-Wall", "-Wextra", "-Werror", str(SOURCE), "-o", str(library)],
                   check=True, timeout=45)
    return library


def screen(library: Path) -> dict[str, Any]:
    cases = load_oracle()
    native = NativeQuad(library)
    runs = []
    for _ in range(2):
        rows = []
        for case in cases:
            expected = base64.b64decode(case["mask_base64"], validate=True)
            actual = native.mask(case)
            missing = [i for i, (godot, cpp) in enumerate(zip(expected, actual))
                       if godot == 1 and cpp == 0]
            extra = [i for i, (godot, cpp) in enumerate(zip(expected, actual))
                     if godot == 0 and cpp == 1]
            rows.append({"id": case["id"], "native_allowed": actual.count(1),
                         "native_sha256": _digest(actual),
                         "missing_indices": missing, "extra_indices": extra})
        runs.append(rows)
    summary = {"runs": 2, "cases_per_run": COUNT,
               "nonparity_cases": sum(bool(r["missing_indices"] or r["extra_indices"])
                                      for r in runs[0]),
               "missing_pixels_per_run": sum(len(r["missing_indices"]) for r in runs[0]),
               "extra_pixels_per_run": sum(len(r["extra_indices"]) for r in runs[0])}
    result = {"schema": 1, "ticket": "T-068",
              "godot_oracle_sha256": ORACLE_SHA256,
              "native_source_sha256": _digest(SOURCE.read_bytes()),
              "summary": summary, "runs": runs,
              "limitations": [
                  "Seeded near-boundary diagnostic, not native selection acceptance",
                  "Uses Godot-generated float32 Vector2 transform and polygon coordinates; native geometry uses double intermediates",
                  "Detached C++ CPU mask only, not GDExtension document publication, GPU, or physical latency",
              ]}
    validate_evidence(result)
    return result


def validate_evidence(record: Any) -> None:
    """Reconstruct native masks and statistics from independently pinned Godot bytes."""
    cases = load_oracle()
    if (not isinstance(record, dict) or set(record) != {
            "schema", "ticket", "godot_oracle_sha256", "native_source_sha256",
            "summary", "runs", "limitations"}
            or type(record["schema"]) is not int or record["schema"] != 1
            or record["ticket"] != "T-068"
            or record["godot_oracle_sha256"] != ORACLE_SHA256
            or record["native_source_sha256"] != _digest(SOURCE.read_bytes())
            or not isinstance(record["runs"], list) or len(record["runs"]) != 2
            or not isinstance(record["limitations"], list)
            or not any("not native selection acceptance" in value
                       for value in record["limitations"] if isinstance(value, str))):
        raise ValueError("Incomplete differential evidence envelope")
    signatures = []
    for rows in record["runs"]:
        if not isinstance(rows, list) or len(rows) != COUNT:
            raise ValueError("Missing differential comparisons")
        signature = []
        for case, row in zip(cases, rows):
            if not isinstance(row, dict) or set(row) != {
                    "id", "native_allowed", "native_sha256", "missing_indices", "extra_indices"}:
                raise ValueError("Malformed native differential comparison")
            missing, extra = row["missing_indices"], row["extra_indices"]
            if row["id"] != case["id"]:
                raise ValueError("Differential cases out of order")
            original = base64.b64decode(case["mask_base64"], validate=True)
            if any(not isinstance(group, list) or any(
                    type(i) is not int or i < 0 or i >= SIDE * SIDE for i in group)
                    or group != sorted(set(group)) for group in (missing, extra)):
                raise ValueError("Invalid mismatch index list")
            if any(original[i] != 1 for i in missing) or any(original[i] != 0 for i in extra):
                raise ValueError("Mismatch indices do not describe the Godot mask")
            actual = bytearray(original)
            for index in missing:
                actual[index] = 0
            for index in extra:
                actual[index] = 1
            if (type(row["native_allowed"]) is not int
                    or row["native_allowed"] != actual.count(1)
                    or row["native_sha256"] != _digest(actual)):
                raise ValueError("Native mask cannot be reconstructed")
            signature.append((tuple(missing), tuple(extra), row["native_sha256"]))
        signatures.append(signature)
    if signatures[0] != signatures[1]:
        raise ValueError("Differential native runs disagree")
    rows = record["runs"][0]
    expected = {"runs": 2, "cases_per_run": COUNT,
                "nonparity_cases": sum(bool(r["missing_indices"] or r["extra_indices"])
                                       for r in rows),
                "missing_pixels_per_run": sum(len(r["missing_indices"]) for r in rows),
                "extra_pixels_per_run": sum(len(r["extra_indices"]) for r in rows)}
    if record["summary"] != expected:
        raise ValueError("Differential summary does not match raw comparisons")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="t068-quad-differential-") as temp:
        evidence = screen(build(Path(temp)))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print("T068_QUAD_DIFFERENTIAL_PASSED: %s" % evidence["summary"])


if __name__ == "__main__":
    main()
