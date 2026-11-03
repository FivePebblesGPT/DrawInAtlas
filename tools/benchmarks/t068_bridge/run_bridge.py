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
REVISION_RE = re.compile(r"^T068_REVISION_PASSED: (\d+) checks$", re.MULTILINE)
DOCUMENT_RE = re.compile(r"^T068_DOCUMENT_PASSED: (\d+) checks$", re.MULTILINE)
BATCH_RE = re.compile(r"^T068_BATCH_PASSED: (\d+) checks$", re.MULTILINE)
SPARSE_RE = re.compile(r"^T068_SPARSE_PASSED: (\d+) checks$", re.MULTILINE)
SPARSE_TIMING_RE = re.compile(r"^T068_SPARSE_TIMING: (.+)$", re.MULTILINE)
CANONICAL_SCRIPTS = (
    "document", "edit_session", "signed_tiles", "layer_node", "raster_tile",
    "result", "delta", "dirty_region", "selection", "history_context",
    "text_element", "text_raster",
)


def checked_run(argv: list[str], *, cwd: Path, timeout: int) -> str:
    """Run one bounded command and reject Godot diagnostics and subprocess errors."""
    environment = os.environ.copy()
    environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    result = subprocess.run(
        argv, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False,
        env=environment,
    )
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0 or re.search(r"(?m)^(?:ERROR:|SCRIPT ERROR:|T068_BRIDGE_FAIL:|T068_REVISION_FAIL:|T068_REVISION_FAILED:|T068_DOCUMENT_FAIL:|T068_DOCUMENT_FAILED:|T068_BATCH_FAIL:|T068_BATCH_FAILED:|T068_SPARSE_FAIL:|T068_SPARSE_FAILED:)", combined):
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
        # Install only the canonical Drawing document/transaction dependency set;
        # the test exercises real production scripts, not a parallel model.
        drawing = project / "addons" / "drawing"
        drawing.mkdir(parents=True)
        for script in CANONICAL_SCRIPTS:
            shutil.copyfile(ROOT / "addons" / "drawing" / (script + ".gd"),
                            drawing / (script + ".gd"))
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
        shutil.copyfile(BRIDGE / "t068_revision_adapter.gd", project / "adapter.gd")
        shutil.copyfile(BRIDGE / "t068_revision_smoke.gd", project / "revision_test.gd")
        shutil.copyfile(BRIDGE / "t068_document_adapter.gd", project / "document_adapter.gd")
        shutil.copyfile(BRIDGE / "t068_document_smoke.gd", project / "document_test.gd")
        shutil.copyfile(BRIDGE / "t068_document_batch_adapter.gd", project / "batch_adapter.gd")
        shutil.copyfile(BRIDGE / "t068_document_batch_smoke.gd", project / "batch_test.gd")
        shutil.copyfile(BRIDGE / "t068_document_sparse_adapter.gd", project / "sparse_adapter.gd")
        shutil.copyfile(BRIDGE / "t068_document_sparse_smoke.gd", project / "sparse_test.gd")
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
            xvfb = shutil.which("xvfb-run")
            if xvfb is None:
                raise RuntimeError("Native texture readback witness requires xvfb-run")
            revision_output = checked_run([xvfb, "-a", "-s", "-screen 0 1280x720x24",
                                           godot, "--path", str(project), "--audio-driver", "Dummy",
                                           "--rendering-method", "gl_compatibility",
                                           "--script", "res://revision_test.gd"],
                                          cwd=project, timeout=120)
            revision_match = REVISION_RE.search(revision_output)
            if revision_match is None or int(revision_match.group(1)) < 300:
                raise RuntimeError(f"Missing or insufficient revision checks:\n{revision_output[-4000:]}")
            # Real DrawingDocument transactions need no GL readback. Exercise
            # them headlessly, keeping the isolated extension explicit.
            document_output = checked_run([godot, "--headless", "--path", str(project),
                                           "--audio-driver", "Dummy", "--script",
                                           "res://document_test.gd"], cwd=project, timeout=120)
            document_match = DOCUMENT_RE.search(document_output)
            if document_match is None or int(document_match.group(1)) < 140:
                raise RuntimeError(f"Missing or insufficient canonical document checks:\n{document_output[-4000:]}")
            batch_output = checked_run([godot, "--headless", "--path", str(project),
                                        "--audio-driver", "Dummy", "--script",
                                        "res://batch_test.gd"], cwd=project, timeout=120)
            batch_match = BATCH_RE.search(batch_output)
            if batch_match is None or int(batch_match.group(1)) != 128:
                raise RuntimeError(f"Missing or insufficient multi-tile checks:\n{batch_output[-4000:]}")
            sparse_output = checked_run([godot, "--headless", "--path", str(project),
                                         "--audio-driver", "Dummy", "--script",
                                         "res://sparse_test.gd"], cwd=project, timeout=120)
            sparse_match = SPARSE_RE.search(sparse_output)
            sparse_timing = SPARSE_TIMING_RE.search(sparse_output)
            if sparse_match is None or int(sparse_match.group(1)) < 173 or sparse_timing is None:
                raise RuntimeError(f"Missing or insufficient sparse checks/timing:\n{sparse_output[-4000:]}")
            sparse_benchmark = json.loads(sparse_timing.group(1))
            if any(str(side) not in sparse_benchmark for side in (32, 64, 128)):
                raise RuntimeError("Sparse benchmark omitted a test size")
            observations.append({"checks": count, "sparse_checks": int(sparse_match.group(1)),
                                 "sparse_benchmark": sparse_benchmark, "revision_checks": int(revision_match.group(1)),
                                 "document_checks": int(document_match.group(1)),
                                 "batch_checks": int(batch_match.group(1)),
                                 "bridge_latency_us": json.loads(timing.group(1))})
        return {
            "ticket": "T-068", "mode": "optional, isolated Linux GDExtension (not production)",
            "godot_version": version, "generated_header_sha256": header_sha,
            "test_method": "Checked native batch, detached texture adapter, and real single/multiple-tile DrawingDocument transactions",
            "measurements": observations,
            "limitations": [
                "Canonical DrawingDocument and DrawingEditSession are exercised in a temporary test project; production Drawing UI/Atlas history do not load this backend",
                "Whole-tile and sparse-delta paths both commit through DrawingEditSession; neither is production enabled or proven faster",
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
    print(f"T068_GDEXTENSION_INTEGRATION_PASSED: {counts} native parity checks per run")
    print("Revision-guarded publication adapter:", ", ".join(str(item["revision_checks"]) for item in evidence["measurements"]), "checks per run")
    print("Canonical DrawingDocument transactions:", ", ".join(str(item["document_checks"]) for item in evidence["measurements"]), "checks per run")
    print("Atomic multi-tile transactions:", ", ".join(str(item["batch_checks"]) for item in evidence["measurements"]), "checks per run")
    print("Sparse delta transaction parity:", ", ".join(str(item["sparse_checks"]) for item in evidence["measurements"]), "checks per run")
    print("Timings are diagnostic only; no production backend enabled.")


if __name__ == "__main__":
    main()
