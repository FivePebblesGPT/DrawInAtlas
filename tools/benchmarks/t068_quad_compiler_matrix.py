#!/usr/bin/env python3
"""Cross-compiler ABI safety/parity regression for detached T-068 quad masks.

This test-only CPU matrix is not evidence of Windows runtime compatibility,
physical display latency, or a production-ready native Drawing backend.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import t068_quad_differential as quad

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools/benchmarks/t068_quad_scope_kernel.cpp"
PROFILES = (("g++", "-O0"), ("g++", "-O2"), ("g++", "-O3"),
            ("clang++", "-O0"), ("clang++", "-O2"), ("clang++", "-O3"))
REJECTIONS = ("nan_transform", "inf_transform", "nan_density", "inf_density",
              "nan_polygon", "singular_transform", "short_output")
SENTINEL = bytes([0xA5] * 4)


def sha(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def expected_masks() -> list[bytes]:
    return [base64.b64decode(case["mask_base64"], validate=True)
            for case in quad.load_oracle()]


def build(compiler: str, optimization: str, dest: Path) -> Path:
    path = dest / (compiler.replace("+", "p") + optimization.replace("-", "") + ".so")
    subprocess.run([compiler, "-std=c++17", optimization, "-fPIC", "-shared",
                    "-Wall", "-Wextra", "-Werror", str(SOURCE), "-o", str(path)],
                   check=True, timeout=45, capture_output=True, text=True)
    return path


def raw_rejections(native: quad.NativeQuad) -> dict[str, int]:
    results: dict[str, int] = {}
    for kind in REJECTIONS:
        coefficients = (ctypes.c_double * 6)(1, 0, 0, 1, 0, 0)
        polygon = (ctypes.c_double * 8)(0, 0, 2, 0, 2, 2, 0, 2)
        density = 1.0
        output_bytes = 4
        if kind == "nan_transform":
            coefficients[0] = math.nan
        elif kind == "inf_transform":
            coefficients[0] = math.inf
        elif kind == "nan_density":
            density = math.nan
        elif kind == "inf_density":
            density = math.inf
        elif kind == "nan_polygon":
            polygon[0] = math.nan
        elif kind == "singular_transform":
            coefficients[3] = 0
        elif kind == "short_output":
            output_bytes = 3
        output = (ctypes.c_uint8 * 4).from_buffer_copy(SENTINEL)
        code = native.function(output, output_bytes, 2, coefficients, 48,
                               density, polygon, 64, 4, 1)
        if code >= 0 or bytes(output) != SENTINEL:
            raise ValueError(f"{kind}: invalid ABI call was not rejected atomically")
        results[kind] = code
    return results


def strict_math_guard(compiler: str, dest: Path) -> None:
    """Fast-math builds must fail specifically on the native safety guard."""
    flags = ["-Ofast"] if compiler == "g++" else ["-O3", "-ffast-math"]
    path = dest / (compiler.replace("+", "p") + "-unsafe.so")
    proc = subprocess.run([compiler, "-std=c++17", *flags, "-fPIC", "-shared",
                           str(SOURCE), "-o", str(path)], capture_output=True,
                          text=True, timeout=45, check=False)
    if (proc.returncode == 0 or path.exists()
            or "T-068 quad scope requires strict floating-point semantics" not in proc.stderr):
        raise ValueError(f"{compiler} fast-math guard missing or not responsible for rejection")


def screen() -> dict[str, Any]:
    masks = expected_masks()
    rows = []
    with tempfile.TemporaryDirectory(prefix="t068-quad-compiler-") as temporary:
        dest = Path(temporary)
        for compiler, optimization in PROFILES:
            if shutil.which(compiler) is None:
                raise ValueError(f"Required native compiler missing: {compiler}")
            version = subprocess.run([compiler, "--version"], check=True,
                                     capture_output=True, text=True, timeout=15).stdout.splitlines()[0]
            library = build(compiler, optimization, dest)
            native = quad.NativeQuad(library)
            runs = []
            for _ in range(2):
                results = [native.mask(case) for case in quad.load_oracle()]
                if any(actual != expected for actual, expected in zip(results, masks)):
                    raise ValueError(f"{compiler} {optimization}: canonical selection parity failed")
                runs.append([sha(mask) for mask in results])
            rejected = raw_rejections(native)
            rows.append({"compiler": compiler, "optimization": optimization,
                         "version": version, "runs": runs, "rejections": rejected})
        for compiler in ("g++", "clang++"):
            strict_math_guard(compiler, dest)
    evidence = {"schema": 1, "ticket": "T-068", "quad_source_sha256": sha(SOURCE.read_bytes()),
                "godot_oracle_sha256": quad.ORACLE_SHA256,
                "profiles": rows, "unsafe_builds_rejected": ["g++", "clang++"],
                "limitations": [
                    "Six Linux compiler/optimization builds, not Windows or ARM compatibility",
                    "48 pinned 32x32 Godot oracle cases, not arbitrary polygons or all float modes",
                    "Detached C++ CPU kernel, not a production or physical display benchmark",
                ]}
    validate(evidence)
    return evidence


def validate(payload: Any) -> None:
    """Fail closed on source drift, profile omission, altered hashes or guards."""
    if (not isinstance(payload, dict) or set(payload) != {
            "schema", "ticket", "quad_source_sha256", "godot_oracle_sha256",
            "profiles", "unsafe_builds_rejected", "limitations"}
            or type(payload["schema"]) is not int or payload["schema"] != 1
            or payload["ticket"] != "T-068"
            or payload["quad_source_sha256"] != sha(SOURCE.read_bytes())
            or payload["godot_oracle_sha256"] != quad.ORACLE_SHA256
            or payload["unsafe_builds_rejected"] != ["g++", "clang++"]
            or not isinstance(payload["limitations"], list)
            or len(payload["limitations"]) != 3
            or not isinstance(payload["profiles"], list)
            or len(payload["profiles"]) != len(PROFILES)):
        raise ValueError("Incomplete T-068 compiler matrix envelope")
    expected = [sha(mask) for mask in expected_masks()]
    for profile, (compiler, optimization) in zip(payload["profiles"], PROFILES):
        if (not isinstance(profile, dict)
                or set(profile) != {"compiler", "optimization", "version", "runs", "rejections"}
                or profile["compiler"] != compiler or profile["optimization"] != optimization
                or not isinstance(profile["version"], str) or not profile["version"].strip()
                or not isinstance(profile["runs"], list) or len(profile["runs"]) != 2
                or profile["runs"] != [expected, expected]
                or not isinstance(profile["rejections"], dict)
                or list(profile["rejections"]) != list(REJECTIONS)
                or any(type(code) is not int or code >= 0
                       for code in profile["rejections"].values())):
            raise ValueError(f"Compiler parity/ABI evidence invalid: {compiler} {optimization}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    record = screen()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print("T068_QUAD_COMPILER_MATRIX_PASSED: 6 strict C++ builds, 576 exact mask checks, "
          "42 atomic rejection checks, 2 unsafe builds rejected")


if __name__ == "__main__":
    main()
