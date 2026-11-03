"""Compile and test T-068's isolated Godot-to-C++ raster boundary.

The shared library and .gdextension descriptor exist only in a temporary
Godot project. Nothing is loaded by the standalone Drawing or Atlas projects.
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

ROOT = Path(__file__).resolve().parents[3]
BRIDGE = Path(__file__).resolve().parent
EXPECTED_VERSION = "4.8.beta2.official.cafc17a19"
PASS_RE = re.compile(r"^T068_BRIDGE_PASSED: (\d+) checks$", re.MULTILINE)
TIMING_RE = re.compile(r"^T068_BRIDGE_TIMING: (.+)$", re.MULTILINE)


def checked_run(argv: list[str], *, cwd: Path, timeout: int) -> str:
    """Run one bounded command and reject Godot diagnostics and subprocess errors."""
    environment = os.environ.copy()
    environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    result = subprocess.run(
        argv, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False,
        env=environment,
    )
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0 or re.search(r"(?m)^(?:ERROR:|SCRIPT ERROR:|T068_BRIDGE_FAIL:)", combined):
        raise RuntimeError(f"Command failed ({result.returncode}): {argv}\n{combined[-6000:]}")
    return combined


def execute(godot: str, *, runs: int = 1) -> dict[str, Any]:
    """Build against Godot's own header and verify actual Godot Variant calls."""
    version = checked_run([godot, "--version"], cwd=ROOT, timeout=15).strip()
    if EXPECTED_VERSION not in version:
        raise RuntimeError(f"Expected pinned Godot {EXPECTED_VERSION}; got {version!r}")

    with tempfile.TemporaryDirectory(prefix="t068-gdextension-") as directory:
        temporary = Path(directory)
        header_dir = temporary / "header"
        header_dir.mkdir()
        checked_run([godot, "--headless", "--dump-gdextension-interface"], cwd=header_dir, timeout=45)
        header = header_dir / "gdextension_interface.h"
        if not header.is_file():
            raise RuntimeError("Pinned Godot did not generate gdextension_interface.h")
        header_sha = hashlib.sha256(header.read_bytes()).hexdigest()

        project = temporary / "test-project"
        native = project / "native"
        native.mkdir(parents=True)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="T068 Isolated Bridge"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8",
        )
        descriptor = native / "t068.gdextension"
        descriptor_text = (
            '[configuration]\nentry_symbol="t068_raster_bridge_init"\n'
            'compatibility_minimum="4.7"\nreloadable=false\n\n'
            '[libraries]\nlinux.debug.x86_64="res://native/libt068_raster.so"\n'
            'linux.release.x86_64="res://native/libt068_raster.so"\n'
        )
        library = native / "libt068_raster.so"
        compiler = shutil.which("g++")
        if compiler is None:
            raise RuntimeError("This optional Linux benchmark requires g++")
        checked_run([
            compiler, "-std=c++17", "-O2", "-fPIC", "-shared", "-Wall", "-Wextra", "-Werror",
            "-I", str(header_dir), str(BRIDGE / "t068_bridge.cpp"),
            str(ROOT / "tools/benchmarks/t068_raster_kernel.cpp"),
            "-o", str(library),
        ], cwd=ROOT, timeout=90)
        # Bootstrap a fresh Godot project before registering optional classes.
        # Godot 4.8 beta 2 can abort on the very first editor scan with a
        # freshly compiled GDExtension; the existing cache avoids that path.
        checked_run([godot, "--headless", "--editor", "--path", str(project),
                     "--import"], cwd=project, timeout=120)
        descriptor.write_text(descriptor_text, encoding="utf-8")
        # An explicit runtime load avoids an editor startup crash in Godot 4.8b2
        # when scanning a hand-authored GDExtension descriptor.
        # Keep the standalone stress script outside the editor initial scan.
        shutil.copyfile(BRIDGE / "t068_bridge_smoke.gd", project / "test.gd")
        observations: list[dict[str, Any]] = []
        for _ in range(runs):
            output = checked_run([godot, "--headless", "--path", str(project),
                                  "--script", "res://test.gd"], cwd=project, timeout=90)
            match = PASS_RE.search(output)
            timing = TIMING_RE.search(output)
            if match is None or timing is None:
                raise RuntimeError(f"Missing Godot correctness/timing marker:\n{output[-4000:]}")
            count = int(match.group(1))
            if count < 442:
                raise RuntimeError(f"Only {count} GDExtension checks ran; expected at least 442")
            observations.append({"checks": count, "bridge_latency_us": json.loads(timing.group(1))})
        return {
            "ticket": "T-068", "mode": "optional, isolated Linux GDExtension (not production)",
            "godot_version": version, "generated_header_sha256": header_sha,
            "test_method": "Godot GDScript calls against C++ length-checked raster batch",
            "measurements": observations,
            "limitations": [
                "No source/document publication or production UI is exercised",
                "Timings include Godot PackedByteArray copies and are not input-to-visible latency",
                "Software runner only; no physical Windows/Linux hardware or GPU timings",
                "Temporary binary is not bundled in the repository or loaded at normal startup",
            ],
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.8 beta 2 executable")
    parser.add_argument("--runs", type=int, default=1, choices=[1, 2, 3])
    parser.add_argument("--output", type=Path, help="Write raw JSON evidence outside repository")
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if executable is None:
        parser.error(f"Godot executable not found: {args.godot}")
    evidence = execute(executable, runs=args.runs)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    counts = ", ".join(str(item["checks"]) for item in evidence["measurements"])
    print(f"T068_GDEXTENSION_INTEGRATION_PASSED: {counts} checks per run")
    print("Timings are diagnostic only; no production backend enabled.")


if __name__ == "__main__":
    main()
