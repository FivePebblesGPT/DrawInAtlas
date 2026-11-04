#!/usr/bin/env python3
"""Deterministic ASan+UBSan check of T-068's detached native brush/scope ABIs.

The executable invokes the real C++ entrypoints, not ctypes. This avoids
loading an ASan runtime into a nonsanitized Python process. It is correctness
and failure-atomicity evidence, not a production/native timing measurement.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SOURCES = (
    "tools/benchmarks/t068_native_sanitizer_smoke.cpp",
    "tools/benchmarks/t068_quad_scope_kernel.cpp",
    "tools/benchmarks/t068_scalar_hard_brush.cpp",
)
PROFILES = ("g++", "clang++")
FLAGS = ("-std=c++17", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
         "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
         "-fno-sanitize-recover=all")
EXPECTED = {"cases": 256, "checks": 54378, "rejected": 17,
            "covered": 2070, "changed": 2057, "digest": "93bb007e99ff4dbd"}
RESULT_PATTERN = re.compile(r"^T068_SANITIZER_OK cases=(\d+) checks=(\d+) "
                            r"rejected=(\d+) covered=(\d+) changed=(\d+) "
                            r"digest=([0-9a-f]{16})\n$")


def sha(path: Path) -> str:
    """Hash the exact tracked source bytes, not the compilation result."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def result(stdout: str) -> dict[str, int | str]:
    """Require one complete success line with the independently pinned values."""
    matched = RESULT_PATTERN.fullmatch(stdout)
    if not matched:
        raise ValueError("Missing or malformed native sanitizer success record")
    values: dict[str, int | str] = dict(zip(EXPECTED, (*map(int, matched.groups()[:5]),
                                                      matched.group(6))))
    if values != EXPECTED:
        raise ValueError("Sanitizer smoke parity/counter digest changed")
    return values


def validate(payload: Any) -> None:
    """Fail closed on changed sources, missing profiles/runs or forged results."""
    if (not isinstance(payload, dict) or set(payload) != {
            "schema", "ticket", "sources", "compiler_flags", "profiles", "limitations"}
            or type(payload["schema"]) is not int or payload["schema"] != 1
            or payload["ticket"] != "T-068"
            or payload["sources"] != {p: sha(ROOT / p) for p in SOURCES}
            or payload["compiler_flags"] != list(FLAGS)
            or not isinstance(payload["profiles"], list)
            or len(payload["profiles"]) != len(PROFILES)
            or payload["limitations"] != [
                "Linux x86-64 GCC/Clang ASan+UBSan only; no Windows, ARM or Godot app integration",
                "Small seeded fixtures and malformed buffers, not proof against all native memory faults",
                "No GPU, input-to-present latency, production native backend or release acceptance",
            ]):
        raise ValueError("Incomplete native sanitizer record")
    for compiler, profile in zip(PROFILES, payload["profiles"]):
        if (not isinstance(profile, dict)
                or set(profile) != {"compiler", "version", "runs"}
                or profile["compiler"] != compiler
                or not isinstance(profile["version"], str)
                or not profile["version"].strip()
                or not isinstance(profile["runs"], list)
                or len(profile["runs"]) != 2):
            raise ValueError("Native sanitizer compiler profile altered")
        for run in profile["runs"]:
            if not isinstance(run, dict) or set(run) != set(EXPECTED) or run != EXPECTED:
                raise ValueError("Native sanitizer results altered or incomplete")


def screen() -> dict[str, Any]:
    """Build both independent sanitized executables and run each twice."""
    profiles = []
    env = {**os.environ,
           "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1",
           "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"}
    with tempfile.TemporaryDirectory(prefix="t068-native-sanitizer-") as tmp:
        for compiler in PROFILES:
            binary = Path(tmp) / ("sanitizer-" + compiler.replace("+", "p"))
            if shutil.which(compiler) is None:
                raise RuntimeError(f"Required sanitizer compiler missing: {compiler}")
            version = subprocess.run([compiler, "--version"], check=True,
                capture_output=True, text=True, timeout=15).stdout.splitlines()[0]
            subprocess.run([compiler, *FLAGS, *(str(ROOT / p) for p in SOURCES),
                            "-o", str(binary)], capture_output=True, text=True,
                           check=True, timeout=90)
            runs = []
            for _ in range(2):
                completed = subprocess.run([str(binary)], capture_output=True,
                                           text=True, env=env, timeout=60, check=False)
                if completed.returncode != 0 or completed.stderr:
                    raise RuntimeError(f"{compiler} sanitizer failed (exit {completed.returncode}):\n"
                                       + completed.stderr + completed.stdout)
                runs.append(result(completed.stdout))
            profiles.append({"compiler": compiler, "version": version, "runs": runs})
    evidence = {
        "schema": 1, "ticket": "T-068",
        "sources": {path: sha(ROOT / path) for path in SOURCES},
        "compiler_flags": list(FLAGS), "profiles": profiles,
        "limitations": [
            "Linux x86-64 GCC/Clang ASan+UBSan only; no Windows, ARM or Godot app integration",
            "Small seeded fixtures and malformed buffers, not proof against all native memory faults",
            "No GPU, input-to-present latency, production native backend or release acceptance",
        ],
    }
    validate(evidence)
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    record = screen()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print("T068_NATIVE_SANITIZER_PASSED: 4 runs, 1024 deterministic cases, "
          "68 atomic rejections, 4 matching reconstruction digests")


if __name__ == "__main__":
    main()
