#!/usr/bin/env python3
"""T-105: Windows/MSVC detached ABI parity and strict-FP reproduction.

Runs ONLY on a real Windows x64 host with Visual Studio's cl.exe on PATH.
Not a cross-compile simulation or a Godot export / physical GPU test.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from typing import Any

import t068_quad_compiler_matrix as quad_matrix
import t068_quad_differential as quad
import t068_matched_brush as matched
from t068_scalar_hard_brush import SOURCE as SCALAR_SOURCE, ScalarBrush

ROOT = Path(__file__).resolve().parents[2]
QUAD_SOURCE = ROOT / "tools/benchmarks/t068_quad_scope_kernel.cpp"
SOURCES = (SCALAR_SOURCE, QUAD_SOURCE)
EXPECTED_SOURCE_SHA256 = {
    SCALAR_SOURCE: "48e731354c4bec55f046f11324650e41f31c94cc528eebb31fa94e4e5643a7bf",
    QUAD_SOURCE: "95094bfb518dc1b7289e53e9ef767bbf6705166a444a734b861dbe527ce64466",
}


def digest(path: Path) -> str:
    """Return a SHA-256 fingerprint for a source file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def portable_source(source: Path) -> str:
    """Generate an MSVC guard/export shim from an unchanged pinned T-068 source.

    Historical Linux source SHA-256 fixtures must remain immutable. This source
    adapter is strictly for detached Windows test compilation, not application
    code or a new shipping backend.
    """
    if source not in EXPECTED_SOURCE_SHA256 or digest(source) != EXPECTED_SOURCE_SHA256[source]:
        raise ValueError("Detached T-068 native source bytes differ from pinned cross-OS oracle")
    text = source.read_text(encoding="utf-8")
    guard = ('#if defined(_M_FP_FAST)\n'
             '#error "T-105 Windows ABI requires strict floating-point semantics"\n'
             '#endif\n')
    if source == QUAD_SOURCE:
        signature = 'extern "C" int32_t t068_quad_scope_mask('
        if text.count(signature) != 1:
            raise ValueError("Pinned quad export signature changed")
        text = text.replace(signature,
                            'extern "C" __declspec(dllexport) int32_t t068_quad_scope_mask(')
    elif source != SCALAR_SOURCE:
        raise ValueError("Only pinned T-068 candidates supported")
    return guard + text


def compile_msvc(source: Path, name: str, directory: Path, *extra: str) -> Path:
    """Compile with the installed MSVC toolchain, failing on any diagnostic error."""
    portable = directory / f"{name}-portable.cpp"
    portable.write_text(portable_source(source), encoding="utf-8")
    destination = directory / f"{name}.dll"
    command = ["cl", "/nologo", "/std:c++17", "/EHsc", "/W4", "/WX",
               "/O2", "/fp:strict", "/LD", *extra, str(portable),
               "/link", f"/OUT:{destination}"]
    result = subprocess.run(command, cwd=directory, text=True, capture_output=True,
                            timeout=120, check=False)
    if result.returncode or not destination.is_file():
        raise RuntimeError(f"MSVC {name} failed ({result.returncode}): {result.stdout}\n{result.stderr}")
    return destination


def reject_fast_math(source: Path, name: str, directory: Path) -> None:
    """Prove /fp:fast itself cannot build the sensitive detached source."""
    portable = directory / f"{name}-unsafe.cpp"
    portable.write_text(portable_source(source), encoding="utf-8")
    destination = directory / f"{name}-unsafe.dll"
    # The final /fp option wins; place /fp:fast last, as in a compromised build.
    command = ["cl", "/nologo", "/std:c++17", "/EHsc", "/O2", "/LD",
               "/fp:fast", str(portable), "/link", f"/OUT:{destination}"]
    result = subprocess.run(command, cwd=directory, text=True, capture_output=True,
                            timeout=120, check=False)
    if (result.returncode == 0 or destination.exists() or
            "requires strict floating-point semantics" not in
            (result.stdout + result.stderr)):
        raise AssertionError(f"Unsafe MSVC {name} /fp:fast compilation was not rejected by source guard")


def percentiles(values: list[float]) -> dict[str, float]:
    """Nearest-rank CPU-time summary over nonempty measured cases."""
    if not values or any(not math.isfinite(v) or v <= 0 for v in values):
        raise ValueError("Invalid CPU timings")
    ordered = sorted(values)
    return {"p50": ordered[math.ceil(len(values) * 0.50) - 1],
            "p95": ordered[math.ceil(len(values) * 0.95) - 1],
            "max": ordered[-1]}


def run() -> dict[str, Any]:
    """Build and execute the exact T-068 signed-mask and RGBA8 source oracles."""
    if sys.platform != "win32" or platform.machine().lower() not in ("amd64", "x86_64"):
        raise RuntimeError("Real Windows x64 MSVC host required")
    version = subprocess.run(["cl"], text=True, capture_output=True,
                             timeout=20, check=False)
    banner = (version.stdout + version.stderr).splitlines()
    if not any("Microsoft (R) C/C++ Optimizing Compiler" in line for line in banner):
        raise RuntimeError("cl.exe is not Microsoft Visual C++")
    with tempfile.TemporaryDirectory(prefix="t105-msvc-") as temp:
        directory = Path(temp)
        quad_lib = compile_msvc(QUAD_SOURCE, "quad", directory)
        scalar_lib = compile_msvc(SCALAR_SOURCE, "scalar", directory)
        reject_fast_math(QUAD_SOURCE, "quad", directory)
        reject_fast_math(SCALAR_SOURCE, "scalar", directory)
        native_quad = quad.NativeQuad(quad_lib)
        expected = quad_matrix.expected_masks()
        quad_cases = quad.load_oracle()
        if len(quad_cases) != 48:
            raise ValueError("Missing pinned signed-mask fixtures")
        for _ in range(2):
            if [native_quad.mask(case) for case in quad_cases] != expected:
                raise AssertionError("MSVC signed/rotated mask parity differs from Godot")
        rejections = quad_matrix.raw_rejections(native_quad)
        scalar = ScalarBrush(scalar_lib)
        cases = matched.workloads()
        if len(cases) != 10:
            raise ValueError("Missing pinned RGBA8 workloads")
        rows = []
        for case in cases:
            prepared = matched.Prepared(case, scalar, SimpleNamespace(function=None))
            samples = []
            for _ in range(3):
                start = time.perf_counter_ns()
                status = prepared.call("scalar")
                elapsed_us = (time.perf_counter_ns() - start) / 1000.0
                parity = prepared.check("scalar", status)
                if parity["missing"] or parity["extra"] or parity["pixel_mismatch"]:
                    raise AssertionError(f"MSVC scalar canonical output differs: {case.key}")
                samples.append(elapsed_us)
            if bytes(prepared.src) != case.source or bytes(prepared.sel) != case.selected:
                raise AssertionError("MSVC native mutated immutable source/selection")
            rows.append({"case": case.key, "side": case.side,
                         "source_sha256": hashlib.sha256(case.source).hexdigest(),
                         "output_sha256": hashlib.sha256(case.expected).hexdigest(),
                         "cpu_us": percentiles(samples)})
    return {"schema": 1, "ticket": "T-105", "platform": "windows-x86_64-msvc",
            "compiler": next(line.strip() for line in banner if "Microsoft (R) C/C++" in line),
            "source_sha256": {str(p.relative_to(ROOT)): digest(p) for p in SOURCES},
            "quad_cases_checked": len(quad_cases) * 2,
            "atomic_rejection_cases": len(rejections),
            "unsafe_fp_builds_rejected": 2, "rgba8_cases": rows,
            "limit": "Detached MSVC ABI/CPU parity; not exported app, VRAM or physical input-to-display"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = run()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("T105_MSVC_PARITY_PASSED: 96 signed masks, 7 atomic failures, "
          "2 rejected unsafe builds, 10 canonical RGBA8 workloads")


if __name__ == "__main__":
    main()
